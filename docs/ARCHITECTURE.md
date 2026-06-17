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
 | trigger key down (by key code, default Right ⌘)
 v
capture current input source (remember it for restore)
 |
switching
 |
 | worker: select voice IME if not already active
 | wait for current input source to match
 | wait settle delay
 v
activation loop
 |
 | post Doubao voice shortcut down (private event source)
 | verify readiness: microphone running, or new Doubao-owned window
 |-- detected --------------------------------> holding
 |-- not detected, retries left: post up, gap, post down again
 |-- not detected, no retries: hold anyway (best effort) --> holding
 v
holding
 |
 | trigger key release
 v
post Doubao voice shortcut up
 |
 | wait restore delay
 | select the input source we started from
 |   (skip if the user was already on Doubao)
 v
ready
```


## Why Decouple And Verify

Doubao voice input is a hold-to-talk shortcut that only works while Doubao is the active IME. A naive "switch then press the shortcut" is unreliable for two reasons:

1. **Readiness race.** After macOS reports the IME switch, Doubao's own voice hotkey listener (in the Doubao IME process) is not necessarily live yet, so a shortcut posted on a fixed delay can be dropped.
2. **Modifier collision.** If the key the user holds is the same as the shortcut being replayed, the synthetic key-down is not a fresh edge — the modifier flag is already set by the physically-held key — so Doubao may never see a new press.

The agent addresses both. The **trigger key is decoupled** from the replayed shortcut and detected by key code, so the replayed `Command+Option` is a clean edge and ordinary `⌘`-shortcuts are never mistaken for the trigger. Synthetic events come from a private `CGEventSource` so their modifier state does not merge with held hardware keys. Instead of a fixed delay, activation runs a **closed loop**: post the shortcut down, confirm voice actually started via a screen-independent readiness signal (microphone running, or a new Doubao-owned window), and if it did not start, do one clean re-trigger (release then press). The geometry-based window heuristic is kept for diagnostics only; it is not used to gate activation because window position/size is not reliable across displays and scaling.

The release side posts the same shortcut up, waits, then restores the input source the user started from (skipped if they were already on Doubao).


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
| `TRIGGER_KEY` | `rightCommand` |
| `DOUBAO_AGENT_CONFIG_PATH` | `~/Library/Application Support/DoubaoVoiceWeTypeAgent/config.json` |
| `DOUBAO_AGENT_LOG_PATH` | `~/Library/Logs/doubao-voice-wetype-agent.log` |
| `DOUBAO_AGENT_STATUS_PATH` | `~/Library/Application Support/DoubaoVoiceWeTypeAgent/status.json` |

Timing and behavior are persisted in `config.json`:

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

`triggerKey` is the key the user holds, detected by key code (whitelist: `rightCommand`, `leftCommand`, `rightOption`, `leftOption`, `rightControl`, `leftControl`, `rightShift`, `leftShift`, `fn`); it is decoupled from `voiceShortcutModifiers`, the shortcut replayed to Doubao (`cmd`/`option`/`control`/`shift`). `voiceSettleDelayMs` is the wait after the IME switch confirms and before the first shortcut down. `voiceReadinessSignal` selects how activation confirms voice started: `microphone` (default; default-input device running — screen-independent, no permission prompt; auto-falls back to `window` if the mic was already running), `window` (a new Doubao-owned window, ignoring geometry), or `none`. `voiceVerifyTimeoutMs` bounds the wait for that signal; on miss the loop does up to `voiceMaxRetries` clean re-triggers separated by `voiceRetryGapMs`. `restoreInputDelayMs` is the delay after release before restoring the original input source. The geometry-based window probe is diagnostics-only. Overrides: `TRIGGER_KEY`, `VOICE_READINESS_SIGNAL`, `VOICE_VERIFY_TIMEOUT_MS`, `VOICE_RETRY_GAP_MS`, `VOICE_MAX_RETRIES`, `VOICE_SETTLE_DELAY_MS`, `RESTORE_INPUT_DELAY_MS`, `VOICE_SHORTCUT_MODIFIERS`, `VOICE_UI_WINDOW_OWNER_NAMES`.

## Files

```text
Sources/DoubaoVoiceWeTypeAgent/Core.swift
Sources/DoubaoVoiceWeTypeAgent/App.swift
Sources/DoubaoVoiceWeTypeAgent/Events.swift
Sources/DoubaoVoiceWeTypeAgent/Installer.swift
Sources/DoubaoVoiceWeTypeAgent/VoiceUIProbe.swift
Sources/DoubaoVoiceWeTypeAgent/MicMonitor.swift
Sources/DoubaoVoiceWeTypeAgent/main.swift
Sources/DoubaoVoiceWeTypeAgent/Resources/AppIcon.icns
Sources/IMSwitch/main.swift
launchd/com.github.Coco422.doubao-voice-wetype-agent.plist.template
scripts/install.sh
scripts/install_or_update_app.sh
scripts/package_dmg.sh
scripts/uninstall.sh
```
