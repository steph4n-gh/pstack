#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_PLUGINS_DIR="${AGY_PLUGINS_DIR:-$HOME/.gemini/config/plugins}"
AGY_TARGET="$AGY_PLUGINS_DIR/pstack"
CODEX_SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
CURSOR_RULES_DIR="$HOME/.cursor/rules"

mkdir -p "$AGY_PLUGINS_DIR" "$CODEX_SKILLS_DIR" "$CURSOR_RULES_DIR"

# 1. Install into Antigravity plugins if cloned outside ~/.gemini/config/plugins/pstack
if [ "$REPO_ROOT" != "$AGY_TARGET" ]; then
  if [ -L "$AGY_TARGET" ] || [ -e "$AGY_TARGET" ]; then
    rm -rf "$AGY_TARGET"
  fi
  ln -s "$REPO_ROOT" "$AGY_TARGET"
  echo "==> Linked Antigravity plugin: $AGY_TARGET -> $REPO_ROOT"
else
  echo "==> Antigravity plugin already in place at: $AGY_TARGET"
fi

# 2. Symlink all skills into Codex skills directory
SKILL_COUNT=0
for skill_dir in "$AGY_TARGET"/skills/*; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  ln -sfn "$skill_dir" "$CODEX_SKILLS_DIR/$skill_name"
  SKILL_COUNT=$((SKILL_COUNT + 1))
done
echo "==> Symlinked $SKILL_COUNT skills into Codex: $CODEX_SKILLS_DIR"

# 3. Install default inherit-parent model rule if absent (or --force)
if [ ! -f "$CURSOR_RULES_DIR/pstack-models.mdc" ] || [ "${1:-}" = "--force" ]; then
  cp "$REPO_ROOT/config/pstack-models.mdc" "$CURSOR_RULES_DIR/pstack-models.mdc"
  echo "==> Installed model routing rule: $CURSOR_RULES_DIR/pstack-models.mdc"
else
  echo "==> Existing $CURSOR_RULES_DIR/pstack-models.mdc preserved (pass --force to overwrite)"
fi

echo "==> Done! pstack is ready for both Antigravity and Codex."
