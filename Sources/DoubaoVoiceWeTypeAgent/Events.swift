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

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if isTriggerKeycode(keycode) {
            // The trigger key's keycode filters out ordinary ⌘-shortcuts (e.g. ⌘C
            // uses the *left* ⌘, keycode 55, not the right ⌘, keycode 54). For the
            // matching keycode, the presence of the modifier flag in event.flags
            // tells us whether this flagsChanged is a press (flag set) or release
            // (flag cleared). It is safe to read the flag here because we already
            // know the exact keycode.
            let spec = cachedTriggerKeySpec()
            let isDown = event.flags.contains(spec.flag)
            if isDown {
                mutateRuntime { $0.physicalComboDown = true }
                return handlePhysicalComboDown(event)
            }
            mutateRuntime { $0.physicalComboDown = false }
            return handlePhysicalComboUp(event)
        }

        // Any other modifier change: swallow while we are managing a hold so the
        // user's stray modifiers do not leak to the foreground app; otherwise
        // pass it through untouched.
        return readRuntime({ $0.managingHold }) ? nil : Unmanaged.passUnretained(event)
    }

    private func handleTapDisabled(_ type: CGEventType, event: CGEvent) {
        let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
        DispatchQueue.main.async { [weak self] in
            self?.reenableEventTapAfterDisable(reason)
        }
    }

    private func handlePhysicalComboDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let current = currentInputID() ?? "unknown"
        let alreadyVoice = isVoiceInput(current)

        let activationID = startManagedHold(wasAlreadyVoice: alreadyVoice)
        mutateRuntime {
            $0.currentInputID = current
            $0.originalInputID = current
        }
        worker.async { [weak self] in
            self?.beginManagedHold(activationID: activationID, initialInputID: current)
        }
        // Suppress the physical trigger key: it is decoupled from the voice
        // shortcut, so the foreground app never needs to see it.
        return nil
    }

    private func startManagedHold(wasAlreadyVoice: Bool) -> Int {
        var activationID = 0
        mutateRuntime {
            $0.activationID += 1
            activationID = $0.activationID
            $0.mode = .switching
            $0.managingHold = true
            $0.passThroughPhysicalCombo = false
            $0.syntheticDownPosted = false
            $0.wasAlreadyVoice = wasAlreadyVoice
            $0.lastActivationResult = "starting"
            $0.lastProbeWindow = nil
            $0.lastProbeWindowOwner = nil
            $0.lastProbeWindowName = nil
            $0.lastProbeWindowBounds = nil
            $0.lastEvent = "\(triggerKeyDescription()) down"
            $0.lastError = nil
        }
        updateStatusUI()
        log("trigger down (\(triggerKeyDescription())); wasAlreadyVoice=\(wasAlreadyVoice); replay=\(voiceShortcutDescription()); activationID=\(activationID)")
        return activationID
    }

    private func handlePhysicalComboUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        var managing = false
        var activationID = 0
        mutateRuntime {
            managing = $0.managingHold
            activationID = $0.activationID
            $0.passThroughPhysicalCombo = false
            $0.lastEvent = "\(triggerKeyDescription()) released, managed=\(managing)"
        }
        log("trigger released (\(triggerKeyDescription())); managing=\(managing), activationID=\(activationID)")

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
        recordWorkerComboDown(current, activationID: activationID)

        guard isActivationCurrent(activationID) else {
            log("activation \(activationID) became stale before voice input switch; skip")
            return
        }

        guard prepareVoiceInput(current: current) else {
            failAndRestoreManagedHold(
                activationID: activationID,
                event: "failed to switch voice input",
                error: "cannot switch to voice input"
            )
            log("failed to switch/settle voice input; abort managing hold")
            return
        }

        guard sleepWhileHoldActive(activationID: activationID, milliseconds: config.voiceSettleDelayMs) else {
            cancelActivationBeforeReady(activationID: activationID)
            return
        }

        runVoiceActivation(activationID: activationID)
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

        let startPosted = readRuntime { $0.syntheticDownPosted }
        if startPosted {
            postVoiceShortcutUp()
            log("activation \(activationID) voice shortcut up posted")
        } else {
            log("release before voice shortcut down; skip shortcut up")
        }

        if readRuntime({ $0.wasAlreadyVoice }) {
            // The user was already on the voice IME before holding the trigger;
            // leave them on it instead of forcing a switch to the restore IME.
            markHoldFinishedWithoutRestore()
            log("activation \(activationID) finished; stayed on voice input (was already active)")
            updateStatusUIOnMain()
            return
        }

        usleep(config.restoreInputDelayMs * 1000)
        restoreAfterManagedHold()
        updateStatusUIOnMain()
    }

    private func markHoldFinishedWithoutRestore() {
        mutateRuntime {
            $0.mode = .ready
            $0.managingHold = false
            $0.passThroughPhysicalCombo = false
            $0.syntheticDownPosted = false
            $0.currentInputID = currentInputID() ?? config.voiceInputID
            $0.lastEvent = "voice hold finished; stayed on voice input"
            $0.lastError = nil
        }
    }

    private func restoreAfterManagedHold(event: String = "restored input method", error: String? = nil) {
        // Restore to whatever the user was on before the hold, not a hardcoded IME.
        let captured = readRuntime { $0.originalInputID } ?? config.restoreInputID
        let target = isVoiceInput(captured) ? config.restoreInputID : captured
        if selectAndSettleInput(target, settleMs: 60) {
            markRestoreResult(mode: .ready, target: target, event: event, error: error)
            log("restored input to \(displayInputName(target))")
        } else {
            markRestoreResult(mode: .error, target: target, event: "failed to restore input method", error: "cannot switch back to restore input")
            log("failed to restore input to \(displayInputName(target))")
        }
    }

    private func markRestoreResult(mode: AgentMode, target: String, event: String, error: String?) {
        mutateRuntime {
            $0.mode = mode
            $0.managingHold = false
            $0.passThroughPhysicalCombo = false
            $0.syntheticDownPosted = false
            $0.currentInputID = mode == .ready ? target : (currentInputID() ?? "unknown")
            $0.lastEvent = event
            $0.lastError = error
        }
    }

    private func recordWorkerComboDown(_ current: String, activationID: Int) {
        mutateRuntime {
            $0.currentInputID = current
            $0.originalInputID = current
            $0.lastEvent = "\(triggerKeyDescription()) down, current=\(displayInputName(current))"
        }
        log("activation \(activationID) current input=\(current)")
    }

    private func prepareVoiceInput(current: String) -> Bool {
        log("switching to voice input; triggerDelayMs=\(config.voiceSettleDelayMs)")
        if isVoiceInput(current) {
            return true
        }
        return selectAndSettleInput(config.voiceInputID, settleMs: 0)
    }

    // Closed-loop activation: post the replayed voice shortcut down, then confirm
    // voice actually started using a screen-independent readiness signal
    // (microphone running, or a new Doubao-owned window as fallback). If it did
    // not start in time, do a CLEAN re-trigger (up then down) so the next press is
    // a real edge, bounded by voiceMaxRetries. This replaces the old fixed-delay
    // fire-and-hope and the abandoned geometry-based probe.
    private func runVoiceActivation(activationID: Int) {
        let signal = config.voiceReadinessSignal.lowercased()
        let probe = VoiceUIProbe(ownerNames: config.voiceUIWindowOwnerNames)
        let windowBaseline = probe.snapshot()
        let micBaselineRunning = MicMonitor.isInputRunningSomewhere()

        // Microphone is the preferred signal, but it is useless if the mic was
        // already running before we triggered (e.g. the user is in a call), so in
        // that case fall back to a new Doubao-owned window. "none" disables
        // verification entirely (fire-and-hold).
        let useMic = signal == "microphone" && !micBaselineRunning
        let useWindow = signal == "window" || (signal == "microphone" && micBaselineRunning)
        if micBaselineRunning && signal == "microphone" {
            log("activation \(activationID) mic already running at baseline; using window fallback")
        }

        let maxAttempts = Int(config.voiceMaxRetries) + 1
        var attempt = 1
        while true {
            guard isHoldActive(activationID) else {
                cancelActivationBeforeReady(activationID: activationID)
                return
            }

            postVoiceShortcutDown()
            mutateRuntime {
                $0.mode = .holding
                $0.syntheticDownPosted = true
                $0.currentInputID = config.voiceInputID
                $0.lastEvent = "voice shortcut down posted (attempt \(attempt))"
                $0.lastActivationResult = "attempt \(attempt) posted; verifying"
                $0.lastError = nil
            }
            log("activation \(activationID) voice shortcut down posted attempt=\(attempt) signal=\(signal)")
            updateStatusUIOnMain()

            if !useMic && !useWindow {
                markVoiceHolding(activationID: activationID, detail: "no verify signal; assumed started")
                return
            }

            let detected: Bool
            if useMic {
                detected = MicMonitor.waitForInputRunning(
                    timeoutMs: config.voiceVerifyTimeoutMs,
                    shouldContinue: { self.isHoldActive(activationID) }
                )
            } else {
                detected = probe.waitForNewOwnedWindow(
                    baseline: windowBaseline,
                    timeoutMs: config.voiceVerifyTimeoutMs,
                    shouldContinue: { self.isHoldActive(activationID) }
                ) != nil
            }

            if detected {
                markVoiceHolding(activationID: activationID, detail: "\(useMic ? "mic" : "window") detected on attempt \(attempt)")
                return
            }

            guard isHoldActive(activationID) else {
                cancelActivationBeforeReady(activationID: activationID)
                return
            }

            if attempt >= maxAttempts {
                // Best effort: keep the shortcut held so a late start still works.
                mutateRuntime {
                    $0.lastActivationResult = "verify failed after \(attempt) attempt(s); holding anyway"
                    $0.lastError = "voice readiness not detected"
                }
                log("activation \(activationID) verify failed after \(attempt) attempt(s); holding anyway")
                updateStatusUIOnMain()
                return
            }

            // Re-trigger without posting up: the IME may still be starting and an up
            // event would kill it. Just wait a gap and post down again — the IME
            // interprets repeated downs as the user pressing the shortcut again, harmless.
            log("activation \(activationID) attempt \(attempt) no readiness; re-triggering")
            guard sleepWhileHoldActive(activationID: activationID, milliseconds: config.voiceRetryGapMs) else {
                cancelActivationBeforeReady(activationID: activationID)
                return
            }
            attempt += 1
        }
    }

    private func markVoiceHolding(activationID: Int, detail: String) {
        mutateRuntime {
            $0.mode = .holding
            $0.syntheticDownPosted = true
            $0.currentInputID = config.voiceInputID
            $0.lastEvent = "voice started: \(detail)"
            $0.lastActivationResult = detail
            $0.lastError = nil
        }
        log("activation \(activationID) voice started: \(detail)")
        updateStatusUIOnMain()
    }

    private func cancelActivationBeforeReady(activationID: Int) {
        guard isActivationCurrent(activationID) else {
            log("activation \(activationID) cancelled after becoming stale; skip restore")
            return
        }

        releaseVoiceShortcutIfNeeded()
        mutateRuntime {
            $0.lastEvent = "released before voice input became ready"
            $0.lastActivationResult = "cancelled by release"
            $0.managingHold = false
            $0.passThroughPhysicalCombo = false
            $0.syntheticDownPosted = false
        }
        log("activation \(activationID) cancelled before voice shortcut down")
        restoreAfterManagedHold(event: "released before voice shortcut; restored input")
        updateStatusUIOnMain()
    }

    private func releaseVoiceShortcutIfNeeded() {
        let syntheticDownPosted = readRuntime { $0.syntheticDownPosted }
        guard syntheticDownPosted else { return }
        postVoiceShortcutUp()
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
