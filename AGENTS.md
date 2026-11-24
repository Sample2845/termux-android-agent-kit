# AGENTS.md — Agent Entrypoint

This repository (`termux-android-agent-kit`) is an **agentic-friendly** toolkit and cross-agent skill package for non-rooted Android devices running **Termux** (including Android 14–16 and Xiaomi HyperOS/MIUI).

It enables AI agents (Antigravity, Codex, Hermes, Claude Code, etc.) and human operators to:
1. Capture microphone audio and run **100% offline multilingual voice dictation** (`whisper.cpp` + `ffmpeg` + `Termux:API`), including direct floating-popup dictation into `tmux` TUI panes (`voice-tui`).
2. Operate **local Wireless ADB** reliably (including OEM/HyperOS workarounds).
3. Launch Android apps, URLs, and Settings screens cleanly via Termux or Wireless ADB.
4. Organize launcher icons and folders using authorized ADB or temporary UHID input.

## Canonical Skills

- Home-screen organization: [`.agents/skills/android-home-organizer/SKILL.md`](./.agents/skills/android-home-organizer/SKILL.md).
  Its controller uses only existing shell access to UHID and never changes permission restrictions.

- Primary skill file: [`.agents/skills/termux-android-mic-adb/SKILL.md`](./.agents/skills/termux-android-mic-adb/SKILL.md)
- Environment diagnostic (supports `--json` for structured parsing):
  ```bash
  bash .agents/skills/termux-android-mic-adb/scripts/check_env.sh --json
  ```

## Repository Map

- `.agents/skills/termux-android-mic-adb/SKILL.md` — Cross-agent skill runbook (YAML frontmatter compatible with Antigravity, Codex, Hermes, Claude Code).
- `.agents/skills/termux-android-mic-adb/scripts/check_env.sh` — Non-destructive device/API/Whisper/ADB health check (`--json` supported).
- `bin/dictate` — Multilingual voice dictation CLI (`--offline` via `whisper.cpp` or Android Speech-to-Text via `Termux:API`).
- `bin/vdict` — Short alias wrapper for `dictate --offline`.
- `bin/voice-tui` — `tmux display-popup` dictation bridge that pastes transcribed text into the active TUI pane without auto-submitting `ENTER`.
- `examples/tmux-voice.conf` — Reusable `tmux` keybindings (`Alt+v`, `Prefix+v`).
- `examples/termux-extra-keys.properties` — Reusable Termux 1-tap `VOICE` extra-key snippet.
- `install.sh` — Idempotent installer (`--dry-run`, `--skill-only`, `--bin-only`, `--all`).
- `llms.txt` — Minimal discovery index for LLM agents.

## Safe Verification Commands

```bash
# Run full static host-side test suite (no microphone or ADB probes)
bash scripts/test.sh

# Static machine-readable diagnostics (privacy-minimal by default; add --include-device-info to opt in)
bash .agents/skills/termux-android-mic-adb/scripts/check_env.sh --static --json

# Dry-run transactional installation (makes no changes)
bash install.sh --all --dry-run
```

## Contribution & Security Rules for Agents

- **Never commit personal or device-identifying data**: no private/public IPs, ADB ports, pairing codes/GUIDs, serial numbers, exact personal device nicknames, real names, personal emails, or tokens/keys. Use placeholders (`<DEVICE_IP>`, `<ADB_PORT>`, `<PAIRING_PORT>`).
- **Keep everything neutral English and multilingual**: default language detection to `auto` (`-l auto` / `WHISPER_LANG`) so any user worldwide can select their language.
- **Least privilege & sanctioned paths only**: never attempt to bypass Android security prompts, Play Protect, or OEM permission restrictions. Document official user-confirmed flows only.
- Keep scripts POSIX/Bash-safe (`set -euo pipefail`), idempotent, and verifiable via `--dry-run` or `--test`.
