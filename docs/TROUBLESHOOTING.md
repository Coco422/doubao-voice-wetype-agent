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

The agent switches to Doubao, posts the configured Doubao voice shortcut down (from a private event source), then verifies voice actually started before settling. If it cannot confirm, it does one clean re-trigger (release then press). Check the menu's trigger/verify line, and edit the persistent config:

```bash
open "$HOME/Library/Application Support/DoubaoVoiceWeTypeAgent/config.json"
```

Defaults:

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
  ],
  "triggerKey": "rightCommand",
  "voiceReadinessSignal": "microphone",
  "voiceVerifyTimeoutMs": 700,
  "voiceRetryGapMs": 90,
  "voiceMaxRetries": 1
}
```

Steps:

1. Run `Run activation calibration` from the menu. It logs the IME switch time, the microphone start latency after the shortcut, and whether release stops the mic (hold-to-talk) or not (toggle). Set `voiceVerifyTimeoutMs` to at least the measured mic latency plus headroom.
2. Make sure `voiceShortcutModifiers` matches the voice shortcut configured **inside Doubao** (`cmd,option` by default; names: `cmd`, `option`, `control`, `shift`).
3. Make sure `triggerKey` is the key you actually hold (default `rightCommand`). It must be a modifier-type key from the whitelist. Keep it disjoint from `voiceShortcutModifiers`; `fn` is the cleanest if `rightCommand` misbehaves.
4. If voice still misses, raise `voiceMaxRetries` to `2`, or try `voiceReadinessSignal: "window"` if microphone detection is unreliable on your setup.
5. If restore happens too soon after release, raise `restoreInputDelayMs`.

Check the log:

```bash
tail -100 "$HOME/Library/Logs/doubao-voice-wetype-agent.log"
```

Look for:

```text
trigger down (Right ⌘)
voice shortcut down posted attempt=1
voice started: mic detected on attempt 1
trigger released (Right ⌘)
voice shortcut up posted
restored input to <your IME>
```

If you see `verify failed after N attempt(s)`, voice was posted but never confirmed — increase `voiceVerifyTimeoutMs` (per calibration) or switch the readiness signal. `Run voice probe diagnostics` and the geometry heuristic are diagnostics-only; activation does not depend on window position.

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
