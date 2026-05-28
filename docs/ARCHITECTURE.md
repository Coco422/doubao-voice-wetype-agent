# Architecture

This project has two executables:

- `doubao-voice-wetype-agent`, a menu bar app and event-tap state machine.
- `im-switch`, a small Text Input Source utility for listing, reading, and selecting macOS input sources.

## Components

```text
LaunchAgent
  -> doubao-voice-wetype-agent
      -> menu bar status
      -> Quartz event tap
      -> TIS input source switching
      -> synthetic modifier events
      -> optional Doubao window diagnostics
```

DMG distribution installs the app bundle to `~/Applications/Doubao Voice WeType Agent.app`.
The installer command and the app's first-launch self-install path both write the same LaunchAgent label and executable path, so future updates can replace the app in place.

## State Machine

```text
ready
 |
 | physical configured shortcut down
 v
check current input source
 |
 |-- already voice IME --> pass through original event
 |
switching
 |
 | worker uses captured source
 | select voice IME if needed
 | wait for current input source to match
 | wait trigger delay
 | post configured Doubao voice shortcut down
 v
holding

holding
 |
 | physical configured shortcut release
 v
post configured Doubao voice shortcut up
 |
 | wait restore delay
 | select restore IME
 v
ready
```

## Why Replay Events

Doubao voice input is triggered by a user-configured hold-style shortcut. If the user presses that shortcut while another IME is active, then Doubao may not observe the key-down transition after the app switches IMEs. The agent suppresses the original modifier transition, switches to Doubao, waits for a configurable trigger delay, then posts the configured Doubao voice shortcut down so Doubao can observe the hold from the start.

The release side posts the same configured shortcut up, waits before restoring the previous IME, then switches back. The main activation path does not probe UI windows or retry. Window probing remains as a diagnostics menu item only.

## Event Tap Hygiene

The event tap callback is kept short. It performs only the first input-source check needed to preserve the "already Doubao IME means pass through" rule. Slower operations such as selecting an IME, waiting for confirmation, sleeping for trigger/restore delays, and posting synthetic sequences run on a serial worker queue.

Synthetic events are marked with `eventSourceUserData`, and the event tap ignores events carrying that marker. Without this guard, the agent would observe and recursively process its own generated modifier events.

If macOS disables the event tap because of timeout or user input, the app marks itself unhealthy and tries to re-enable the tap.

## Configuration

IME and path configuration is read from environment variables, usually supplied by LaunchAgent:

| Variable | Default |
| --- | --- |
| `AGENT_LAUNCHD_LABEL` | `com.github.Coco422.doubao-voice-wetype-agent` |
| `RESTORE_IME_ID` | `com.tencent.inputmethod.wetype.pinyin` |
| `VOICE_IME_ID` | `com.bytedance.inputmethod.doubaoime.pinyin` |
| `VOICE_IME_ALIASES` | `com.bytedance.inputmethod.doubaoime` |
| `DOUBAO_AGENT_CONFIG_PATH` | `~/Library/Application Support/DoubaoVoiceWeTypeAgent/config.json` |
| `DOUBAO_AGENT_LOG_PATH` | `~/Library/Logs/doubao-voice-wetype-agent.log` |
| `DOUBAO_AGENT_STATUS_PATH` | `~/Library/Application Support/DoubaoVoiceWeTypeAgent/status.json` |

Timing configuration is persisted in `config.json`:

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

`voiceSettleDelayMs` is the delay after macOS confirms the voice IME is selected and before the configured Doubao voice shortcut is posted down. `voiceShortcutModifiers` is the modifier-only shortcut the agent listens for and replays; it must match the hold-to-talk shortcut configured inside Doubao. By default it is `cmd,option`; supported names are `cmd`, `option`, `control`, and `shift`. `restoreInputDelayMs` is the delay after the physical release before restoring WeType. The diagnostics menu item observes new visible windows and logs whether they match configured Doubao owner names; it does not participate in normal activation. Timing values can be overridden with `VOICE_SETTLE_DELAY_MS`, `RESTORE_INPUT_DELAY_MS`, `VOICE_SHORTCUT_MODIFIERS`, and `VOICE_UI_WINDOW_OWNER_NAMES`.

## Files

```text
Sources/DoubaoVoiceWeTypeAgent/Core.swift
Sources/DoubaoVoiceWeTypeAgent/App.swift
Sources/DoubaoVoiceWeTypeAgent/Events.swift
Sources/DoubaoVoiceWeTypeAgent/Installer.swift
Sources/DoubaoVoiceWeTypeAgent/VoiceUIProbe.swift
Sources/DoubaoVoiceWeTypeAgent/main.swift
Sources/DoubaoVoiceWeTypeAgent/Resources/AppIcon.icns
Sources/IMSwitch/main.swift
launchd/com.github.Coco422.doubao-voice-wetype-agent.plist.template
scripts/install.sh
scripts/install_or_update_app.sh
scripts/package_dmg.sh
scripts/uninstall.sh
```
