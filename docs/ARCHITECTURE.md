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
```

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
 |-- not voice IME
        |
        v
    switching
        |
        | select voice IME
        | wait for current input source to match
        | settle briefly
        | post synthetic Cmd+Option down
        v
    holding
        |
        | physical Cmd+Option release
        v
    switching
        |
        | post synthetic Cmd+Option up if down was posted
        | select restore IME
        v
    ready
```

## Why Replay Events

Doubao voice input is triggered by a hold-style shortcut. If the user presses `Command + Option` before Doubao is active, Doubao may not observe the key-down transition. The agent suppresses the original modifier transition, switches IME, waits for confirmation, then posts a synthetic key-down event that Doubao can observe from the start.

The release side is symmetrical. The agent posts a synthetic key-up only if it previously posted the synthetic key-down. This avoids confusing the voice IME if the user releases before the switch completes.

## Event Tap Hygiene

The event tap callback is kept short. Slow operations such as selecting an IME, waiting for confirmation, sleeping for settle delays, and posting synthetic sequences run on a serial worker queue.

Synthetic events are marked with `eventSourceUserData`, and the event tap ignores events carrying that marker. Without this guard, the agent would observe and recursively process its own generated modifier events.

If macOS disables the event tap because of timeout or user input, the app marks itself unhealthy and tries to re-enable the tap.

## Configuration

Configuration is read from environment variables, usually supplied by LaunchAgent:

| Variable | Default |
| --- | --- |
| `RESTORE_IME_ID` | `com.tencent.inputmethod.wetype.pinyin` |
| `VOICE_IME_ID` | `com.bytedance.inputmethod.doubaoime.pinyin` |
| `VOICE_IME_ALIASES` | `com.bytedance.inputmethod.doubaoime` |
| `DOUBAO_AGENT_LOG_PATH` | `~/Library/Logs/doubao-voice-wetype-agent.log` |
| `DOUBAO_AGENT_STATUS_PATH` | `~/Library/Application Support/DoubaoVoiceWeTypeAgent/status.json` |

## Files

```text
Sources/DoubaoVoiceWeTypeAgent/Core.swift
Sources/DoubaoVoiceWeTypeAgent/App.swift
Sources/DoubaoVoiceWeTypeAgent/Events.swift
Sources/DoubaoVoiceWeTypeAgent/main.swift
Sources/IMSwitch/main.swift
launchd/com.github.Coco422.doubao-voice-wetype-agent.plist.template
scripts/install.sh
scripts/uninstall.sh
```
