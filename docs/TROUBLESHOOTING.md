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

This is usually timing-related. The IME may report as selected before its shortcut monitor is ready. The agent waits for the selected input source, adds a small settle delay, posts synthetic `Command + Option` down, and then checks whether Doubao's small bottom voice UI panel appears. If no voice UI appears, it keeps synthetic `Command + Option` held and refreshes down attempts while the physical shortcut is still held. Once that bottom voice panel appears, retrying stops.

Open the menu bar item and check `Voice settle delay`. You can edit the persistent config:

```bash
open "$HOME/Library/Application Support/DoubaoVoiceWeTypeAgent/config.json"
```

The default timing config is:

```json
{
  "voiceActivationMaxAttempts": 0,
  "voiceActivationProbeTimeoutMs": 280,
  "voiceActivationRetryGapMs": 90,
  "voiceSettleDelayMs": 200,
  "voiceUIWindowOwnerNames": [
    "DoubaoIme",
    "Doubao",
    "豆包"
  ]
}
```

If Doubao switches in but voice input does not appear, first check whether the log says `voice UI detected`. If it never detects a window, run `Run voice probe diagnostics` from the menu while manually opening Doubao voice input, then add the observed owner name to `voiceUIWindowOwnerNames`. Diagnostics logs each new visible window with `matchConfiguredOwner=true/false`, `likelyVoicePanel=true/false`, owner, name, and bounds so an unknown Doubao process can still be discovered.

`voiceActivationMaxAttempts=0` means retry until you release the physical shortcut. Use a positive value only if you want bounded failure behavior.

Check the log:

```bash
tail -100 "$HOME/Library/Logs/doubao-voice-wetype-agent.log"
```

Look for:

```text
physical cmd+option down
activation 1 attempt 1 start
voice UI detected
physical cmd+option released
posted cmd+option up
restored input
```

If repeated attempts log `no voice UI detected`, the IME did not react to the synthetic hold or the probe is not matching the right window owner. Tune `voiceUIWindowOwnerNames` before increasing settle delay.

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
