import AppKit
import Darwin
import Foundation
import Quartz

final class AgentApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let worker = DispatchQueue(label: "dev.doubao-voice-wetype-agent.worker")
    var eventTap: CFMachPort?

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem()
    private let permissionsMenuItem = NSMenuItem()
    private let inputMenuItem = NSMenuItem()
    private let timingMenuItem = NSMenuItem()
    private let activationMenuItem = NSMenuItem()
    private let probeWindowMenuItem = NSMenuItem()
    private let lastEventMenuItem = NSMenuItem()
    private let tapMenuItem = NSMenuItem()
    private var statusTimer: Timer?
    private var retryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if InstallCoordinator.prepareInstalledLaunchIfNeeded() {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        refreshPermissions(requestPrompt: false)
        installEventTap()
        startTimers()
        log("agent mini app started pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        log("agent mini app stopped")
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "豆 ..."
        item.button?.toolTip = "Voice IME hold agent"
        statusItem = item

        menu.delegate = self
        addReadOnlyMenuItems()
        addActionMenuItems()
        item.menu = menu
        updateStatusUI()
    }

    private func addReadOnlyMenuItems() {
        [statusMenuItem, permissionsMenuItem, inputMenuItem, timingMenuItem, activationMenuItem, probeWindowMenuItem, tapMenuItem, lastEventMenuItem].forEach {
            $0.isEnabled = false
            menu.addItem($0)
        }
        menu.addItem(.separator())
    }

    private func addActionMenuItems() {
        menu.addItem(NSMenuItem(title: "Retry permissions/tap", action: #selector(retryNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Accessibility settings", action: #selector(openAccessibilitySettings), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "Open Input Monitoring settings", action: #selector(openInputMonitoringSettings), keyEquivalent: "i"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Restore input method", action: #selector(restoreInputNow), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Run voice probe diagnostics", action: #selector(runVoiceProbeDiagnostics), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Open config", action: #selector(openConfig), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Restart agent", action: #selector(restartAgent), keyEquivalent: "q"))
        menu.addItem(NSMenuItem(title: "Quit agent", action: #selector(quitAgent), keyEquivalent: "x"))
    }

    private func startTimers() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshCurrentInput()
            self?.refreshPermissions(requestPrompt: false)
            self?.updateStatusUI()
        }

        retryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let snapshot = snapshotRuntime()
            if !snapshot.eventTapReady || snapshot.mode == .needsPermission || snapshot.mode == .tapDisabled {
                self.installEventTap()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshCurrentInput()
        refreshPermissions(requestPrompt: false)
        updateStatusUI()
    }

    func refreshCurrentInput() {
        let id = currentInputID() ?? "unknown"
        mutateRuntime { $0.currentInputID = id }
        refreshVoiceShortcutCache()
    }

    func refreshPermissions(requestPrompt: Bool) {
        let axOK = accessibilityTrusted(requestPrompt: requestPrompt)
        let inputOK = inputMonitoringTrusted(requestPrompt: requestPrompt)
        mutateRuntime {
            $0.accessibilityOK = axOK
            $0.inputMonitoringOK = inputOK
        }
    }

    func installEventTap() {
        refreshPermissions(requestPrompt: false)
        let permissions = snapshotRuntime()
        guard permissions.accessibilityOK && permissions.inputMonitoringOK else {
            markTapUnavailable(
                mode: .needsPermission,
                event: "waiting for permissions",
                error: "Accessibility=\(permissions.accessibilityOK), InputMonitoring=\(permissions.inputMonitoringOK)"
            )
            return
        }

        invalidateEventTap()
        guard let newTap = makeEventTap() else {
            markTapUnavailable(mode: .needsPermission, event: "event tap creation failed", error: "re-grant Accessibility and Input Monitoring")
            log("failed to create event tap; grant Accessibility/Input Monitoring permission")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        eventTap = newTap
        markTapReady(event: "event tap ready")
        log("event tap installed")
    }

    private func invalidateEventTap() {
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    private func makeEventTap() -> CFMachPort? {
        let events = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: events,
            callback: eventTapCallback,
            userInfo: refcon
        )
    }

    func markTapReady(event: String) {
        mutateRuntime {
            $0.mode = .ready
            $0.eventTapReady = true
            $0.lastError = nil
            $0.lastEvent = event
            $0.tapRestartCount += 1
        }
        updateStatusUI()
    }

    func markTapUnavailable(mode: AgentMode, event: String, error: String?) {
        let previous = snapshotRuntime()
        mutateRuntime {
            $0.mode = mode
            $0.eventTapReady = false
            $0.lastEvent = event
            $0.lastError = error
        }
        if previous.mode != mode || previous.lastEvent != event || previous.lastError != error {
            log("status unavailable mode=\(mode.rawValue), event=\(event), error=\(error ?? "none")")
        }
        updateStatusUI()
    }

    func reenableEventTapAfterDisable(_ reason: String) {
        markTapUnavailable(mode: .tapDisabled, event: "event tap disabled by macOS", error: reason)
        log("event tap disabled: \(reason)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                self.markTapReady(event: "event tap re-enabled")
                log("event tap re-enabled")
            } else {
                self.installEventTap()
            }
        }
    }

    func updateStatusUIOnMain() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusUI()
        }
    }

    func updateStatusUI() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.updateStatusUI() }
            return
        }

        let snapshot = snapshotRuntime()
        statusItem?.button?.title = statusTitle(for: snapshot)
        statusItem?.button?.toolTip = statusTooltip(for: snapshot)
        statusMenuItem.title = "Status: \(snapshot.mode.rawValue)"
        permissionsMenuItem.title = "Permissions: AX \(snapshot.accessibilityOK ? "OK" : "missing") / Input \(snapshot.inputMonitoringOK ? "OK" : "missing")"
        inputMenuItem.title = "Current input: \(displayInputName(snapshot.currentInputID))"
        timingMenuItem.title = "Voice: \(voiceShortcutDescription()) / trigger \(config.voiceSettleDelayMs) ms / restore \(config.restoreInputDelayMs) ms"
        activationMenuItem.title = "Activation: \(snapshot.lastActivationResult)"
        probeWindowMenuItem.title = "Probe window: \(snapshot.lastProbeWindow ?? "none")"
        tapMenuItem.title = "Tap: \(snapshot.eventTapReady ? "enabled" : "disabled") / restarts \(snapshot.tapRestartCount)"
        lastEventMenuItem.title = "Last: \(snapshot.lastEvent)"
        writeStatusFile(snapshot)
    }

    private func statusTitle(for snapshot: RuntimeSnapshot) -> String {
        switch snapshot.mode {
        case .ready:
            return snapshot.eventTapReady ? "豆 OK" : "豆 !"
        case .holding:
            return "豆 REC"
        case .switching, .starting:
            return "豆 ..."
        case .needsPermission, .tapDisabled, .error:
            return "豆 !"
        }
    }

    private func statusTooltip(for snapshot: RuntimeSnapshot) -> String {
        [
            "Status: \(snapshot.mode.rawValue)",
            "Accessibility: \(snapshot.accessibilityOK ? "OK" : "missing"), Input Monitoring: \(snapshot.inputMonitoringOK ? "OK" : "missing")",
            "Input: \(displayInputName(snapshot.currentInputID))",
            snapshot.lastError.map { "Error: \($0)" }
        ].compactMap { $0 }.joined(separator: "\n")
    }

    @objc private func retryNow() {
        refreshPermissions(requestPrompt: true)
        installEventTap()
        updateStatusUI()
    }

    @objc private func openAccessibilitySettings() {
        openSettings(anchor: "Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        openSettings(anchor: "Privacy_ListenEvent")
    }

    private func openSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        if !NSWorkspace.shared.open(url),
           let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallback)
        }
    }

    @objc private func restoreInputNow() {
        worker.async {
            _ = selectAndSettleInput(config.restoreInputID, settleMs: 60)
            mutateRuntime {
                $0.mode = .ready
                $0.managingHold = false
                $0.syntheticDownPosted = false
                $0.currentInputID = config.restoreInputID
                $0.lastEvent = "manually restored input"
                $0.lastError = nil
            }
            log("manual restore input")
            self.updateStatusUIOnMain()
        }
    }

    @objc private func openLog() {
        let url = URL(fileURLWithPath: config.logPath)
        if !FileManager.default.fileExists(atPath: config.logPath) {
            FileManager.default.createFile(atPath: config.logPath, contents: nil)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openConfig() {
        ensureDefaultConfigFile(path: config.configPath, defaults: config.defaultPersistentConfig)
        NSWorkspace.shared.open(URL(fileURLWithPath: config.configPath))
    }

    @objc private func runVoiceProbeDiagnostics() {
        mutateRuntime {
            $0.lastEvent = "voice probe diagnostics running"
            $0.lastActivationResult = "diagnostics running"
            $0.lastProbeWindow = nil
            $0.lastProbeWindowOwner = nil
            $0.lastProbeWindowName = nil
            $0.lastProbeWindowBounds = nil
        }
        updateStatusUI()

        worker.async { [weak self] in
            VoiceUIProbe(ownerNames: config.voiceUIWindowOwnerNames).runDiagnostics(durationMs: 3_000)
            mutateRuntime {
                $0.lastEvent = "voice probe diagnostics finished"
                $0.lastActivationResult = "diagnostics finished"
            }
            self?.updateStatusUIOnMain()
        }
    }

    @objc private func restartAgent() {
        log("agent restart requested from menu")
        exit(0)
    }

    @objc private func quitAgent() {
        log("agent quit requested from menu")
        bootoutLaunchAgent()
        NSApp.terminate(nil)
    }

    private func bootoutLaunchAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(config.launchdLabel)"]

        do {
            try process.run()
        } catch {
            log("failed to bootout launch agent \(config.launchdLabel): \(error)")
        }
    }
}
