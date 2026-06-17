# Doubao Voice WeType Agent

A tiny macOS menu bar agent for this workflow:

- Keep WeType as the everyday input method.
- Hold a dedicated trigger key, default **Right Command**, to temporarily switch to Doubao IME.
- Replay Doubao's own voice shortcut (default `Command + Option`) so its hold-to-talk voice input starts, and confirm it actually started before settling.
- Release the trigger key to end voice input and switch back to the input method you were using.
- If Doubao IME is already active, skip the switch but still replay the voice shortcut, and stay on Doubao afterward.

The trigger key you hold is intentionally **decoupled** from the shortcut replayed to Doubao. That is the key to reliability: because your fingers are not already holding `Command + Option`, the replayed shortcut registers as a clean, fresh key edge instead of colliding with keys you are physically holding.

It is not an IME plugin and does not modify Doubao or WeType. It is a small Swift app that combines the macOS Text Input Source API with a Quartz event tap.

## Why This Exists

Doubao voice input is a hold-to-talk shortcut that only works while Doubao is the active IME. Two things make a naive "switch then press" unreliable:

1. After macOS reports the switch, Doubao's voice hotkey listener is not necessarily live yet, so a shortcut posted on a fixed delay can be missed.
2. If the key you hold is the same as the shortcut being replayed, the synthetic press is not a fresh edge (the modifier is already physically down), so Doubao may not see a new press.

This agent handles both:

```text
trigger key down (default Right ⌘)
  -> suppress the trigger key (decoupled from the voice shortcut)
  -> switch to Doubao IME (skip if already active)
  -> wait until macOS confirms the switch
  -> post the Doubao voice shortcut down (default ⌘⌥, from a private event source)
  -> verify voice actually started (microphone in use, or a new Doubao window)
  -> if not started in time: release and re-press once (a clean re-trigger), bounded
  -> wait for trigger key release
  -> post the Doubao voice shortcut up
  -> wait, then restore the input method you started from
```


## Menu Bar Status

The app has no Dock icon. It lives in the macOS menu bar:

- `豆 OK`, permissions and event tap are ready.
- `豆 !`, permissions or event tap need attention.
- `豆 REC`, the agent is managing the hold.
- `豆 ...`, starting or switching.

The menu shows current permissions, current input method, event tap state, voice activation status, restart count, and the latest event. It can also open the relevant macOS privacy settings.

Use `Restart agent` to let launchd restart the agent. Use `Quit agent` to unload the LaunchAgent and stop the menu bar process.
Use `Run voice probe diagnostics` to observe visible window changes for 3 seconds without sending any shortcut. The log marks whether each new window matches the configured Doubao owner names.
Use `Run activation calibration` to measure, on this machine, how long the IME switch takes to confirm and how long after the replayed shortcut the microphone actually starts, and whether releasing stops the mic (hold-to-talk) or not (toggle). It briefly starts and stops Doubao voice; results go to the log and help you tune `voiceVerifyTimeoutMs`.

## Requirements

- macOS 13 or newer
- Swift toolchain, Xcode Command Line Tools are enough
- Doubao IME installed
- WeType installed, or another restore IME configured through `RESTORE_IME_ID`

Default input source IDs:

```text
Doubao: com.bytedance.inputmethod.doubaoime.pinyin
WeType: com.tencent.inputmethod.wetype.pinyin
```

Use the bundled `im-switch` helper to inspect available IDs:

```bash
swift run im-switch --list
swift run im-switch --current
```

## Install

### From Source

```bash
git clone https://github.com/Coco422/doubao-voice-wetype-agent.git
cd doubao-voice-wetype-agent
./scripts/install.sh
```

The installer builds release binaries, installs them to:

```text
~/.local/bin/doubao-voice-wetype-agent
~/.local/bin/im-switch
```

and installs a LaunchAgent:

```text
~/Library/LaunchAgents/com.github.Coco422.doubao-voice-wetype-agent.plist
```

### From DMG

Build a local DMG:

```bash
./scripts/package_dmg.sh
```

This creates:

```text
dist/Doubao Voice WeType Agent.app
dist/DoubaoVoiceWeTypeAgent-<version>.dmg
```

Open the DMG and double-click:

```text
1 Double-click to Install or Update.command
```

It installs or updates the app at:

```text
~/Applications/Doubao Voice WeType Agent.app
```

and points the LaunchAgent at the app executable.

If you double-click `Doubao Voice WeType Agent.app` directly, it will install itself to `~/Applications`, register the LaunchAgent, then run from the installed location.

## Permissions

Grant both permissions to:

```text
~/.local/bin/doubao-voice-wetype-agent
```

If you installed from the DMG, grant permissions to:

```text
~/Applications/Doubao Voice WeType Agent.app/Contents/MacOS/doubao-voice-wetype-agent
```

Required:

- System Settings -> Privacy & Security -> Accessibility
- System Settings -> Privacy & Security -> Input Monitoring

After granting permissions, either use the menu bar item to retry or run:

```bash
launchctl kickstart -k gui/$(id -u)/com.github.Coco422.doubao-voice-wetype-agent
```

The first launch may show `豆 !` in the menu bar. That is expected until both permissions are granted. After granting permissions, choose `Retry permissions/tap`; it should change to `豆 OK`.

## Updates And Permission Stability

macOS privacy permissions are tied to the app's identity. To reduce re-authorization:

- Keep the installed app path stable.
- Keep the LaunchAgent label stable.
- Sign every release with the same Developer ID identity when distributing builds.
- Update in place with `1 Double-click to Install or Update.command` instead of changing install locations.

Unsigned or ad-hoc signed builds may still require re-authorization after the binary changes, because macOS can treat the new build as a different executable. For local testing this is normal; for smooth updates, build the DMG with a stable signing identity:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package_dmg.sh
```

## Configure Another IME Pair

The LaunchAgent template uses environment variables:

```text
RESTORE_IME_ID=com.tencent.inputmethod.wetype.pinyin
VOICE_IME_ID=com.bytedance.inputmethod.doubaoime.pinyin
VOICE_IME_ALIASES=com.bytedance.inputmethod.doubaoime
TRIGGER_KEY=rightCommand
```

Edit the installed plist or template if you want to use a different restore IME or voice IME.

## Trigger Key And Voice Shortcut

These are two separate things and should stay separate:

- `triggerKey` — the single key you physically hold. Default `rightCommand`. Supported: `rightCommand`, `leftCommand`, `rightOption`, `leftOption`, `rightControl`, `leftControl`, `rightShift`, `leftShift`, `fn`. It is detected by key code, so e.g. holding right ⌘ never collides with ordinary ⌘C/⌘V.
- `voiceShortcutModifiers` — the hold-to-talk shortcut configured **inside Doubao**, which the agent replays. Default `cmd,option`. Supported names: `cmd`, `option`, `control`, `shift`.

Keep them disjoint for best reliability. `fn` is the cleanest trigger because it shares no modifier flag with `cmd`/`option`; `rightCommand` is the default for ergonomics. If you change Doubao's voice shortcut, set `voiceShortcutModifiers` to match it.

## Tune Voice Startup Timing

The agent keeps a persistent config file at:

```text
~/Library/Application Support/DoubaoVoiceWeTypeAgent/config.json
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

- `voiceSettleDelayMs` — wait after macOS confirms the Doubao switch and before the first synthetic shortcut down.
- `voiceReadinessSignal` — how the agent confirms voice actually started: `microphone` (default; the default input device starts running — screen-independent, no extra permission), `window` (a new Doubao-owned window appears, ignoring its size/position), or `none` (post and assume). With `microphone`, if the mic is already in use at trigger time (e.g. a call) the agent automatically falls back to the window signal.
- `voiceVerifyTimeoutMs` — how long to wait for the readiness signal before re-triggering. Use `Run activation calibration` to find a good value for your machine.
- `voiceMaxRetries` — extra clean re-triggers (release then press) if voice did not start; `0` disables re-triggering.
- `voiceRetryGapMs` — pause between a re-trigger's release and the next press.
- `restoreInputDelayMs` — delay after you release the trigger key before switching back.

`Run voice probe diagnostics` and the geometry-based window heuristic are troubleshooting-only; the activation path uses the microphone/owner-window signals above, which do not depend on screen resolution, scaling, the Dock, or which display is active.

You can also override these from the LaunchAgent with:

```text
VOICE_SETTLE_DELAY_MS=300
RESTORE_INPUT_DELAY_MS=2000
VOICE_SHORTCUT_MODIFIERS=cmd,option
VOICE_UI_WINDOW_OWNER_NAMES=DoubaoIme,Doubao,豆包
TRIGGER_KEY=rightCommand
VOICE_READINESS_SIGNAL=microphone
VOICE_VERIFY_TIMEOUT_MS=700
VOICE_RETRY_GAP_MS=90
VOICE_MAX_RETRIES=1
```

## Diagnostics

Status JSON:

```bash
cat "$HOME/Library/Application Support/DoubaoVoiceWeTypeAgent/status.json"
```

Log:

```bash
tail -100 "$HOME/Library/Logs/doubao-voice-wetype-agent.log"
```

LaunchAgent:

```bash
launchctl print gui/$(id -u)/com.github.Coco422.doubao-voice-wetype-agent
```

## Uninstall

```bash
./scripts/uninstall.sh
```

The uninstall script unloads and removes the LaunchAgent. It intentionally leaves installed binaries in `~/.local/bin` so macOS privacy permissions are not churned unless you delete them yourself.

If you installed from the DMG, remove the installed app only when you really want to reset that install path:

```bash
rm -rf "$HOME/Applications/Doubao Voice WeType Agent.app"
```

Keeping the app in place is better for update stability.

## Caveats

- Rebuilding or replacing the binary can make macOS ask for permissions again.
- Third-party IMEs may report as selected before their own shortcut monitors are ready. The agent confirms voice actually started (microphone/owner window) and re-triggers once if needed, but exact timing is still system-dependent; tune `voiceVerifyTimeoutMs` with `Run activation calibration`.
- The trigger key is detected by key code on `flagsChanged`, so it must be a modifier-type key (`triggerKey` whitelist). It is decoupled from `voiceShortcutModifiers`, the shortcut replayed to Doubao.
- The microphone readiness signal reads device state only; it does not request the Microphone permission. If you are already recording when you trigger, the agent falls back to the window signal.
