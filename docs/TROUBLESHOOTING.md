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
2. Re-add `~/.local/bin/doubao-voice-wetype-agent`.
3. Restart the agent:

```bash
launchctl kickstart -k gui/$(id -u)/com.github.Coco422.doubao-voice-wetype-agent
```

## Voice input does not start, but the IME switches

This is usually timing-related. The IME may report as selected before its shortcut monitor is ready. The current implementation waits for the selected input source and then adds a settle delay before posting synthetic `Command + Option` down.

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

If `posted cmd+option down` appears but the voice UI does not start, the IME did not react to the synthetic hold. You can experiment with a longer settle delay in `Events.swift`.

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
