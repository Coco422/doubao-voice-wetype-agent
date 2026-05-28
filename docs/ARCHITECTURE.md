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
      -> Doubao voice UI window probing
```

DMG distribution installs the app bundle to `~/Applications/Doubao Voice WeType Agent.app`.
The installer command and the app's first-launch self-install path both write the same LaunchAgent label and executable path, so future updates can replace the app in place.

## State Machine

```text
ready
 |
 | physical Cmd+Option down
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
 | settle briefly
 | snapshot Doubao-related visible windows
 |
 v
activation loop
 |
 | post synthetic Cmd+Option down
 | probe for a new bottom Doubao voice UI panel
 |-- detected --> holding
 |-- not detected --> keep synthetic hold down and refresh down while physical keys remain held
 |
 | bounded attempts exhausted
 v
restore input and mark activation failure
 |
 v
ready

holding
 |
 | physical Cmd+Option release
 v
post synthetic Cmd+Option up
 |
 | select restore IME
 v
ready
```

## Why Replay Events

Doubao voice input is triggered by a hold-style shortcut. If the user presses `Command + Option` before Doubao is active, Doubao may not observe the key-down transition. The agent suppresses the original modifier transition, switches IME, waits for confirmation, then posts synthetic hold attempts that Doubao can observe from the start.

After each synthetic key-down, the agent checks whether Doubao exposes a new visible voice UI panel. The probe intentionally ignores generic Doubao windows and only accepts a small panel near the bottom of a display, matching the voice input UI that appears above the input bar. If not detected, it keeps the synthetic hold down and refreshes the down attempt while the physical keys remain held. After detection, it stops retrying and waits for the physical release. The release side posts synthetic key-up only if a synthetic down is still active, so the simulated hold follows the user's real hold instead of bouncing between attempts.

## Event Tap Hygiene

The event tap callback is kept short. It performs only the first input-source check needed to preserve the "already Doubao IME means pass through" rule. Slower operations such as selecting an IME, waiting for confirmation, sleeping for settle delays, probing windows, and posting synthetic sequences run on a serial worker queue.

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

`voiceSettleDelayMs` is the wait after macOS confirms the voice IME is selected and before the first synthetic `Command + Option` down is posted. The activation loop then probes for new visible windows owned by the configured Doubao owner names and only accepts the small bottom voice panel as success. `voiceActivationMaxAttempts=0` means the loop has no attempt cap and stops on physical release; a positive value bounds attempts and restores WeType after failure. The diagnostics menu item observes all new visible windows for a short window and logs whether each one matches those names and the bottom-panel heuristic, which helps discover owner names without Screen Recording permission. Timing values can be overridden with `VOICE_SETTLE_DELAY_MS`, `VOICE_ACTIVATION_MAX_ATTEMPTS`, `VOICE_ACTIVATION_PROBE_TIMEOUT_MS`, `VOICE_ACTIVATION_RETRY_GAP_MS`, and `VOICE_UI_WINDOW_OWNER_NAMES`.

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
