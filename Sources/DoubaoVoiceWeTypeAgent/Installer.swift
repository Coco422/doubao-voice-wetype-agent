import AppKit
import Darwin
import Foundation

enum InstallCoordinator {
    static let appName = "Doubao Voice WeType Agent.app"

    static var installedAppURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .appendingPathComponent(appName)
    }

    static var installedExecutableURL: URL {
        installedAppURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("doubao-voice-wetype-agent")
    }

    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(config.launchdLabel).plist")
    }

    static func prepareInstalledLaunchIfNeeded() -> Bool {
        guard let currentAppURL = currentAppBundleURL() else { return false }

        let currentPath = normalizedPath(currentAppURL)
        let installedPath = normalizedPath(installedAppURL)
        let launchdManaged = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == config.launchdLabel

        if currentPath != installedPath {
            showInstallNotice()
            do {
                try installApp(from: currentAppURL)
                try installLaunchAgent()
                restartLaunchAgent()
                openAccessibilitySettings()
            } catch {
                showInstallError(error)
                log("self install failed: \(error)")
            }
            NSApp.terminate(nil)
            return true
        }

        if !launchdManaged {
            do {
                try installLaunchAgent()
                restartLaunchAgent()
            } catch {
                showInstallError(error)
                log("launch agent refresh failed: \(error)")
            }
            NSApp.terminate(nil)
            return true
        }

        return false
    }

    private static func currentAppBundleURL() -> URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func installApp(from sourceURL: URL) throws {
        try FileManager.default.createDirectory(
            at: installedAppURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(config.launchdLabel)"])
        try runProcess("/usr/bin/ditto", [sourceURL.path, installedAppURL.path])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: installedExecutableURL.path
        )
    }

    private static func installLaunchAgent() throws {
        try FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plist = launchAgentPlist(programPath: installedExecutableURL.path)
        try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
    }

    private static func restartLaunchAgent() {
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(config.launchdLabel)"])
        _ = runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
        _ = runLaunchctl(["kickstart", "-k", "gui/\(getuid())/\(config.launchdLabel)"])
    }

    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        (try? runProcess("/bin/launchctl", arguments)) ?? -1
    }

    @discardableResult
    private static func runProcess(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func launchAgentPlist(programPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(xmlEscape(config.launchdLabel))</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(xmlEscape(programPath))</string>
          </array>
          <key>EnvironmentVariables</key>
          <dict>
            <key>AGENT_LAUNCHD_LABEL</key>
            <string>\(xmlEscape(config.launchdLabel))</string>
            <key>RESTORE_IME_ID</key>
            <string>\(xmlEscape(config.restoreInputID))</string>
            <key>VOICE_IME_ID</key>
            <string>\(xmlEscape(config.voiceInputID))</string>
            <key>VOICE_IME_ALIASES</key>
            <string>\(xmlEscape(config.voiceInputAliases.sorted().joined(separator: ",")))</string>
          </dict>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>LimitLoadToSessionType</key>
          <string>Aqua</string>
          <key>StandardOutPath</key>
          <string>\(xmlEscape(NSHomeDirectory()))/Library/Logs/doubao-voice-wetype-agent.stdout.log</string>
          <key>StandardErrorPath</key>
          <string>\(xmlEscape(NSHomeDirectory()))/Library/Logs/doubao-voice-wetype-agent.stderr.log</string>
          <key>WorkingDirectory</key>
          <string>\(xmlEscape(NSHomeDirectory()))</string>
        </dict>
        </plist>
        """
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func showInstallNotice() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Install Doubao Voice WeType Agent"
        alert.informativeText = """
        The app will be copied to:
        \(installedAppURL.path)

        After installation, grant Accessibility and Input Monitoring permissions to the installed app executable.
        """
        alert.addButton(withTitle: "Install")
        alert.runModal()
    }

    private static func showInstallError(_ error: Error) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.messageText = "Install failed"
        alert.runModal()
    }

    private static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
