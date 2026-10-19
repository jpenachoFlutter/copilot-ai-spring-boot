#!/usr/bin/env bash
# Installs this repo's Copilot CLI agents, skills and instructions into $COPILOT_HOME (default ~/.copilot) as symlinks.
# Idempotent: re-running refreshes links. Conflicting real files/dirs are moved to *.bak.<timestamp>.
# Usage: ./install.sh [--copy] [--uninstall] [--dry-run] [--skip-upstream]
#   --copy           copy files instead of symlinking (use if Copilot CLI does not pick up symlinked agents/skills; re-run after every pull)
#   --skip-upstream  don't fetch/link the upstream apache/flink-agents `flink-agents-dev` skill (pinned SHA, into .upstream/)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${COPILOT_HOME:-$HOME/.copilot}"
MODE=install
DRY=0
COPY=0
SKIP_UPSTREAM=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE=uninstall ;;
    --dry-run)   DRY=1 ;;
    --copy)      COPY=1 ;;
    --skip-upstream) SKIP_UPSTREAM=1 ;;
    -h|--help)   sed -n '2,6p' "$0"; exit 0 ;;
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

# Upstream skill: apache/flink-agents dev/agent-skills/flink-agents-dev (only on main so far, not in a release tag).
# Bump deliberately: update the SHA, re-run ./install.sh, re-check flink-agents-gst against the new upstream skill.
FLINK_AGENTS_URL="https://github.com/apache/flink-agents.git"
FLINK_AGENTS_SHA="a50a8a180d5ee0f6fa4f6259b098161c458b257c"   # main @ 2026-10-19
FLINK_AGENTS_SKILL="dev/agent-skills/flink-agents-dev"
UPSTREAM_DIR="$REPO/.upstream/flink-agents"

fetch_upstream() {   # sparse, shallow checkout of the pinned SHA; returns 1 (with a warning) if unavailable
  if [[ -d "$UPSTREAM_DIR/.git" && "$(git -C "$UPSTREAM_DIR" rev-parse HEAD 2>/dev/null)" == "$FLINK_AGENTS_SHA" ]]; then
    echo "ok      upstream flink-agents @ ${FLINK_AGENTS_SHA:0:12}"; return 0
  fi
  if [[ $DRY == 1 ]]; then echo "[dry-run] fetch $FLINK_AGENTS_URL @ $FLINK_AGENTS_SHA into $UPSTREAM_DIR"; return 0; fi
  echo "fetch   $FLINK_AGENTS_URL @ ${FLINK_AGENTS_SHA:0:12}"
  {
    mkdir -p "$UPSTREAM_DIR" &&
    { [[ -d "$UPSTREAM_DIR/.git" ]] || git -C "$UPSTREAM_DIR" init -q; } &&
    { git -C "$UPSTREAM_DIR" remote set-url origin "$FLINK_AGENTS_URL" 2>/dev/null ||
      git -C "$UPSTREAM_DIR" remote add origin "$FLINK_AGENTS_URL"; } &&
    git -C "$UPSTREAM_DIR" sparse-checkout set "$FLINK_AGENTS_SKILL" &&
    git -C "$UPSTREAM_DIR" fetch -q --depth 1 --filter=blob:none origin "$FLINK_AGENTS_SHA" &&
    git -C "$UPSTREAM_DIR" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
  } || { echo "warning: could not fetch upstream flink-agents; skipping flink-agents-dev (re-run later)" >&2; return 1; }
  if [[ "$(git -C "$UPSTREAM_DIR" rev-parse HEAD)" != "$FLINK_AGENTS_SHA" || ! -f "$UPSTREAM_DIR/$FLINK_AGENTS_SKILL/SKILL.md" ]]; then
    echo "warning: upstream checkout does not match $FLINK_AGENTS_SHA; skipping flink-agents-dev" >&2; return 1
  fi
}

items=()
for f in "$REPO"/agents/*.agent.md;               do items+=("$f|$TARGET/agents/$(basename "$f")"); done
for d in "$REPO"/skills/*/;                       do d="${d%/}"; items+=("$d|$TARGET/skills/$(basename "$d")"); done
for f in "$REPO"/instructions/*.instructions.md;  do items+=("$f|$TARGET/instructions/$(basename "$f")"); done

UPSTREAM_ITEM="$UPSTREAM_DIR/$FLINK_AGENTS_SKILL|$TARGET/skills/flink-agents-dev"
if [[ $MODE == install && $SKIP_UPSTREAM == 0 ]] && fetch_upstream; then items+=("$UPSTREAM_ITEM"); fi
if [[ $MODE == uninstall ]]; then items+=("$UPSTREAM_ITEM"); fi

if [[ $MODE == install ]]; then
  run mkdir -p "$TARGET/agents" "$TARGET/skills" "$TARGET/instructions"
  for it in "${items[@]}"; do link "${it%%|*}" "${it##*|}"; done
  echo "Installed into $TARGET. Restart Copilot CLI, then check with /agent, /skills and /instructions."
else
  for it in "${items[@]}"; do unlink_ours "${it##*|}"; done
  echo "Uninstalled links from $TARGET (backups, if any, were left in place; $REPO/.upstream is kept)."
fi
