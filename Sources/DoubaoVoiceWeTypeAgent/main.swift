import AppKit

let app = NSApplication.shared
let delegate = AgentApp()
app.delegate = delegate
withExtendedLifetime(delegate) {
    app.run()
}
