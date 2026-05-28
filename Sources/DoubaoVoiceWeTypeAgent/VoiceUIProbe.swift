import Foundation
import Quartz

struct VoiceUIWindow: Hashable {
    let windowNumber: Int
    let ownerName: String
    let windowName: String
    let layer: Int
    let bounds: CGRect

    var signature: String {
        "\(windowNumber):\(ownerName):\(windowName):\(layer):\(Int(bounds.width))x\(Int(bounds.height))"
    }

    var logDescription: String {
        let name = windowName.isEmpty ? "<untitled>" : windowName
        return "owner=\(ownerName), name=\(name), layer=\(layer), bounds=\(boundsDescription)"
    }

    var boundsDescription: String {
        "x=\(Int(bounds.origin.x)),y=\(Int(bounds.origin.y)),w=\(Int(bounds.width)),h=\(Int(bounds.height))"
    }
}

final class VoiceUIProbe {
    private let ownerNames: [String]

    init(ownerNames: [String]) {
        self.ownerNames = ownerNames
    }

    func snapshot() -> [VoiceUIWindow] {
        return visibleWindows(requireOwnerMatch: true)
    }

    private func visibleWindows(requireOwnerMatch: Bool) -> [VoiceUIWindow] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return raw.compactMap { window(from: $0, requireOwnerMatch: requireOwnerMatch) }
    }

    func waitForNewWindow(
        baseline: [VoiceUIWindow],
        timeoutMs: UInt32,
        shouldContinue: () -> Bool = { true }
    ) -> VoiceUIWindow? {
        let baselineSignatures = Set(baseline.map(\.signature))
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var ignored = Set<String>()

        while Date() < deadline && shouldContinue() {
            let newWindows = snapshot().filter { !baselineSignatures.contains($0.signature) }
            if let window = newWindows.first(where: isLikelyVoicePanel) {
                return window
            }
            logIgnoredWindows(newWindows, seen: &ignored)
            usleep(40_000)
        }

        return nil
    }

    func runDiagnostics(durationMs: UInt32) {
        let baseline = visibleWindows(requireOwnerMatch: false)
        let baselineSignatures = Set(baseline.map(\.signature))
        let deadline = Date().addingTimeInterval(Double(durationMs) / 1000.0)
        var seen = Set<String>()

        log("voice probe diagnostics started owners=\(ownerNames.joined(separator: ",")), visibleBaseline=\(baseline.count)")
        while Date() < deadline {
            for window in visibleWindows(requireOwnerMatch: false)
            where !baselineSignatures.contains(window.signature) && !seen.contains(window.signature) {
                seen.insert(window.signature)
                log("voice probe diagnostics new window matchConfiguredOwner=\(matches(owner: window.ownerName, name: window.windowName)) likelyVoicePanel=\(isLikelyVoicePanel(window)) \(window.logDescription)")
            }
            usleep(100_000)
        }
        log("voice probe diagnostics finished newWindows=\(seen.count)")
    }

    private func window(from dict: [String: Any], requireOwnerMatch: Bool) -> VoiceUIWindow? {
        let owner = dict[kCGWindowOwnerName as String] as? String ?? ""
        let name = dict[kCGWindowName as String] as? String ?? ""
        guard !requireOwnerMatch || matches(owner: owner, name: name) else { return nil }

        let number = dict[kCGWindowNumber as String] as? Int ?? 0
        let layer = dict[kCGWindowLayer as String] as? Int ?? 0
        let alpha = dict[kCGWindowAlpha as String] as? Double ?? 1.0
        guard alpha > 0 else { return nil }

        let bounds = windowBounds(from: dict[kCGWindowBounds as String])
        guard bounds.width >= 20, bounds.height >= 20 else { return nil }

        return VoiceUIWindow(
            windowNumber: number,
            ownerName: owner,
            windowName: name,
            layer: layer,
            bounds: bounds
        )
    }

    private func logIgnoredWindows(_ windows: [VoiceUIWindow], seen: inout Set<String>) {
        for window in windows where !seen.contains(window.signature) {
            seen.insert(window.signature)
            log("voice probe ignored non-voice-panel \(window.logDescription)")
        }
    }

    private func isLikelyVoicePanel(_ window: VoiceUIWindow) -> Bool {
        let width = window.bounds.width
        let height = window.bounds.height
        guard width >= 50, width <= 420, height >= 20, height <= 150 else {
            return false
        }
        return isNearDisplayBottom(window.bounds)
    }

    private func isNearDisplayBottom(_ bounds: CGRect) -> Bool {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for display in activeDisplayBounds() where display.insetBy(dx: -80, dy: -80).contains(center) {
            let gap = display.maxY - bounds.maxY
            return gap >= -40 && gap <= 260
        }
        return false
    }

    private func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGDisplayBounds(CGMainDisplayID())]
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return [CGDisplayBounds(CGMainDisplayID())]
        }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    private func matches(owner: String, name: String) -> Bool {
        ownerNames.contains { candidate in
            contains(owner, candidate) || contains(name, candidate)
        }
    }

    private func contains(_ value: String, _ candidate: String) -> Bool {
        value.range(of: candidate, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func windowBounds(from raw: Any?) -> CGRect {
        guard let raw, CFGetTypeID(raw as CFTypeRef) == CFDictionaryGetTypeID() else {
            return .zero
        }
        return CGRect(dictionaryRepresentation: raw as! CFDictionary) ?? .zero
    }
}
