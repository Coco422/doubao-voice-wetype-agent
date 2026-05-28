# AGENTS.md

This repository contains a small macOS Swift menu bar agent. Keep changes scoped and test with `swift build -c release`.

## Boundaries

- Do not hardcode a local user path. Use `$HOME`, `FileManager.default.homeDirectoryForCurrentUser`, or LaunchAgent environment variables.
- Keep the agent usable without Xcode. SwiftPM and the system Swift toolchain should be enough.
- Preserve the default Doubao voice IME and WeType restore IME IDs unless a change explicitly makes them configurable.
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
