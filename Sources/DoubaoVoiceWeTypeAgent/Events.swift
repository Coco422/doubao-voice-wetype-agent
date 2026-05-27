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
        recordComboDown(current)

        if isVoiceInput(current) {
            passThroughAlreadyVoiceInput()
            return Unmanaged.passUnretained(event)
        }

        mutateRuntime {
            $0.mode = .switching
            $0.managingHold = true
            $0.syntheticDownPosted = false
        }
        updateStatusUI()

        worker.async { [weak self] in
            self?.beginManagedHold()
        }
        return nil
    }

    private func recordComboDown(_ current: String) {
        mutateRuntime {
            $0.currentInputID = current
            $0.originalInputID = current
            $0.lastEvent = "cmd+option down, current=\(displayInputName(current))"
        }
        log("physical cmd+option down, current=\(current)")
    }

    private func passThroughAlreadyVoiceInput() {
        mutateRuntime {
            $0.mode = .ready
            $0.managingHold = false
            $0.syntheticDownPosted = false
            $0.lastEvent = "already voice input; pass through"
        }
        updateStatusUI()
        log("already voice input; pass through")
    }

    private func handlePhysicalComboUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let managing = readRuntime { $0.managingHold }
        mutateRuntime {
            $0.lastEvent = "cmd+option released, managed=\(managing)"
        }
        log("physical cmd+option released; managing=\(managing)")

        if managing {
            worker.async { [weak self] in
                self?.endManagedHold()
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func beginManagedHold() {
        guard selectAndSettleInput(config.voiceInputID, settleMs: 260) else {
            markManagedHoldFailure(event: "failed to switch voice input", error: "cannot switch to voice input")
            log("failed to switch/settle voice input; abort managing hold")
            return
        }

        let shouldPostDown = readRuntime { $0.physicalComboDown && $0.managingHold }
        guard shouldPostDown else {
            mutateRuntime {
                $0.lastEvent = "released before voice input became ready"
                $0.syntheticDownPosted = false
            }
            log("combo released before voice input settled; skip synthetic down")
            updateStatusUIOnMain()
            return
        }

        postCmdOptDown()
        mutateRuntime {
            $0.mode = .holding
            $0.syntheticDownPosted = true
            $0.currentInputID = config.voiceInputID
            $0.lastEvent = "synthetic voice hold posted"
            $0.lastError = nil
        }
        updateStatusUIOnMain()
    }

    private func markManagedHoldFailure(event: String, error: String) {
        mutateRuntime {
            $0.mode = .error
            $0.managingHold = false
            $0.syntheticDownPosted = false
            $0.lastEvent = event
            $0.lastError = error
        }
        updateStatusUIOnMain()
    }

    private func endManagedHold() {
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

    private func restoreAfterManagedHold() {
        if selectAndSettleInput(config.restoreInputID, settleMs: 60) {
            markRestoreResult(mode: .ready, event: "restored input method", error: nil)
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
            $0.syntheticDownPosted = false
            $0.currentInputID = mode == .ready ? config.restoreInputID : (currentInputID() ?? "unknown")
            $0.lastEvent = event
            $0.lastError = error
        }
    }
}

let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let app = Unmanaged<AgentApp>.fromOpaque(refcon).takeUnretainedValue()
    return app.handleEvent(type, event: event)
}
