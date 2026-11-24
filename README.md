# Termux Android Agent Kit

**Agentic-friendly** cross-agent skill + CLI toolkit for running **100% offline multilingual voice dictation (`whisper.cpp`)**, **TUI voice input (`tmux` popup)**, **Termux:API microphone capture**, **local Wireless ADB**, and **Android app launching** on non-rooted Android devices (Android 14–16, including Xiaomi HyperOS / MIUI).

Designed from the ground up to be immediately usable by both **humans** and **AI coding agents** (**Antigravity**, **Codex**, **Hermes**, **Claude Code**, etc.).

---

## Features

- **Cross-Agent Skill Discovery**: Ships in `.agents/skills/termux-android-mic-adb/SKILL.md` with standard YAML frontmatter, `AGENTS.md`, `llms.txt`, and structured JSON diagnostics (`check_env.sh --json`).
- **100% Offline Multilingual Voice Dictation (`vdict` / `dictate --offline`)**: Records from Android's microphone via `Termux:API`, converts with `ffmpeg`, and transcribes locally using `whisper.cpp` across **99+ languages** (`-l auto` by default, or any ISO-639-1 code such as `en`, `es`, `fr`, `de`, `it`, `ja`, `ko`, `pt`, `zh`, etc.) — no cloud dependency or missing OEM offline language packs.
- **Direct TUI Dictation (`voice-tui`)**: Triggered via `Alt+v`, `Ctrl+b v`, or a 1-tap `VOICE` Termux extra key — opens a floating `tmux` popup over any TUI (Antigravity, Codex, Hermes, bash), transcribes offline, and pastes cleanly into the active input box without auto-submitting `ENTER`.
- **Wireless ADB & OEM Runbook**: Practical, sanctioned workarounds for Android / HyperOS quirks (`INSTALL_FAILED_USER_RESTRICTED`, `pm grant` restrictions, background Doze kills, F-Droid signing key matching, MediaStore indexing).
- **Android App & URL Launching**: Verified commands to discover installed packages and launch apps (GitHub, Chrome, Brave, Settings, etc.) from Termux or Wireless ADB.

---

## Quick Start

### For Humans
```bash
git clone https://github.com/Sample2845/termux-android-agent-kit.git
cd termux-android-agent-kit

# Preview what will be installed
bash install.sh --all --dry-run

# Install skill (symlinked into detected agent directories) + CLI scripts
bash install.sh --all

# Check environment status
bash .agents/skills/termux-android-mic-adb/scripts/check_env.sh
```

### For AI Agents
1. Read [`AGENTS.md`](./AGENTS.md) and [`.agents/skills/termux-android-mic-adb/SKILL.md`](./.agents/skills/termux-android-mic-adb/SKILL.md).
2. Run static or live structured diagnostics before taking action (device-identifying fields are omitted by default; pass `--include-device-info` to opt in):
   ```bash
   bash .agents/skills/termux-android-mic-adb/scripts/check_env.sh --static --json
   bash .agents/skills/termux-android-mic-adb/scripts/check_env.sh --json
   ```
3. Run `bash scripts/test.sh` and `bash install.sh --skill-only --dry-run` before installing.

---

## CLI Usage

```bash
# Offline multilingual dictation via whisper.cpp (default: auto language detection)
vdict                      # Record until ENTER, auto-detect language, print to stdout
vdict -l en                # Force English offline transcription
vdict -l es -s 6           # Record 6 seconds in Spanish automatically (script/agent friendly)
vdict -l fr -c             # Continuous French dictation until Ctrl+C
vdict -c -o notes.txt      # Continuous dictation appended to notes.txt
vdict -k                   # Dictate offline and copy to Android clipboard
vdict -m ~/.local/share/whisper/ggml-base-q5_1.bin  # Use a lighter/faster model
vdict --test               # Check Termux:API, whisper-cli, ffmpeg, and model

# Set a persistent default language (optional)
export WHISPER_LANG=en     # or auto, es, fr, de, it, ja, ko, zh, etc.

# Android system Speech-to-Text via Termux:API
dictate                    # Single utterance -> stdout
dictate -p                 # Real-time partial results
```

---

## Multilingual Offline Models (`whisper.cpp`)

Choose a quantized multilingual model based on your device RAM and desired speed/accuracy trade-off (all support 99+ languages):

| Model | Size | Best For |
| :--- | :--- | :--- |
| `ggml-tiny-q5_1.bin` | ~32 MB | Ultra-fast transcription on low-end CPUs |
| `ggml-base-q5_1.bin` | ~60 MB | Fast everyday multilingual dictation |
| `ggml-small-q5_1.bin` | ~182 MB | Recommended balance of speed & accuracy across non-English languages |
| `ggml-medium-q5_0.bin` | ~539 MB | Higher accuracy on flagship ARM64 devices with >= 8 GB RAM |

Download any model into `~/.local/share/whisper/` from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/<model_filename>` and point `WHISPER_MODEL` to it if using a model other than `ggml-small-q5_1.bin`.

---

## Prerequisites on Android (Termux)

1. Install **Termux** and **Termux:API** from the **same distribution source** (recommended: **F-Droid**; never mix F-Droid and Google Play builds because signing keys must match).
2. Grant **Microphone** permission to `Termux:API`, enable **Autostart** (on HyperOS/MIUI/OEM ROMs), and set **Battery** to **No restrictions**.
3. Install Termux packages:
   ```bash
   pkg install -y termux-api ffmpeg android-tools
   ```
4. For offline Whisper mode (`vdict` / `dictate --offline`), compile [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) (`whisper-cli`) and download a multilingual GGML model. Full ARM64 build steps are documented in [`SKILL.md`](./.agents/skills/termux-android-mic-adb/SKILL.md).

---

## Repository Layout

```text
.
├── AGENTS.md
├── LICENSE
├── README.md
├── llms.txt
├── install.sh
├── .agents/skills/termux-android-mic-adb/
│   ├── SKILL.md
│   └── scripts/check_env.sh
├── bin/
│   ├── dictate
│   ├── vdict
│   └── voice-tui
└── examples/
    ├── tmux-voice.conf
    └── termux-extra-keys.properties
```

## License

MIT — see [`LICENSE`](./LICENSE).
