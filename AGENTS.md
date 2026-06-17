# AGENTS.md

This repository contains a small macOS Swift menu bar agent. Keep changes scoped and test with `swift build -c release`.

## Boundaries

- Do not hardcode a local user path. Use `$HOME`, `FileManager.default.homeDirectoryForCurrentUser`, or LaunchAgent environment variables.
- Keep the agent usable without Xcode. SwiftPM and the system Swift toolchain should be enough.
- Preserve the default Doubao voice IME and WeType restore IME IDs unless a change explicitly makes them configurable.
- Keep the physical `triggerKey` (the key the user holds, detected by key code) decoupled from `voiceShortcutModifiers` (the shortcut replayed to Doubao). Do not hardcode `rightCommand` or `Command + Option` except as default values.
- Keep Doubao window-geometry probing diagnostic-only. The normal activation path should switch IME (skip if already on it), post the replayed shortcut down from a private event source, verify voice started via a screen-independent signal (microphone running, or a new Doubao-owned window) with a bounded clean re-trigger, hold until the trigger key is released, then post up and restore the input source the user started from.
- Reading microphone device state (`kAudioDevicePropertyDeviceIsRunningSomewhere`) is inspection only; do not add audio capture or request the Microphone permission.
- Avoid long blocking work inside the CGEvent tap callback. Schedule slow work on the serial worker queue.
- Keep user-facing troubleshooting in `README.md` and `docs/TROUBLESHOOTING.md`.

## Verification

Run:

```bash
swift build -c release
plutil -lint launchd/com.github.Coco422.doubao-voice-wetype-agent.plist.template
```

When touching packaging or installer scripts, also run:

```bash
bash -n scripts/install.sh scripts/install_or_update_app.sh scripts/package_dmg.sh scripts/uninstall.sh
```
