#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "[1/5] Shell syntax checks..."
bash -n install.sh scripts/test.sh bin/dictate bin/vdict bin/voice-tui \
  .agents/skills/termux-android-mic-adb/scripts/check_env.sh
echo "  [OK]"

echo "[2/5] Static JSON diagnostics check (no live Android/ADB probes)..."
OUT="$(bash .agents/skills/termux-android-mic-adb/scripts/check_env.sh --static --json)"
printf '%s\n' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["mode"] == "static", d
assert d["termux_api_status"] == "skipped", d
assert "device_info" not in d, "device_info must be opt-in"
'
echo "  [OK]"

echo "[3/5] Reject unknown flags in check_env.sh and dictate..."
if bash .agents/skills/termux-android-mic-adb/scripts/check_env.sh --bogus-flag >/dev/null 2>&1; then
  echo "  [FAIL] check_env.sh accepted unknown flag" >&2
  exit 1
fi
if bash bin/dictate -s notanumber >/dev/null 2>&1; then
  echo "  [FAIL] dictate accepted invalid -s value" >&2
  exit 1
fi
echo "  [OK]"

echo "[4/5] Reject unsafe tmux pane id in voice-tui..."
if bash bin/voice-tui '1; touch /tmp/pwned' >/dev/null 2>&1; then
  echo "  [FAIL] voice-tui accepted malicious pane id" >&2
  exit 1
fi
echo "  [OK]"

echo "[5/5] Installer dry-run check..."
bash install.sh --all --dry-run >/dev/null
echo "  [OK]"

echo "ALL HOST-SIDE TESTS PASSED"
