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

This is usually timing-related. The IME may report as selected before its shortcut monitor is ready. The current implementation waits for the selected input source and then adds a settle delay before posting synthetic `Command + Option` down.

Open the menu bar item and check `Voice settle delay`. You can edit the persistent config:

```bash
open "$HOME/Library/Application Support/DoubaoVoiceWeTypeAgent/config.json"
```

Increase `voiceSettleDelayMs` if Doubao switches in but voice input does not appear:

```json
{
  "voiceSettleDelayMs": 700
}
```

The value is milliseconds, clamped to `0...5000`, and applies on the next shortcut attempt.

Check the log:

```bash
tail -100 "$HOME/Library/Logs/doubao-voice-wetype-agent.log"
```

Look for:

```text
physical cmd+option down
posted cmd+option down
physical cmd+option released
posted cmd+option up
restored input
```

If `posted cmd+option down` appears but the voice UI does not start, the IME did not react to the synthetic hold. Try a longer `voiceSettleDelayMs`.

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
