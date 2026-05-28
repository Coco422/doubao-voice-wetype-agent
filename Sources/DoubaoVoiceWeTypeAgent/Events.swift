import Foundation
import Quartz

extension AgentApp {
    func handleEvent(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleTapDisabled(type, event: event)
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == marker {
            return Unmanaged.passUnretained(event)
        }

        let comboDown = isCmdOptionOnly(event.flags)
        if comboDown {
            return handleComboDownEvent(event)
        }

        if readRuntime({ $0.physicalComboDown }) {
            mutateRuntime { $0.physicalComboDown = false }
            return handlePhysicalComboUp(event)
        }

        return readRuntime({ $0.managingHold }) ? nil : Unmanaged.passUnretained(event)
    }

    private func handleTapDisabled(_ type: CGEventType, event: CGEvent) {
        let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
        DispatchQueue.main.async { [weak self] in
            self?.reenableEventTapAfterDisable(reason)
        }
    }

    private func handleComboDownEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let shouldStart = readRuntime { !$0.physicalComboDown }
        if shouldStart {
            mutateRuntime { $0.physicalComboDown = true }
            return handlePhysicalComboDown(event)
        }

        if readRuntime({ $0.managingHold }) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handlePhysicalComboDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let current = currentInputID() ?? "unknown"
        if isVoiceInput(current) {
            passThroughAlreadyVoiceInput(current: current)
            return Unmanaged.passUnretained(event)
        }

        let activationID = startManagedHold()
        mutateRuntime {
            $0.currentInputID = current
            $0.originalInputID = current
        }
        worker.async { [weak self] in
            self?.beginManagedHold(activationID: activationID, initialInputID: current)
        }
        return nil
    }

    private func passThroughAlreadyVoiceInput(current: String) {
        mutateRuntime {
            $0.mode = .ready
            $0.managingHold = false
            $0.passThroughPhysicalCombo = true
            $0.syntheticDownPosted = false
            $0.currentInputID = current
            $0.originalInputID = current
            $0.lastEvent = "already voice input; pass through"
            $0.lastError = nil
        }
        updateStatusUI()
        log("already voice input; pass through current=\(current)")
    }

    private func startManagedHold() -> Int {
        var activationID = 0
        mutateRuntime {
            $0.activationID += 1
            activationID = $0.activationID
            $0.mode = .switching
            $0.managingHold = true
            $0.passThroughPhysicalCombo = false
            $0.syntheticDownPosted = false
            $0.activationAttemptCount = 0
            $0.lastActivationResult = "starting"
            $0.lastProbeWindow = nil
            $0.lastProbeWindowOwner = nil
            $0.lastProbeWindowName = nil
            $0.lastProbeWindowBounds = nil
            $0.lastEvent = "cmd+option down"
            $0.lastError = nil
        }
        updateStatusUI()
        log("physical cmd+option down; activationID=\(activationID)")
        return activationID
    }

    private func handlePhysicalComboUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        var managing = false
        var passThrough = false
        var activationID = 0
        let flags = modifierFlagDescription(event.flags)
        mutateRuntime {
            managing = $0.managingHold
            passThrough = $0.passThroughPhysicalCombo
            activationID = $0.activationID
            $0.passThroughPhysicalCombo = false
            $0.lastEvent = "cmd+option released, flags=\(flags), managed=\(managing)"
        }
        log("physical cmd+option released; flags=\(flags), managing=\(managing), activationID=\(activationID)")

        if passThrough {
            log("already voice input passthrough release")
            return Unmanaged.passUnretained(event)
        }

        if managing {
            worker.async { [weak self] in
                self?.endManagedHold(activationID: activationID)
            }
        }
        return nil
    }

    private func beginManagedHold(activationID: Int, initialInputID: String) {
        guard isActivationCurrent(activationID) else {
            log("activation \(activationID) is stale before input query; skip")
            return
        }

        let current = initialInputID
        let settleMs = config.voiceSettleDelayMs
        recordWorkerComboDown(current, activationID: activationID)

        guard isActivationCurrent(activationID) else {
            log("activation \(activationID) became stale before voice input switch; skip")
            return
        }

        guard prepareVoiceInput(current: current, settleMs: settleMs) else {
            failAndRestoreManagedHold(
                activationID: activationID,
                event: "failed to switch voice input",
                error: "cannot switch to voice input"
            )
            log("failed to switch/settle voice input; abort managing hold")
            return
        }

        runVoiceActivationLoop(activationID: activationID)
    }

    private func failAndRestoreManagedHold(activationID: Int, event: String, error: String) {
        guard isActivationCurrent(activationID) else {
            log("activation \(activationID) failed after becoming stale; skip restore")
            return
        }

        mutateRuntime {
            $0.mode = .error
            $0.managingHold = false
            $0.passThroughPhysicalCombo = false
            $0.syntheticDownPosted = false
            $0.lastEvent = event
            $0.lastError = error
        }
        restoreAfterManagedHold(event: "\(event); restored input", error: error)
        updateStatusUIOnMain()
    }

    private func endManagedHold(activationID: Int) {
        guard readRuntime({ $0.activationID == activationID && $0.managingHold }) else {
            log("managed hold already finished; skip release activationID=\(activationID)")
            return
        }

        mutateRuntime { $0.mode = .switching }
        updateStatusUIOnMain()

        let syntheticDownPosted = readRuntime { $0.syntheticDownPosted }
        if syntheticDownPosted {
            postCmdOptUp()
            usleep(150_000)
        } else {
            log("release without synthetic down; skip synthetic up")
        }

        restoreAfterManagedHold()
        updateStatusUIOnMain()
    }

    private func restoreAfterManagedHold(event: String = "restored input method", error: String? = nil) {
        if selectAndSettleInput(config.restoreInputID, settleMs: 60) {
            markRestoreResult(mode: .ready, event: event, error: error)
            log("restored input")
        } else {
            markRestoreResult(mode: .error, event: "failed to restore input method", error: "cannot switch back to restore input")
            log("failed to restore input")
        }
    }

    private func markRestoreResult(mode: AgentMode, event: String, error: String?) {
        mutateRuntime {
            $0.mode = mode
            $0.managingHold = false
            $0.passThroughPhysicalCombo = false
            $0.syntheticDownPosted = false
            $0.currentInputID = mode == .ready ? config.restoreInputID : (currentInputID() ?? "unknown")
            $0.lastEvent = event
            $0.lastError = error
        }
    }

    private func recordWorkerComboDown(_ current: String, activationID: Int) {
        mutateRuntime {
            $0.currentInputID = current
            $0.originalInputID = current
            $0.lastEvent = "cmd+option down, current=\(displayInputName(current))"
        }
        log("activation \(activationID) current input=\(current)")
    }

    private func prepareVoiceInput(current: String, settleMs: UInt32) -> Bool {
        log("switching to voice input; voiceSettleDelayMs=\(settleMs)")
        if isVoiceInput(current) {
            usleep(settleMs * 1000)
            return true
        }
        return selectAndSettleInput(config.voiceInputID, settleMs: settleMs)
    }

    private func runVoiceActivationLoop(activationID: Int) {
        let probe = VoiceUIProbe(ownerNames: config.voiceUIWindowOwnerNames)
        let baseline = probe.snapshot()
        log("activation \(activationID) voice probe baseline windows=\(baseline.count)")

        var attempt = 1
        while true {
            guard isHoldActive(activationID) else {
                markActivationReleasedBeforeReady(activationID: activationID)
                return
            }

            if tryVoiceActivationAttempt(activationID: activationID, attempt: attempt, baseline: baseline, probe: probe) { return }

            guard isHoldActive(activationID) else {
                cancelActivationBeforeReady(activationID: activationID)
                return
            }

            if shouldStopActivationAttempts(attempt: attempt) {
                markVoiceActivationFailed(activationID: activationID)
                return
            }

            guard sleepWhileHoldActive(activationID: activationID, milliseconds: config.voiceActivationRetryGapMs) else {
                cancelActivationBeforeReady(activationID: activationID)
                return
            }
            attempt += 1
        }
    }

    private func tryVoiceActivationAttempt(
        activationID: Int,
        attempt: Int,
        baseline: [VoiceUIWindow],
        probe: VoiceUIProbe
    ) -> Bool {
        markActivationAttempt(activationID: activationID, attempt: attempt)
        guard isHoldActive(activationID) else {
            mutateRuntime {
                $0.lastActivationResult = "attempt \(attempt) cancelled before synthetic down"
            }
            log("activation \(activationID) attempt \(attempt) cancelled before synthetic down")
            return false
        }

        postCmdOptDown()
        mutateRuntime { $0.syntheticDownPosted = true }

        if let window = probe.waitForNewWindow(
            baseline: baseline,
            timeoutMs: config.voiceActivationProbeTimeoutMs,
            shouldContinue: { self.isHoldActive(activationID) }
        ) {
            markVoiceActivationSuccess(window: window, attempt: attempt)
            return true
        }

        guard isHoldActive(activationID) else {
            releaseSyntheticHoldIfNeeded()
            mutateRuntime {
                $0.lastActivationResult = "attempt \(attempt) cancelled"
            }
            log("activation \(activationID) attempt \(attempt) cancelled before voice UI detected")
            return false
        }

        mutateRuntime {
            $0.syntheticDownPosted = true
            $0.lastActivationResult = "attempt \(attempt) no voice UI; keeping down"
        }
        log("activation \(activationID) attempt \(attempt) no voice UI detected; keeping synthetic down")
        return false
    }

    private func markActivationAttempt(activationID: Int, attempt: Int) {
        mutateRuntime {
            $0.activationAttemptCount = attempt
            $0.lastActivationResult = "attempt \(attempt) probing"
            $0.lastEvent = "voice activation attempt \(attempt)"
            $0.lastError = nil
        }
        log("activation \(activationID) attempt \(attempt) start")
        updateStatusUIOnMain()
    }

    private func markVoiceActivationSuccess(window: VoiceUIWindow, attempt: Int) {
        mutateRuntime {
            $0.mode = .holding
            $0.syntheticDownPosted = true
            $0.currentInputID = config.voiceInputID
            $0.lastEvent = "voice UI detected on attempt \(attempt)"
            $0.lastActivationResult = "detected on attempt \(attempt)"
            $0.lastProbeWindow = window.logDescription
            $0.lastProbeWindowOwner = window.ownerName
            $0.lastProbeWindowName = window.windowName
            $0.lastProbeWindowBounds = window.boundsDescription
            $0.lastError = nil
        }
        log("voice UI detected attempt=\(attempt) \(window.logDescription)")
        updateStatusUIOnMain()
    }

    private func markVoiceActivationFailed(activationID: Int) {
        guard isActivationCurrent(activationID) else {
            log("activation \(activationID) failed after becoming stale; skip")
            return
        }

        releaseSyntheticHoldIfNeeded()
        mutateRuntime {
            $0.managingHold = false
            $0.passThroughPhysicalCombo = false
            $0.syntheticDownPosted = false
            $0.lastActivationResult = "failed after \($0.activationAttemptCount) attempts"
        }
        log("voice activation failed activationID=\(activationID)")
        restoreAfterManagedHold(event: "voice activation failed; restored input", error: "voice UI not detected")
        updateStatusUIOnMain()
    }

    private func markActivationReleasedBeforeReady(activationID: Int) {
        cancelActivationBeforeReady(activationID: activationID)
    }

    private func cancelActivationBeforeReady(activationID: Int) {
        guard isActivationCurrent(activationID) else {
            log("activation \(activationID) cancelled after becoming stale; skip restore")
            return
        }

        releaseSyntheticHoldIfNeeded()
        mutateRuntime {
            $0.lastEvent = "released before voice input became ready"
            $0.lastActivationResult = "cancelled by release"
            $0.managingHold = false
            $0.passThroughPhysicalCombo = false
            $0.syntheticDownPosted = false
        }
        log("activation \(activationID) cancelled before voice UI detected")
        restoreAfterManagedHold(event: "released before voice UI; restored input")
        updateStatusUIOnMain()
    }

    private func shouldStopActivationAttempts(attempt: Int) -> Bool {
        let maxAttempts = config.voiceActivationMaxAttempts
        return maxAttempts > 0 && attempt >= maxAttempts
    }

    private func releaseSyntheticHoldIfNeeded() {
        let syntheticDownPosted = readRuntime { $0.syntheticDownPosted }
        guard syntheticDownPosted else { return }
        postCmdOptUp()
        mutateRuntime { $0.syntheticDownPosted = false }
    }

    private func sleepWhileHoldActive(activationID: Int, milliseconds: UInt32) -> Bool {
        var remaining = milliseconds
        while remaining > 0 {
            guard isHoldActive(activationID) else { return false }
            let chunk = min(remaining, 20)
            usleep(chunk * 1000)
            remaining -= chunk
        }
        return isHoldActive(activationID)
    }

    private func isActivationCurrent(_ activationID: Int) -> Bool {
        readRuntime { $0.activationID == activationID && $0.managingHold }
    }

    private func isHoldActive(_ activationID: Int) -> Bool {
        readRuntime {
            $0.activationID == activationID && $0.physicalComboDown && $0.managingHold
        }
    }
}

let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let app = Unmanaged<AgentApp>.fromOpaque(refcon).takeUnretainedValue()
    return app.handleEvent(type, event: event)
}
