# Troubleshooting

## `豆 !` stays in the menu bar

Read the status file:

```bash
cat "$HOME/Library/Application Support/DoubaoVoiceWeTypeAgent/status.json"
```

Common causes:

- `accessibilityOK` is `false`, grant Accessibility permission.
- `inputMonitoringOK` is `false`, grant Input Monitoring permission.
- `eventTapReady` is `false`, retry from the menu or restart the LaunchAgent.

## Permissions look granted but the app still cannot listen

macOS sometimes treats a rebuilt binary as a new app even when the path is the same.

Try:

1. Remove the binary from Accessibility and Input Monitoring.
2. Re-add the executable for your install path:
   - Source install: `~/.local/bin/doubao-voice-wetype-agent`
   - DMG install: `~/Applications/Doubao Voice WeType Agent.app/Contents/MacOS/doubao-voice-wetype-agent`
3. Restart the agent:

```bash
launchctl kickstart -k gui/$(id -u)/com.github.Coco422.doubao-voice-wetype-agent
```

## Voice input does not start, but the IME switches

This is usually timing-related or shortcut-mapping-related. The agent waits for the selected input source, adds a small trigger delay, then posts the configured Doubao voice shortcut down. It keeps that synthetic shortcut held until the physical shortcut is released, then posts the same shortcut up and waits before restoring WeType.

Open the menu bar item and check `Voice timing`. You can edit the persistent config:

```bash
open "$HOME/Library/Application Support/DoubaoVoiceWeTypeAgent/config.json"
```

The default timing config is:

```json
{
  "restoreInputDelayMs": 2000,
  "voiceSettleDelayMs": 300,
  "voiceShortcutModifiers": [
    "cmd",
    "option"
  ],
  "voiceUIWindowOwnerNames": [
    "DoubaoIme",
    "Doubao",
    "豆包"
  ]
}
```

Make sure `voiceShortcutModifiers` matches the voice shortcut configured inside Doubao. The agent uses it both for the physical shortcut it listens for and the synthetic shortcut it replays. The default is `cmd,option`, and supported modifier names are `cmd`, `option`, `control`, and `shift`. If Doubao switches in but voice input does not start, try increasing `voiceSettleDelayMs`, for example `500` or `700`. If restore happens too soon after release, increase `restoreInputDelayMs`.

Check the log:

```bash
tail -100 "$HOME/Library/Logs/doubao-voice-wetype-agent.log"
```

Look for:

```text
physical voice shortcut down
voice shortcut down posted
physical voice shortcut released
voice shortcut up posted
restored input
```

`Run voice probe diagnostics` is still available from the menu, but it is diagnostic only. The main activation path no longer depends on window detection.

## The current input source ID is unknown

Use:

```bash
swift run im-switch --list
swift run im-switch --current
```

Then update `RESTORE_IME_ID`, `VOICE_IME_ID`, or `VOICE_IME_ALIASES` in the LaunchAgent plist.

## LaunchAgent is not running

```bash
launchctl print gui/$(id -u)/com.github.Coco422.doubao-voice-wetype-agent
```

If it is missing, reinstall:

```bash
./scripts/install.sh
```

If you installed from the DMG, open the DMG and double-click `1 Double-click to Install or Update.command`.
The app should be installed at:

```text
~/Applications/Doubao Voice WeType Agent.app
```

If you double-click the app directly, it should copy itself there and register the LaunchAgent automatically.

## Quit immediately starts again

`Restart agent` exits the process and lets launchd start it again. Use `Quit agent` from the menu to unload the LaunchAgent and stop the process.

If you need to stop it from Terminal:

```bash
launchctl bootout gui/$(id -u)/com.github.Coco422.doubao-voice-wetype-agent
```

## DMG install path is confusing

The recommended DMG entry point is:

```text
1 Double-click to Install or Update.command
```

It installs the app to `~/Applications/Doubao Voice WeType Agent.app` and registers the LaunchAgent. Directly double-clicking the app is also supported; the app self-installs to the same location and exits the temporary launch.
