import CoreAudio
import Foundation

// Detects whether the default audio input device is "running somewhere", i.e.
// some process has the microphone open. Doubao voice input opens the mic for
// speech recognition (the IME bundle declares NSMicrophoneUsageDescription), so
// a rising edge of this signal is a screen-independent confirmation that voice
// actually started — unlike window geometry, it does not depend on resolution,
// Dock, or which display is active.
//
// Reading this property is device-state inspection, not capture, so it does NOT
// require the Microphone privacy permission.
enum MicMonitor {
    static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    static func isInputRunningSomewhere() -> Bool {
        guard let device = defaultInputDeviceID() else { return false }
        var isRunning = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &isRunning)
        guard status == noErr else { return false }
        return isRunning != 0
    }

    // Wait until the default input device starts running somewhere. The caller is
    // responsible for ensuring the mic was NOT already running before triggering
    // (otherwise this returns true immediately and tells you nothing). Returns
    // true on detection, false on timeout or cancellation via shouldContinue.
    static func waitForInputRunning(
        timeoutMs: UInt32,
        pollMs: UInt32 = 20,
        shouldContinue: () -> Bool = { true }
    ) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline && shouldContinue() {
            if isInputRunningSomewhere() { return true }
            usleep(pollMs * 1000)
        }
        return false
    }
}
