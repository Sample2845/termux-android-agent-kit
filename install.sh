#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="termux-android-mic-adb"
SKILL_SRC="$REPO_DIR/.agents/skills/$SKILL_NAME"
BIN_DEST="${PREFIX:-$HOME/.local}/bin"

INSTALL_SKILL=false
INSTALL_BIN=false
DRY_RUN=false

show_help() {
  cat <<'EOF'
Usage: bash install.sh [options]

Idempotent installer for termux-android-agent-kit.

Options:
  --all         Install both the cross-agent skill and CLI scripts (default)
  --skill-only  Install/symlink only the cross-agent skill
  --bin-only    Install only bin/{dictate,vdict,voice-tui} into $PREFIX/bin
  --dry-run     Print planned actions without making any changes
  -h, --help    Show this help
EOF
}

if [ $# -eq 0 ]; then
  INSTALL_SKILL=true
  INSTALL_BIN=true
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --all) INSTALL_SKILL=true; INSTALL_BIN=true ;;
    --skill-only) INSTALL_SKILL=true ;;
    --bin-only) INSTALL_BIN=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown option: $1 (use --help)" >&2; exit 1 ;;
  esac
  shift
done

run_step() {
  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

if [ "$INSTALL_SKILL" = true ]; then
  CANONICAL_DIR="$HOME/.agents/skills/$SKILL_NAME"
  echo "Installing skill '$SKILL_NAME' to $CANONICAL_DIR..."
  run_step mkdir -p "$HOME/.agents/skills"
  run_step rm -rf "$CANONICAL_DIR"
  run_step cp -r "$SKILL_SRC" "$CANONICAL_DIR"
  run_step chmod +x "$CANONICAL_DIR/scripts/check_env.sh"

  # Symlink into any detected agent global skill directories
  for agent_root in \
    "$HOME/.gemini/config" \
    "$HOME/.codex" \
    "$HOME/.hermes" \
    "$HOME/.claude"; do
    if [ -d "$agent_root" ]; then
      echo "Linking skill into $agent_root/skills/$SKILL_NAME..."
      run_step mkdir -p "$agent_root/skills"
      run_step ln -sfn "$CANONICAL_DIR" "$agent_root/skills/$SKILL_NAME"
    fi
  done
fi

if [ "$INSTALL_BIN" = true ]; then
  echo "Installing CLI scripts into $BIN_DEST..."
  run_step mkdir -p "$BIN_DEST"
  for script in dictate vdict voice-tui; do
    run_step install -m 755 "$REPO_DIR/bin/$script" "$BIN_DEST/$script"
  done
fi

echo "Done!$([ "$DRY_RUN" = true ] && echo ' (dry-run only; no files modified)')"
