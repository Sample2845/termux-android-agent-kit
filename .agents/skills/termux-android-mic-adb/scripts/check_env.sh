#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

JSON_MODE=false
STATIC_MODE=false
INCLUDE_DEVICE_INFO=false

show_help() {
  cat <<'EOF'
Usage: bash check_env.sh [options]

Diagnostic check for the Termux Android Agent Kit environment.

Options:
  --json                 Emit RFC 8259 JSON (recommended for AI agents)
  --static               Check only local binaries/files (do not contact Termux:API or ADB)
  --include-device-info  Opt-in to include device model, Android version, and APK release
  -h, --help             Show this help

Privacy note:
  By default, device-identifying fields (model, Android version, APK release) are omitted
  to minimize environment fingerprinting. Transcripts are never printed.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_MODE=true ;;
    --static) STATIC_MODE=true ;;
    --include-device-info) INCLUDE_DEVICE_INFO=true ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown option: $1 (use --help)" >&2; exit 2 ;;
  esac
  shift
done

MODEL_PATH="${WHISPER_MODEL:-$HOME/.local/share/whisper/ggml-small-q5_1.bin}"
has_cmd() { command -v "$1" >/dev/null 2>&1; }

VDICT_OK=false; has_cmd vdict && VDICT_OK=true
DICTATE_OK=false; has_cmd dictate && DICTATE_OK=true
VOICE_TUI_OK=false; has_cmd voice-tui && VOICE_TUI_OK=true
WHISPER_OK=false; has_cmd whisper-cli && WHISPER_OK=true
FFMPEG_OK=false; has_cmd ffmpeg && FFMPEG_OK=true
ADB_BIN_OK=false; has_cmd adb && ADB_BIN_OK=true
MODEL_OK=false; [ -s "$MODEL_PATH" ] && MODEL_OK=true

TERMUX_API_STATE="skipped"
MIC_STATUS="skipped"
ADB_STATE="skipped"
ADB_COUNT=0

if [ "$STATIC_MODE" = false ]; then
  if has_cmd termux-battery-status && timeout 5 termux-battery-status >/dev/null 2>&1; then
    TERMUX_API_STATE="ok"
  else
    TERMUX_API_STATE="unavailable"
  fi

  MIC_STATUS="unavailable"
  if has_cmd termux-microphone-record; then
    MIC_OUT="$(timeout 5 termux-microphone-record -i 2>&1 || true)"
    if printf '%s' "$MIC_OUT" | grep -q '"isRecording"'; then
      MIC_STATUS="ok"
    elif printf '%s' "$MIC_OUT" | grep -qi 'RECORD_AUDIO'; then
      MIC_STATUS="missing_permission"
    elif [ -n "$MIC_OUT" ]; then
      MIC_STATUS="error"
    else
      MIC_STATUS="timeout"
    fi
  fi

  if [ "$ADB_BIN_OK" = true ]; then
    ADB_COUNT="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {c++} END {print c+0}')"
    if [ "$ADB_COUNT" -gt 0 ]; then
      ADB_STATE="connected"
    else
      ADB_STATE="disconnected"
    fi
  else
    ADB_STATE="missing"
  fi
fi

DEVICE_MODEL=""
ANDROID_VER=""
APK_RELEASE=""
if [ "$INCLUDE_DEVICE_INFO" = true ]; then
  DEVICE_MODEL="$(getprop ro.product.model 2>/dev/null || echo unknown)"
  ANDROID_VER="$(getprop ro.build.version.release 2>/dev/null || echo unknown)"
  APK_RELEASE="${TERMUX_APP__APK_RELEASE:-unknown}"
fi

if [ "$JSON_MODE" = true ]; then
  if has_cmd python3; then
    STATIC_MODE="$STATIC_MODE" \
    INCLUDE_DEVICE_INFO="$INCLUDE_DEVICE_INFO" \
    DEVICE_MODEL="$DEVICE_MODEL" \
    ANDROID_VER="$ANDROID_VER" \
    APK_RELEASE="$APK_RELEASE" \
    TERMUX_API_STATE="$TERMUX_API_STATE" \
    MIC_STATUS="$MIC_STATUS" \
    VDICT_OK="$VDICT_OK" \
    DICTATE_OK="$DICTATE_OK" \
    VOICE_TUI_OK="$VOICE_TUI_OK" \
    WHISPER_OK="$WHISPER_OK" \
    FFMPEG_OK="$FFMPEG_OK" \
    ADB_BIN_OK="$ADB_BIN_OK" \
    MODEL_OK="$MODEL_OK" \
    ADB_STATE="$ADB_STATE" \
    ADB_COUNT="$ADB_COUNT" \
    python3 - <<'PY'
import json, os

def b(name):
    return os.environ.get(name, "false") == "true"

data = {
    "mode": "static" if b("STATIC_MODE") else "live",
    "termux_api_status": os.environ["TERMUX_API_STATE"],
    "microphone_api_status": os.environ["MIC_STATUS"],
    "commands": {
        "vdict": b("VDICT_OK"),
        "dictate": b("DICTATE_OK"),
        "voice_tui": b("VOICE_TUI_OK"),
        "whisper_cli": b("WHISPER_OK"),
        "ffmpeg": b("FFMPEG_OK"),
        "adb": b("ADB_BIN_OK"),
    },
    "whisper_model_present": b("MODEL_OK"),
    "adb": {
        "state": os.environ["ADB_STATE"],
        "connected_devices": int(os.environ.get("ADB_COUNT", "0")),
    },
}

if b("INCLUDE_DEVICE_INFO"):
    data["device_info"] = {
        "device_model": os.environ.get("DEVICE_MODEL", "unknown"),
        "android_version": os.environ.get("ANDROID_VER", "unknown"),
        "termux_apk_release": os.environ.get("APK_RELEASE", "unknown"),
    }

print(json.dumps(data, indent=2))
PY
    exit 0
  else
    # Pure-shell fallback only emits controlled enum/boolean fields (no untrusted raw strings)
    cat <<EOF
{
  "mode": "$([ "$STATIC_MODE" = true ] && echo static || echo live)",
  "termux_api_status": "$TERMUX_API_STATE",
  "microphone_api_status": "$MIC_STATUS",
  "commands": {
    "vdict": $VDICT_OK,
    "dictate": $DICTATE_OK,
    "voice_tui": $VOICE_TUI_OK,
    "whisper_cli": $WHISPER_OK,
    "ffmpeg": $FFMPEG_OK,
    "adb": $ADB_BIN_OK
  },
  "whisper_model_present": $MODEL_OK,
  "adb": {
    "state": "$ADB_STATE",
    "connected_devices": $ADB_COUNT
  }
}
EOF
    exit 0
  fi
fi

echo "=== Diagnostics (mode: $([ "$STATIC_MODE" = true ] && echo static || echo live)) ==="
if [ "$INCLUDE_DEVICE_INFO" = true ]; then
  echo "Device: $DEVICE_MODEL | Android: $ANDROID_VER | Termux release: $APK_RELEASE"
fi
echo "termux-api:  $TERMUX_API_STATE"
echo "microphone:  $MIC_STATUS"
echo "vdict:       $([ "$VDICT_OK" = true ] && echo OK || echo MISSING)"
echo "dictate:     $([ "$DICTATE_OK" = true ] && echo OK || echo MISSING)"
echo "voice-tui:   $([ "$VOICE_TUI_OK" = true ] && echo OK || echo MISSING)"
echo "whisper-cli: $([ "$WHISPER_OK" = true ] && echo OK || echo MISSING)"
echo "ffmpeg:      $([ "$FFMPEG_OK" = true ] && echo OK || echo MISSING)"
echo "model:       $([ "$MODEL_OK" = true ] && echo OK || echo MISSING)"
echo "adb:         $ADB_STATE (connected: $ADB_COUNT)"
