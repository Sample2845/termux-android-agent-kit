#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAMES=(termux-android-mic-adb android-home-organizer)
BIN_DEST="${PREFIX:-$HOME/.local}/bin"

INSTALL_SKILL=false
INSTALL_BIN=false
DRY_RUN=false
KEEP_BACKUP=true

show_help() {
  cat <<'EOF'
Usage: bash install.sh [options]

Idempotent, backup-safe installer for termux-android-agent-kit.

Options:
  --all         Install the cross-agent skills and CLI scripts (default)
  --skill-only  Install/symlink only the cross-agent skills
  --bin-only    Install only bin/{dictate,vdict,voice-tui} into $PREFIX/bin
  --no-backup   Remove replaced pre-existing skill directory after staging succeeds
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
    --no-backup) KEEP_BACKUP=false ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown option: $1 (use --help)" >&2; exit 1 ;;
  esac
  shift
done

if [ "$INSTALL_SKILL" = false ] && [ "$INSTALL_BIN" = false ]; then
  INSTALL_SKILL=true
  INSTALL_BIN=true
fi

run_step() {
  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

install_skill_safe() {
  local SKILL_NAME="$1"
  local SKILL_SRC="$REPO_DIR/.agents/skills/$SKILL_NAME"
  local skills_root="$HOME/.agents/skills"
  local canonical_dir="$skills_root/$SKILL_NAME"
  local ts
  ts="$(date +%Y%m%d%H%M%S)"
  local backup_dir="${canonical_dir}.bak.${ts}"

  echo "Installing skill '$SKILL_NAME' transactionally to $canonical_dir..."
  run_step mkdir -p "$skills_root"

  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] stage copy of $SKILL_SRC into sibling temp dir under $skills_root"
    if [ -e "$canonical_dir" ]; then
      echo "[dry-run] preserve existing $canonical_dir -> $backup_dir"
    fi
    echo "[dry-run] atomic mv staged dir -> $canonical_dir"
    if [ "$KEEP_BACKUP" = false ] && [ -e "$canonical_dir" ]; then
      echo "[dry-run] remove temporary backup $backup_dir"
    fi
  else
    local stage_dir
    stage_dir="$(mktemp -d "$skills_root/.${SKILL_NAME}.stage.XXXXXX")"
    trap 'rm -rf "${stage_dir:-}"' EXIT

    cp -r "$SKILL_SRC/." "$stage_dir/"
    if [ -f "$stage_dir/scripts/check_env.sh" ]; then
      chmod +x "$stage_dir/scripts/check_env.sh"
    fi

    local backed_up=false
    if [ -e "$canonical_dir" ] || [ -L "$canonical_dir" ]; then
      mv "$canonical_dir" "$backup_dir"
      backed_up=true
    fi

    if mv "$stage_dir" "$canonical_dir"; then
      stage_dir=""
      trap - EXIT
      if [ "$backed_up" = true ]; then
        if [ "$KEEP_BACKUP" = true ]; then
          echo "Preserved previous skill at: $backup_dir"
        else
          rm -rf "$backup_dir"
        fi
      fi
    else
      if [ "$backed_up" = true ] && [ -e "$backup_dir" ]; then
        mv "$backup_dir" "$canonical_dir" || true
      fi
      echo "Error: failed to swap staged skill into $canonical_dir" >&2
      exit 1
    fi
  fi

  # Symlink into any detected agent global skill directories
  for agent_root in \
    "$HOME/.gemini/config" \
    "$HOME/.codex" \
    "$HOME/.hermes" \
    "$HOME/.claude"; do
    if [ -d "$agent_root" ]; then
      echo "Linking skill into $agent_root/skills/$SKILL_NAME..."
      run_step mkdir -p "$agent_root/skills"
      run_step ln -sfn "$canonical_dir" "$agent_root/skills/$SKILL_NAME"
    fi
  done
}

if [ "$INSTALL_SKILL" = true ]; then
  for skill_name in "${SKILL_NAMES[@]}"; do
    install_skill_safe "$skill_name"
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
