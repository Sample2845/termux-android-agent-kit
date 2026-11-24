---
name: termux-android-mic-adb
description: >-
  Runbook and reference for microphone capture, offline multilingual voice dictation
  (whisper.cpp via vdict/dictate), floating tmux TUI dictation (voice-tui), Termux:API,
  local Wireless ADB, and launching Android apps/URLs/settings on non-rooted Android devices
  (Android 14-16, including Xiaomi HyperOS / MIUI). Use when capturing audio, dictating speech
  into Termux or TUI panes, troubleshooting Termux:API permissions, reconnecting Wireless ADB,
  or opening Android apps from Termux.
version: 1.0.0
platforms: [linux, android]
metadata:
  hermes:
    tags: [termux, android, microphone, speech-to-text, whisper, dictation, tmux, adb, hyperos]
    related_skills: []
---

# Termux Microphone, Offline Multilingual Dictation, Wireless ADB & App Launching

Verified runbook for AI agents and operators working inside **Termux** on non-rooted Android devices (Android 14–16, including Xiaomi HyperOS / MIUI, F-Droid builds).

---

## 1. Quick Diagnostics (Run First)

Always inspect live state before assuming binaries, permissions, or ADB connections are active:

```bash
# Human-readable diagnostic
bash .agents/skills/termux-android-mic-adb/scripts/check_env.sh

# Structured JSON output (preferred for AI agents)
bash .agents/skills/termux-android-mic-adb/scripts/check_env.sh --json
```

---

## 2. Architecture & Prerequisites

- **Why `Termux:API` is required**: The main `com.termux` APK does **not** declare `android.permission.RECORD_AUDIO`. Microphone capture and speech recognition must go through the companion `com.termux.api` Android app + the `termux-api` CLI package (`pkg install termux-api`).
- **Signing Key Rule**: `com.termux` and `com.termux.api` **must** come from the **same distribution source** (e.g., both from **F-Droid**, verified via `TERMUX_APP__APK_RELEASE=F_DROID`). Never mix F-Droid and Google Play builds.
- **Offline Multilingual Speech Recognition (`whisper.cpp`)**: Android's on-device Google SODA recognizer typically ships with only `en-US` preinstalled and lacks offline language packs for many regional locales. Compiling `whisper.cpp` locally provides 100% offline transcription across **99+ languages** without cloud dependency.

### Building `whisper-cli` on ARM64 Termux
```bash
pkg install -y ffmpeg cmake clang ninja git
git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git ~/.local/src/whisper.cpp
cd ~/.local/src/whisper.cpp

# Inspect /proc/cpuinfo Features first; adjust -DGGML_CPU_ARM_ARCH accordingly
# Common modern ARM64: armv8.2-a+fp16+dotprod+i8mm (fallback: armv8-a)
cmake -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_CPU_ARM_ARCH="armv8.2-a+fp16+dotprod+i8mm" \
  -DGGML_OPENMP=OFF
cmake --build build --target whisper-cli -j "$(nproc)"
install -m 755 build/bin/whisper-cli "$PREFIX/bin/whisper-cli"

# Download any multilingual GGML model (tiny/base/small/medium)
mkdir -p ~/.local/share/whisper
curl -fSL -C - -o ~/.local/share/whisper/ggml-small-q5_1.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin
```

### Selecting Languages & Models
- Pass `-l auto` (default) for automatic language detection, or any ISO-639-1 code (`-l en`, `-l es`, `-l fr`, `-l de`, `-l it`, `-l ja`, `-l ko`, `-l zh`, etc.).
- Set `WHISPER_LANG=<code` and `WHISPER_MODEL=<path>` in your shell profile for persistent defaults.
- Alternative quantized multilingual models on `ggerganov/whisper.cpp`:
  - `ggml-tiny-q5_1.bin` (~32 MB, fastest)
  - `ggml-base-q5_1.bin` (~60 MB, fast)
  - `ggml-small-q5_1.bin` (~182 MB, recommended speed/accuracy balance)
  - `ggml-medium-q5_0.bin` (~539 MB, higher accuracy on devices with >= 8 GB RAM)

---

## 3. Voice Dictation & Raw Audio Capture

### CLI Dictation (`vdict` / `dictate`)
```bash
# 100% offline via whisper.cpp (default: auto language detection)
vdict                    # Record until ENTER, transcribe offline -> stdout
vdict -l en              # Force English
vdict -l es -s 6         # Record 6 seconds in Spanish automatically (non-interactive / scripts)
vdict -c                 # Continuous dictation until Ctrl+C
vdict -c -o notes.txt    # Continuous dictation appended to notes.txt
vdict -k                 # Dictate and copy to Android clipboard
vdict --test             # Verify Termux:API, whisper-cli, ffmpeg, and model
dictate --offline        # Equivalent to 'vdict'

# Android / Google Speech Recognition via Termux:API
dictate                  # Single utterance -> stdout
dictate -p               # Real-time partial results
```

### Direct TUI Dictation inside `tmux` (`voice-tui`)
- Triggered via `Alt+v`, `Ctrl+b v`, or the Termux `VOICE` extra key (see `examples/tmux-voice.conf` and `examples/termux-extra-keys.properties`).
- Opens a floating `tmux display-popup` over the active pane, records offline until `ENTER`, transcribes with `whisper-cli`, and pastes cleanly into the target TUI input box via bracketed paste (`paste-buffer -d -p`) without auto-submitting `ENTER`.

### Raw Microphone Audio (`termux-microphone-record`)
```bash
# Wrap non-interactive probes with timeout (stdout may linger briefly on Termux:API 0.53.0)
timeout 5 termux-microphone-record -i
timeout 5 termux-microphone-record -f "$TMPDIR/audio.m4a" -l 10
termux-microphone-record -q
```

---

## 4. Local Wireless ADB (No Root)

> Wireless ADB IP addresses (DHCP) and ports are dynamic. Always run `adb devices` first and ask the user for the current `<DEVICE_IP>:<ADB_PORT>` from *Developer Options -> Wireless debugging* if disconnected.

### Pair (first time or after revocation)
1. Have the user open *Developer Options -> Wireless debugging* in **Split Screen or Floating Window** alongside Termux (switching apps normally closes Android's pairing dialog and invalidates the 6-digit code).
2. Run:
   ```bash
   adb start-server
   adb pair <DEVICE_IP>:<PAIRING_PORT> <6_DIGIT_CODE>
   adb connect <DEVICE_IP>:<ADB_PORT>
   adb devices -l
   ```
3. Note: Termux's `android-tools` build does **not** support `adb mdns`.

### Keep Termux & Termux:API Alive in Background
```bash
DEV=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')

adb -s "$DEV" shell dumpsys deviceidle whitelist +com.termux
adb -s "$DEV" shell dumpsys deviceidle whitelist +com.termux.api
adb -s "$DEV" shell appops set com.termux RUN_IN_BACKGROUND allow
adb -s "$DEV" shell appops set com.termux RUN_ANY_IN_BACKGROUND allow
adb -s "$DEV" shell appops set com.termux.api RUN_IN_BACKGROUND allow
adb -s "$DEV" shell appops set com.termux.api RUN_ANY_IN_BACKGROUND allow
```

---

## 5. Launching Android Apps, URLs & Settings Screens

### Without ADB (Termux-native, always available)
```bash
am start -a android.intent.action.VIEW -d "https://github.com"   # Most reliable URL opener from Termux
termux-open-url "https://github.com"                             # Alternative URL opener
termux-open /storage/emulated/0/Download/example.pdf             # Open local file in Android app
```

### Via Wireless ADB (full control, works from background panes)
```bash
DEV=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')

# Discover installed package names (2>/dev/null hides OEM secondary-user warnings)
adb -s "$DEV" shell pm list packages 2>/dev/null | grep -i github

# Launch any installed app by package name
adb -s "$DEV" shell monkey -p com.github.android -c android.intent.category.LAUNCHER 1
adb -s "$DEV" shell monkey -p com.android.chrome -c android.intent.category.LAUNCHER 1
adb -s "$DEV" shell monkey -p com.brave.browser -c android.intent.category.LAUNCHER 1

# Open URL in default handler or explicitly in Chrome
adb -s "$DEV" shell am start -a android.intent.action.VIEW -d "https://github.com"
adb -s "$DEV" shell am start -n com.android.chrome/com.google.android.apps.chrome.Main -a android.intent.action.VIEW -d "https://github.com"

# Open App Info or system Settings screens directly for user confirmation
adb -s "$DEV" shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:com.termux.api
adb -s "$DEV" shell am start -a android.settings.WIFI_SETTINGS
adb -s "$DEV" shell am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS
```

---

## 6. Android 14-16 / HyperOS / MIUI Gotchas & Sanctioned Workarounds

1. **`adb install` fails with `INSTALL_FAILED_USER_RESTRICTED`**: HyperOS/MIUI requires *Developer Options -> Install via USB*, which is often restricted without an active SIM / OEM account.
   - **Sanctioned workaround**: Open the official F-Droid APK URL in the browser via `am start -a android.intent.action.VIEW -d "https://f-droid.org/repo/com.termux.api_1002.apk"` so the user confirms installation natively.
2. **`adb shell pm grant` throws `SecurityException`**: Some OEM ROMs deny `GRANT_RUNTIME_PERMISSIONS` to ADB shell unless *USB debugging (Security settings)* is enabled.
   - **Sanctioned workaround**: Open `APPLICATION_DETAILS_SETTINGS` for the package via ADB and let the user toggle the permission in Android Settings.
3. **`termux-*` commands hang/timeout (`EXIT=124`)**: Caused by missing `Termux:API` app, F-Droid vs Play Store signature mismatch, or aggressive background killing. Apply the `deviceidle whitelist` + `appops` commands above and enable *Autostart* + *No Battery Restrictions* in app info.
4. **Files downloaded via `curl` missing in Google Files**: Termux writes to `/storage/emulated/0/Download/` without MediaStore indexing; navigate via *Browse -> Internal storage -> Download* or download via Chrome.
5. **Enabling Developer Options on HyperOS/MIUI**: *Settings -> About phone -> tap **OS version** 7 times* (rather than "Build number").
