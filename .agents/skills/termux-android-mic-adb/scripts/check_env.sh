#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

JSON_MODE=false
if [ "${1:-}" = "--json" ]; then
  JSON_MODE=true
fi

MODEL_PATH="${WHISPER_MODEL:-$HOME/.local/share/whisper/ggml-small-q5_1.bin}"
DEVICE_MODEL="$(getprop ro.product.model 2>/dev/null || echo unknown)"
ANDROID_VER="$(getprop ro.build.version.release 2>/dev/null || echo unknown)"
APK_RELEASE="${TERMUX_APP__APK_RELEASE:-unknown}"

has_cmd() { command -v "$1" >/dev/null 2>&1; }

TERMUX_API_OK=false
if has_cmd termux-battery-status && timeout 5 termux-battery-status >/dev/null 2>&1; then
  TERMUX_API_OK=true
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

ADB_STATE="missing"
ADB_COUNT=0
if has_cmd adb; then
  ADB_COUNT="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {c++} END {print c+0}')"
  if [ "$ADB_COUNT" -gt 0 ]; then
    ADB_STATE="connected"
  else
    ADB_STATE="disconnected"
  fi
fi

VDICT_OK=false; has_cmd vdict && VDICT_OK=true
DICTATE_OK=false; has_cmd dictate && DICTATE_OK=true
VOICE_TUI_OK=false; has_cmd voice-tui && VOICE_TUI_OK=true
WHISPER_OK=false; has_cmd whisper-cli && WHISPER_OK=true
FFMPEG_OK=false; has_cmd ffmpeg && FFMPEG_OK=true
MODEL_OK=false; [ -s "$MODEL_PATH" ] && MODEL_OK=true

if [ "$JSON_MODE" = true ]; then
  cat <<EOF
{
  "device_model": "$(printf '%s' "$DEVICE_MODEL" | sed 's/"/\\"/g')",
  "android_version": "$(printf '%s' "$ANDROID_VER" | sed 's/"/\\"/g')",
  "termux_apk_release": "$(printf '%s' "$APK_RELEASE" | sed 's/"/\\"/g')",
  "termux_api_responding": $TERMUX_API_OK,
  "microphone_api_status": "$MIC_STATUS",
  "commands": {
    "vdict": $VDICT_OK,
    "dictate": $DICTATE_OK,
    "voice_tui": $VOICE_TUI_OK,
    "whisper_cli": $WHISPER_OK,
    "ffmpeg": $FFMPEG_OK
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

echo "=== Device & Termux ==="
echo "Model: $DEVICE_MODEL | Android: $ANDROID_VER | Termux release: $APK_RELEASE"
echo ""
echo "=== Termux:API & Microphone ==="
echo "termux-battery-status: $([ "$TERMUX_API_OK" = true ] && echo OK || echo TIMEOUT/ERROR)"
echo "microphone_api_status: $MIC_STATUS"
echo ""
echo "=== Dictation Stack ==="
echo "vdict:       $([ "$VDICT_OK" = true ] && echo OK || echo MISSING)"
echo "dictate:     $([ "$DICTATE_OK" = true ] && echo OK || echo MISSING)"
echo "voice-tui:   $([ "$VOICE_TUI_OK" = true ] && echo OK || echo MISSING)"
echo "whisper-cli: $([ "$WHISPER_OK" = true ] && echo OK || echo MISSING)"
echo "ffmpeg:      $([ "$FFMPEG_OK" = true ] && echo OK || echo MISSING)"
echo "model:       $([ "$MODEL_OK" = true ] && echo "OK ($MODEL_PATH)" || echo "MISSING ($MODEL_PATH)")"
echo ""
echo "=== ADB ==="
echo "state: $ADB_STATE (connected devices: $ADB_COUNT)"
