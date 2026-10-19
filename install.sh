#!/usr/bin/env bash
# Installs this repo's Copilot CLI agents, skills and instructions into $COPILOT_HOME (default ~/.copilot) as symlinks.
# Idempotent: re-running refreshes links. Conflicting real files/dirs are moved to *.bak.<timestamp>.
# Usage: ./install.sh [--copy] [--uninstall] [--dry-run]
#   --copy  copy files instead of symlinking (use if Copilot CLI does not pick up symlinked agents/skills; re-run after every pull)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${COPILOT_HOME:-$HOME/.copilot}"
MODE=install
DRY=0
COPY=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE=uninstall ;;
    --dry-run)   DRY=1 ;;
    --copy)      COPY=1 ;;
    -h|--help)   sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

run() { if [[ $DRY == 1 ]]; then echo "[dry-run] $*"; else "$@"; fi; }
stamp="$(date +%Y%m%d%H%M%S)"

MARKER=".installed-from-copilot-ai-spring-boot"

link() {   # link <source> <dest>
  local src="$1" dest="$2"
  if [[ $COPY == 1 ]]; then
    if [[ -e "$dest" || -L "$dest" ]] && ! is_ours "$dest"; then
      echo "backup  $dest -> $dest.bak.$stamp"; run mv "$dest" "$dest.bak.$stamp"
    else
      run rm -rf "$dest"
    fi
    run cp -R "$src" "$dest"
    if [[ -d "$src" ]]; then run touch "$dest/$MARKER"; else run touch "$dest.$MARKER"; fi
    echo "copied  $dest"
    return
  fi
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "ok      $dest"; return
  elif [[ -e "$dest" || -L "$dest" ]] && ! is_ours "$dest"; then
    echo "backup  $dest -> $dest.bak.$stamp"
    run mv "$dest" "$dest.bak.$stamp"
  elif [[ -e "$dest" || -L "$dest" ]]; then
    run rm -rf "$dest" "$dest.$MARKER"   # our own previous link/copy
  fi
  run ln -s "$src" "$dest"
  echo "linked  $dest -> $src"
}

is_ours() {   # symlink into this repo, or a copy made by --copy
  local dest="$1"
  [[ -L "$dest" && "$(readlink "$dest")" == "$REPO"/* ]] && return 0
  [[ -d "$dest" && ! -L "$dest" && -e "$dest/$MARKER" ]] && return 0
  [[ -f "$dest" && ! -L "$dest" && -e "$dest.$MARKER" ]] && return 0
  return 1
}

unlink_ours() {   # remove only what this script installed
  local dest="$1"
  if is_ours "$dest"; then
    run rm -rf "$dest" "$dest.$MARKER"; echo "removed $dest"
  fi
}

items=()
for f in "$REPO"/agents/*.agent.md;               do items+=("$f|$TARGET/agents/$(basename "$f")"); done
for d in "$REPO"/skills/*/;                       do d="${d%/}"; items+=("$d|$TARGET/skills/$(basename "$d")"); done
for f in "$REPO"/instructions/*.instructions.md;  do items+=("$f|$TARGET/instructions/$(basename "$f")"); done

if [[ $MODE == install ]]; then
  run mkdir -p "$TARGET/agents" "$TARGET/skills" "$TARGET/instructions"
  for it in "${items[@]}"; do link "${it%%|*}" "${it##*|}"; done
  echo "Installed into $TARGET. Restart Copilot CLI, then check with /agent, /skills and /instructions."
else
  for it in "${items[@]}"; do unlink_ours "${it##*|}"; done
  echo "Uninstalled links from $TARGET (backups, if any, were left in place)."
fi
