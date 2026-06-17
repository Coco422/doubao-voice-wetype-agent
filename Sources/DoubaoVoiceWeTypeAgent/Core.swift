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
    let defaultRestoreInputDelayMs: UInt32
    let defaultVoiceShortcutModifiers: [String]
    let defaultVoiceUIWindowOwnerNames: [String]
    let defaultTriggerKey: String
    let defaultVoiceVerifyTimeoutMs: UInt32
    let defaultVoiceRetryGapMs: UInt32
    let defaultVoiceMaxRetries: UInt32
    let defaultVoiceReadinessSignal: String

    var defaultPersistentConfig: [String: Any] {
        [
            "voiceSettleDelayMs": defaultVoiceSettleDelayMs,
            "restoreInputDelayMs": defaultRestoreInputDelayMs,
            "voiceShortcutModifiers": defaultVoiceShortcutModifiers,
            "voiceUIWindowOwnerNames": defaultVoiceUIWindowOwnerNames,
            "triggerKey": defaultTriggerKey,
            "voiceVerifyTimeoutMs": defaultVoiceVerifyTimeoutMs,
            "voiceRetryGapMs": defaultVoiceRetryGapMs,
            "voiceMaxRetries": defaultVoiceMaxRetries,
            "voiceReadinessSignal": defaultVoiceReadinessSignal
        ]
    }

    var voiceSettleDelayMs: UInt32 {
        configuredUInt32(
            configPath: configPath,
            fileKey: "voiceSettleDelayMs",
            envKey: "VOICE_SETTLE_DELAY_MS",
            defaultValue: defaultVoiceSettleDelayMs,
            range: 0...5_000
        )
    }

    var restoreInputDelayMs: UInt32 {
        configuredUInt32(
            configPath: configPath,
            fileKey: "restoreInputDelayMs",
            envKey: "RESTORE_INPUT_DELAY_MS",
            defaultValue: defaultRestoreInputDelayMs,
            range: 0...5_000
        )
    }

    var voiceShortcutModifiers: [String] {
        configuredStringArray(
            configPath: configPath,
            fileKey: "voiceShortcutModifiers",
            envKey: "VOICE_SHORTCUT_MODIFIERS",
            defaultValue: defaultVoiceShortcutModifiers
        )
    }

    var voiceUIWindowOwnerNames: [String] {
        configuredStringArray(
            configPath: configPath,
            fileKey: "voiceUIWindowOwnerNames",
            envKey: "VOICE_UI_WINDOW_OWNER_NAMES",
            defaultValue: defaultVoiceUIWindowOwnerNames
        )
    }

    var triggerKey: String {
        configuredString(
            configPath: configPath,
            fileKey: "triggerKey",
            envKey: "TRIGGER_KEY",
            defaultValue: defaultTriggerKey
        )
    }

    var voiceVerifyTimeoutMs: UInt32 {
        configuredUInt32(
            configPath: configPath,
            fileKey: "voiceVerifyTimeoutMs",
            envKey: "VOICE_VERIFY_TIMEOUT_MS",
            defaultValue: defaultVoiceVerifyTimeoutMs,
            range: 0...5_000
        )
    }

    var voiceRetryGapMs: UInt32 {
        configuredUInt32(
            configPath: configPath,
            fileKey: "voiceRetryGapMs",
            envKey: "VOICE_RETRY_GAP_MS",
            defaultValue: defaultVoiceRetryGapMs,
            range: 0...2_000
        )
    }

    var voiceMaxRetries: UInt32 {
        configuredUInt32(
            configPath: configPath,
            fileKey: "voiceMaxRetries",
            envKey: "VOICE_MAX_RETRIES",
            defaultValue: defaultVoiceMaxRetries,
            range: 0...5
        )
    }

    var voiceReadinessSignal: String {
        configuredString(
            configPath: configPath,
            fileKey: "voiceReadinessSignal",
            envKey: "VOICE_READINESS_SIGNAL",
            defaultValue: defaultVoiceReadinessSignal
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
        let defaultVoiceSettleDelayMs: UInt32 = 300
        let defaultRestoreDelayMs: UInt32 = 2_000
        let defaultVoiceShortcutModifiers = ["cmd", "option"]
        let defaultOwnerNames = ["DoubaoIme", "Doubao", "豆包"]
        let defaultTriggerKey = "rightCommand"
        let defaultVoiceVerifyTimeoutMs: UInt32 = 1500
        let defaultVoiceRetryGapMs: UInt32 = 150
        let defaultVoiceMaxRetries: UInt32 = 1
        let defaultVoiceReadinessSignal = "microphone"

        ensureDefaultConfigFile(path: configPath, defaults: [
            "voiceSettleDelayMs": defaultVoiceSettleDelayMs,
            "restoreInputDelayMs": defaultRestoreDelayMs,
            "voiceShortcutModifiers": defaultVoiceShortcutModifiers,
            "voiceUIWindowOwnerNames": defaultOwnerNames,
            "triggerKey": defaultTriggerKey,
            "voiceVerifyTimeoutMs": defaultVoiceVerifyTimeoutMs,
            "voiceRetryGapMs": defaultVoiceRetryGapMs,
            "voiceMaxRetries": defaultVoiceMaxRetries,
            "voiceReadinessSignal": defaultVoiceReadinessSignal
        ])

        return AgentConfig(
            launchdLabel: env["AGENT_LAUNCHD_LABEL"] ?? "com.github.Coco422.doubao-voice-wetype-agent",
            restoreInputID: env["RESTORE_IME_ID"] ?? "com.tencent.inputmethod.wetype.pinyin",
            voiceInputID: voiceID,
            voiceInputAliases: aliases.union([voiceID]),
            configPath: configPath,
            logPath: env["DOUBAO_AGENT_LOG_PATH"] ?? "\(home)/Library/Logs/doubao-voice-wetype-agent.log",
            statusPath: env["DOUBAO_AGENT_STATUS_PATH"] ?? "\(appSupport)/status.json",
            defaultVoiceSettleDelayMs: defaultVoiceSettleDelayMs,
            defaultRestoreInputDelayMs: defaultRestoreDelayMs,
            defaultVoiceShortcutModifiers: defaultVoiceShortcutModifiers,
            defaultVoiceUIWindowOwnerNames: defaultOwnerNames,
            defaultTriggerKey: defaultTriggerKey,
            defaultVoiceVerifyTimeoutMs: defaultVoiceVerifyTimeoutMs,
            defaultVoiceRetryGapMs: defaultVoiceRetryGapMs,
            defaultVoiceMaxRetries: defaultVoiceMaxRetries,
            defaultVoiceReadinessSignal: defaultVoiceReadinessSignal
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
    let lastActivationResult: String
    let lastProbeWindow: String?
    let lastProbeWindowOwner: String?
    let lastProbeWindowName: String?
    let lastProbeWindowBounds: String?
}

func ensureDefaultConfigFile(path: String, defaults: [String: Any]) {
    let url = URL(fileURLWithPath: path)
    var payload = persistentConfig(path: path)
    let missingKeys = defaults.keys.filter { payload[$0] == nil }
    guard !FileManager.default.fileExists(atPath: path) || !missingKeys.isEmpty else { return }
    defaults.forEach { key, value in
        if payload[key] == nil { payload[key] = value }
    }

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

func configuredString(
    configPath: String,
    fileKey: String,
    envKey: String,
    defaultValue: String
) -> String {
    if let envValue = ProcessInfo.processInfo.environment[envKey] {
        let trimmed = envValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }

    if let value = persistentConfig(path: configPath)[fileKey] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }

    return defaultValue
}

func configuredStringArray(
    configPath: String,
    fileKey: String,
    envKey: String,
    defaultValue: [String]
) -> [String] {
    if let envValue = ProcessInfo.processInfo.environment[envKey] {
        return nonEmptyStrings(from: envValue).isEmpty ? defaultValue : nonEmptyStrings(from: envValue)
    }

    let value = persistentConfig(path: configPath)[fileKey]
    if let strings = value as? [String] {
        let cleaned = strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? defaultValue : cleaned
    }

    if let string = value as? String {
        let cleaned = nonEmptyStrings(from: string)
        return cleaned.isEmpty ? defaultValue : cleaned
    }

    return defaultValue
}

func nonEmptyStrings(from value: String) -> [String] {
    value.split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
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
    var passThroughPhysicalCombo = false
    var syntheticDownPosted = false
    var originalInputID: String?
    var wasAlreadyVoice = false
    var eventTapReady = false
    var accessibilityOK = false
    var inputMonitoringOK = false
    var currentInputID = "unknown"
    var lastEvent = "not triggered yet"
    var lastError: String?
    var tapRestartCount = 0
    var activationID = 0
    var lastActivationResult = "not attempted"
    var lastProbeWindow: String?
    var lastProbeWindowOwner: String?
    var lastProbeWindowName: String?
    var lastProbeWindowBounds: String?
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
            tapRestartCount: $0.tapRestartCount,
            lastActivationResult: $0.lastActivationResult,
            lastProbeWindow: $0.lastProbeWindow,
            lastProbeWindowOwner: $0.lastProbeWindowOwner,
            lastProbeWindowName: $0.lastProbeWindowName,
            lastProbeWindowBounds: $0.lastProbeWindowBounds
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

// A private-state event source so synthetic modifier presses carry their own
// modifier state instead of merging with whatever hardware keys are physically
// held. This lets the replayed shortcut register as a clean edge even while the
// user is holding the (decoupled) trigger key.
let syntheticEventSource = CGEventSource(stateID: .privateState)

func postModifier(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
    guard let event = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: keyCode, keyDown: down) else { return }
    event.flags = flags
    event.setIntegerValueField(.eventSourceUserData, value: marker)
    event.post(tap: .cghidEventTap)
}

struct ModifierKeySpec {
    let name: String
    let keyCode: CGKeyCode
    let flag: CGEventFlags
}

struct VoiceShortcutDefinition {
    let specs: [ModifierKeySpec]

    var flags: CGEventFlags {
        specs.reduce(CGEventFlags()) { partial, spec in
            partial.union(spec.flag)
        }
    }

    var description: String {
        specs.map(\.name).joined(separator: "+")
    }
}

final class VoiceShortcutCache {
    private let lock = NSLock()
    private var definition: VoiceShortcutDefinition

    init(definition: VoiceShortcutDefinition) {
        self.definition = definition
    }

    func read() -> VoiceShortcutDefinition {
        lock.lock()
        defer { lock.unlock() }
        return definition
    }

    func update(_ newDefinition: VoiceShortcutDefinition) {
        lock.lock()
        definition = newDefinition
        lock.unlock()
    }
}

let voiceShortcutCache = VoiceShortcutCache(definition: makeVoiceShortcutDefinition(from: config.voiceShortcutModifiers))

func cachedVoiceShortcutDefinition() -> VoiceShortcutDefinition {
    return voiceShortcutCache.read()
}

func refreshVoiceShortcutCache() {
    voiceShortcutCache.update(makeVoiceShortcutDefinition(from: config.voiceShortcutModifiers))
}

func makeVoiceShortcutDefinition(from modifiers: [String]) -> VoiceShortcutDefinition {
    let specs = modifiers.compactMap(modifierKeySpec)
    if specs.isEmpty {
        return VoiceShortcutDefinition(specs: ["cmd", "option"].compactMap(modifierKeySpec))
    }
    return VoiceShortcutDefinition(specs: specs)
}

func modifierKeySpec(_ raw: String) -> ModifierKeySpec? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "cmd", "command":
        return ModifierKeySpec(name: "cmd", keyCode: 55, flag: .maskCommand)
    case "option", "alt":
        return ModifierKeySpec(name: "option", keyCode: 58, flag: .maskAlternate)
    case "control", "ctrl":
        return ModifierKeySpec(name: "control", keyCode: 59, flag: .maskControl)
    case "shift":
        return ModifierKeySpec(name: "shift", keyCode: 56, flag: .maskShift)
    default:
        return nil
    }
}

// The physical trigger key the user holds. It is intentionally DECOUPLED from the
// replayed voice shortcut (voiceShortcutModifiers) so the synthetic shortcut is a
// clean edge. Detection is by key code, not flags, so e.g. left ⌘ shortcuts like
// ⌘C never look like a right-⌘ trigger.
struct TriggerKeySpec {
    let name: String
    let keyCode: CGKeyCode
    let flag: CGEventFlags
    let display: String
}

func triggerKeySpec(_ raw: String) -> TriggerKeySpec {
    let rightCommand = TriggerKeySpec(name: "rightCommand", keyCode: 54, flag: .maskCommand, display: "Right ⌘")
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "rightcommand", "right_command", "rcmd", "right-cmd":
        return rightCommand
    case "leftcommand", "left_command", "lcmd", "command", "cmd":
        return TriggerKeySpec(name: "leftCommand", keyCode: 55, flag: .maskCommand, display: "Left ⌘")
    case "rightoption", "right_option", "roption", "ralt":
        return TriggerKeySpec(name: "rightOption", keyCode: 61, flag: .maskAlternate, display: "Right ⌥")
    case "leftoption", "left_option", "option", "alt":
        return TriggerKeySpec(name: "leftOption", keyCode: 58, flag: .maskAlternate, display: "Left ⌥")
    case "rightcontrol", "right_control", "rctrl":
        return TriggerKeySpec(name: "rightControl", keyCode: 62, flag: .maskControl, display: "Right ⌃")
    case "leftcontrol", "left_control", "control", "ctrl":
        return TriggerKeySpec(name: "leftControl", keyCode: 59, flag: .maskControl, display: "Left ⌃")
    case "rightshift", "right_shift", "rshift":
        return TriggerKeySpec(name: "rightShift", keyCode: 60, flag: .maskShift, display: "Right ⇧")
    case "leftshift", "left_shift", "shift":
        return TriggerKeySpec(name: "leftShift", keyCode: 56, flag: .maskShift, display: "Left ⇧")
    case "fn", "function", "globe":
        return TriggerKeySpec(name: "fn", keyCode: 63, flag: .maskSecondaryFn, display: "fn")
    default:
        return rightCommand
    }
}

final class TriggerKeyCache {
    private let lock = NSLock()
    private var spec: TriggerKeySpec

    init(spec: TriggerKeySpec) {
        self.spec = spec
    }

    func read() -> TriggerKeySpec {
        lock.lock()
        defer { lock.unlock() }
        return spec
    }

    func update(_ newSpec: TriggerKeySpec) {
        lock.lock()
        spec = newSpec
        lock.unlock()
    }
}

let triggerKeyCache = TriggerKeyCache(spec: triggerKeySpec(config.triggerKey))

func cachedTriggerKeySpec() -> TriggerKeySpec {
    return triggerKeyCache.read()
}

func refreshTriggerKeyCache() {
    triggerKeyCache.update(triggerKeySpec(config.triggerKey))
}

func isTriggerKeycode(_ keycode: Int64) -> Bool {
    return Int64(cachedTriggerKeySpec().keyCode) == keycode
}

func triggerKeyDescription() -> String {
    return cachedTriggerKeySpec().display
}

func postVoiceShortcutDown() {
    var flags: CGEventFlags = []
    let definition = cachedVoiceShortcutDefinition()
    let specs = definition.specs
    for spec in specs {
        flags.insert(spec.flag)
        postModifier(spec.keyCode, down: true, flags: flags)
        usleep(25_000)
    }
    log("posted voice shortcut down modifiers=\(definition.description)")
}

func postVoiceShortcutUp() {
    let definition = cachedVoiceShortcutDefinition()
    let specs = definition.specs
    var flags = definition.flags
    for spec in specs.reversed() {
        flags.remove(spec.flag)
        postModifier(spec.keyCode, down: false, flags: flags)
        usleep(25_000)
    }
    log("posted voice shortcut up modifiers=\(definition.description)")
}

func voiceShortcutDescription() -> String {
    return cachedVoiceShortcutDefinition().description
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
        "restoreInputDelayMs": config.restoreInputDelayMs,
        "voiceShortcutModifiers": config.voiceShortcutModifiers,
        "voiceUIWindowOwnerNames": config.voiceUIWindowOwnerNames,
        "triggerKey": cachedTriggerKeySpec().name,
        "voiceVerifyTimeoutMs": config.voiceVerifyTimeoutMs,
        "voiceRetryGapMs": config.voiceRetryGapMs,
        "voiceMaxRetries": config.voiceMaxRetries,
        "voiceReadinessSignal": config.voiceReadinessSignal,
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
        "lastActivationResult": snapshot.lastActivationResult,
        "lastProbeWindow": snapshot.lastProbeWindow ?? NSNull(),
        "lastProbeWindowOwner": snapshot.lastProbeWindowOwner ?? NSNull(),
        "lastProbeWindowName": snapshot.lastProbeWindowName ?? NSNull(),
        "lastProbeWindowBounds": snapshot.lastProbeWindowBounds ?? NSNull(),
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
