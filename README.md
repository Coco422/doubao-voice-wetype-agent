# Doubao Voice WeType Agent

A tiny macOS menu bar agent for this workflow:

- Keep WeType as the everyday input method.
- Hold `Command + Option` to temporarily switch to Doubao IME.
- Replay a clean `Command + Option` hold so Doubao's voice input starts.
- Release `Command + Option` to end voice input and switch back to WeType.

It is not an IME plugin and does not modify Doubao or WeType. It is a small Swift app that combines the macOS Text Input Source API with a Quartz event tap.

## Why This Exists

Doubao voice input is a hold-to-talk shortcut. If you press `Command + Option` while another IME is active, then switch to Doubao afterward, Doubao may miss the original key-down event.

This agent handles that ordering:

```text
physical Cmd+Option down
  -> suppress original event
  -> switch to Doubao IME
  -> wait until macOS confirms the switch
  -> wait a short settle delay
  -> post synthetic Cmd+Option down
  -> wait for physical release
  -> post synthetic Cmd+Option up
  -> switch back to WeType
```

## Menu Bar Status

The app has no Dock icon. It lives in the macOS menu bar:

- `豆 OK`, permissions and event tap are ready.
- `豆 !`, permissions or event tap need attention.
- `豆 REC`, the agent is managing the hold.
- `豆 ...`, starting or switching.

The menu shows current permissions, current input method, event tap state, restart count, and the latest event. It can also open the relevant macOS privacy settings.

Use `Restart agent` to let launchd restart the agent. Use `Quit agent` to unload the LaunchAgent and stop the menu bar process.

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
```

Edit the installed plist or template if you want to use a different restore IME or voice IME.

## Tune Voice Startup Timing

The agent keeps a persistent config file at:

```text
~/Library/Application Support/DoubaoVoiceWeTypeAgent/config.json
```

The default voice settle delay is `500` ms:

```json
{
  "voiceSettleDelayMs": 500
}
```

This is the extra wait after macOS reports Doubao as the active input source and before the agent posts synthetic `Command + Option` down. If Doubao switches in but the voice UI does not start, try increasing it, for example `700` or `900`. The value is clamped to `0...5000` ms and is read each time a managed hold starts, so edits apply on the next shortcut attempt.

You can also override it from LaunchAgent with:

```text
VOICE_SETTLE_DELAY_MS=700
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
- Third-party IMEs may report as selected before their own shortcut monitors are ready. The agent uses a confirmation loop plus a small settle delay, but timing can still be system-dependent.
- The agent listens only for `flagsChanged` events and the exact `Command + Option` modifier combination.
