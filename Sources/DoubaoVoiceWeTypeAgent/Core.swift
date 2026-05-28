import ApplicationServices
import Carbon
import Foundation
import Quartz

struct AgentConfig {
    let launchdLabel: String
    let restoreInputID: String
    let voiceInputID: String
    let voiceInputAliases: Set<String>
    let configPath: String
    let logPath: String
    let statusPath: String
    let defaultVoiceSettleDelayMs: UInt32

    var voiceSettleDelayMs: UInt32 {
        configuredUInt32(
            configPath: configPath,
            fileKey: "voiceSettleDelayMs",
            envKey: "VOICE_SETTLE_DELAY_MS",
            defaultValue: defaultVoiceSettleDelayMs,
            range: 0...5_000
        )
    }

    static let `default`: AgentConfig = {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let appSupport = "\(home)/Library/Application Support/DoubaoVoiceWeTypeAgent"
        let configPath = env["DOUBAO_AGENT_CONFIG_PATH"] ?? "\(appSupport)/config.json"
        let voiceID = env["VOICE_IME_ID"] ?? "com.bytedance.inputmethod.doubaoime.pinyin"
        let aliasValue = env["VOICE_IME_ALIASES"] ?? "com.bytedance.inputmethod.doubaoime"
        let aliases = Set(aliasValue.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        let defaultVoiceSettleDelayMs: UInt32 = 500

        ensureDefaultConfigFile(
            path: configPath,
            voiceSettleDelayMs: defaultVoiceSettleDelayMs
        )

        return AgentConfig(
            launchdLabel: env["AGENT_LAUNCHD_LABEL"] ?? "com.github.Coco422.doubao-voice-wetype-agent",
            restoreInputID: env["RESTORE_IME_ID"] ?? "com.tencent.inputmethod.wetype.pinyin",
            voiceInputID: voiceID,
            voiceInputAliases: aliases.union([voiceID]),
            configPath: configPath,
            logPath: env["DOUBAO_AGENT_LOG_PATH"] ?? "\(home)/Library/Logs/doubao-voice-wetype-agent.log",
            statusPath: env["DOUBAO_AGENT_STATUS_PATH"] ?? "\(appSupport)/status.json",
            defaultVoiceSettleDelayMs: defaultVoiceSettleDelayMs
        )
    }()
}

let config = AgentConfig.default
let marker: Int64 = 0x4457425657545950 // DWBVWTYP

enum AgentMode: String {
    case starting = "starting"
    case ready = "ready"
    case switching = "switching"
    case holding = "holding"
    case needsPermission = "needs_permission"
    case tapDisabled = "tap_disabled"
    case error = "error"
}

struct RuntimeSnapshot {
    let mode: AgentMode
    let physicalComboDown: Bool
    let managingHold: Bool
    let syntheticDownPosted: Bool
    let eventTapReady: Bool
    let accessibilityOK: Bool
    let inputMonitoringOK: Bool
    let currentInputID: String
    let lastEvent: String
    let lastError: String?
    let tapRestartCount: Int
}

func ensureDefaultConfigFile(path: String, voiceSettleDelayMs: UInt32) {
    let url = URL(fileURLWithPath: path)
    guard !FileManager.default.fileExists(atPath: path) else { return }
    let payload: [String: Any] = [
        "voiceSettleDelayMs": voiceSettleDelayMs
    ]

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
        return
    }

    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try? data.write(to: url, options: .atomic)
}

func persistentConfig(path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data),
          let config = object as? [String: Any] else {
        return [:]
    }
    return config
}

func configuredUInt32(
    configPath: String,
    fileKey: String,
    envKey: String,
    defaultValue: UInt32,
    range: ClosedRange<UInt32>
) -> UInt32 {
    if let envValue = ProcessInfo.processInfo.environment[envKey],
       let parsed = parseUInt32(envValue) {
        return clampUInt32(parsed, to: range)
    }

    if let parsed = parseUInt32(persistentConfig(path: configPath)[fileKey]) {
        return clampUInt32(parsed, to: range)
    }

    return defaultValue
}

func parseUInt32(_ value: Any?) -> UInt32? {
    if let number = value as? NSNumber {
        let intValue = number.intValue
        return intValue >= 0 ? UInt32(intValue) : nil
    }

    if let string = value as? String {
        return UInt32(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return nil
}

func clampUInt32(_ value: UInt32, to range: ClosedRange<UInt32>) -> UInt32 {
    return min(max(value, range.lowerBound), range.upperBound)
}

final class RuntimeState {
    let lock = NSLock()
    var mode = AgentMode.starting
    var physicalComboDown = false
    var managingHold = false
    var syntheticDownPosted = false
    var originalInputID: String?
    var eventTapReady = false
    var accessibilityOK = false
    var inputMonitoringOK = false
    var currentInputID = "unknown"
    var lastEvent = "not triggered yet"
    var lastError: String?
    var tapRestartCount = 0
}

let runtime = RuntimeState()
let logLock = NSLock()
let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
    return formatter
}()

func log(_ message: String) {
    logLock.lock()
    defer { logLock.unlock() }

    let line = "\(logDateFormatter.string(from: Date())) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }

    let url = URL(fileURLWithPath: config.logPath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: config.logPath), let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

func mutateRuntime(_ change: (RuntimeState) -> Void) {
    runtime.lock.lock()
    change(runtime)
    runtime.lock.unlock()
}

func readRuntime<T>(_ read: (RuntimeState) -> T) -> T {
    runtime.lock.lock()
    let value = read(runtime)
    runtime.lock.unlock()
    return value
}

func snapshotRuntime() -> RuntimeSnapshot {
    return readRuntime {
        RuntimeSnapshot(
            mode: $0.mode,
            physicalComboDown: $0.physicalComboDown,
            managingHold: $0.managingHold,
            syntheticDownPosted: $0.syntheticDownPosted,
            eventTapReady: $0.eventTapReady,
            accessibilityOK: $0.accessibilityOK,
            inputMonitoringOK: $0.inputMonitoringOK,
            currentInputID: $0.currentInputID,
            lastEvent: $0.lastEvent,
            lastError: $0.lastError,
            tapRestartCount: $0.tapRestartCount
        )
    }
}

func getID(_ source: TISInputSource) -> String? {
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return unsafeBitCast(raw, to: CFString.self) as String
}

func currentInputID() -> String? {
    if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), let id = getID(current) { return id }
    if let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(), let id = getID(current) { return id }
    return nil
}

@discardableResult
func selectInput(_ id: String) -> Bool {
    let properties = [kTISPropertyInputSourceID: id] as CFDictionary
    let list = TISCreateInputSourceList(properties, false).takeRetainedValue() as NSArray
    guard list.count > 0 else { log("input source not found: \(id)"); return false }

    let source = list[0] as! TISInputSource
    let status = TISSelectInputSource(source)
    if status != noErr {
        log("select input failed \(id): \(status)")
        return false
    }
    return true
}

func waitForInput(_ id: String, timeoutMs: Int = 500) -> Bool {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
    var last = currentInputID() ?? "unknown"
    while Date() < deadline {
        last = currentInputID() ?? "unknown"
        if last == id { return true }
        usleep(20_000)
    }
    log("waitForInput timeout target=\(id), last=\(last)")
    return false
}

func selectAndSettleInput(_ id: String, settleMs: UInt32) -> Bool {
    guard selectInput(id) else { return false }
    guard waitForInput(id, timeoutMs: 600) else { return false }
    usleep(settleMs * 1000)
    return true
}

func postModifier(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { return }
    event.flags = flags
    event.setIntegerValueField(.eventSourceUserData, value: marker)
    event.post(tap: .cghidEventTap)
}

func postCmdOptDown() {
    postModifier(58, down: true, flags: [.maskAlternate])
    usleep(25_000)
    postModifier(55, down: true, flags: [.maskAlternate, .maskCommand])
    log("posted cmd+option down")
}

func postCmdOptUp() {
    postModifier(55, down: false, flags: [.maskAlternate])
    usleep(25_000)
    postModifier(58, down: false, flags: [])
    log("posted cmd+option up")
}

func relevantFlags(_ flags: CGEventFlags) -> CGEventFlags {
    return flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
}

func isCmdOptionOnly(_ flags: CGEventFlags) -> Bool {
    return relevantFlags(flags) == [.maskCommand, .maskAlternate]
}

func isVoiceInput(_ id: String) -> Bool {
    return config.voiceInputAliases.contains(id)
}

func displayInputName(_ id: String) -> String {
    if id == config.restoreInputID { return "restore input" }
    if isVoiceInput(id) { return "voice input" }
    return id
}

func writeStatusFile(_ snapshot: RuntimeSnapshot) {
    let payload: [String: Any] = [
        "updatedAt": ISO8601DateFormatter().string(from: Date()),
        "pid": ProcessInfo.processInfo.processIdentifier,
        "configPath": config.configPath,
        "voiceSettleDelayMs": config.voiceSettleDelayMs,
        "mode": snapshot.mode.rawValue,
        "eventTapReady": snapshot.eventTapReady,
        "accessibilityOK": snapshot.accessibilityOK,
        "inputMonitoringOK": snapshot.inputMonitoringOK,
        "currentInputID": snapshot.currentInputID,
        "currentInputName": displayInputName(snapshot.currentInputID),
        "physicalComboDown": snapshot.physicalComboDown,
        "managingHold": snapshot.managingHold,
        "syntheticDownPosted": snapshot.syntheticDownPosted,
        "lastEvent": snapshot.lastEvent,
        "lastError": snapshot.lastError ?? NSNull(),
        "tapRestartCount": snapshot.tapRestartCount
    ]

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
        return
    }

    let url = URL(fileURLWithPath: config.statusPath)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
}

func accessibilityTrusted(requestPrompt: Bool) -> Bool {
    if requestPrompt {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
    return AXIsProcessTrusted()
}

func inputMonitoringTrusted(requestPrompt: Bool) -> Bool {
    if CGPreflightListenEventAccess() { return true }
    return requestPrompt ? CGRequestListenEventAccess() : false
}
