#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/cursor/plugins.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Sparse-cloning cursor/plugins (pstack) from $UPSTREAM_REPO ($UPSTREAM_BRANCH)..."
git clone --depth 1 --filter=blob:none --sparse --branch "$UPSTREAM_BRANCH" "$UPSTREAM_REPO" "$TMP_DIR/cursor-plugins"
git -C "$TMP_DIR/cursor-plugins" sparse-checkout set pstack

UPSTREAM_PSTACK="$TMP_DIR/cursor-plugins/pstack"

echo "==> Syncing upstream files into $REPO_ROOT..."
for dir in .cursor-plugin agents assets automations docs skills; do
  if [ -d "$UPSTREAM_PSTACK/$dir" ]; then
    rm -rf "$REPO_ROOT/$dir"
    cp -R "$UPSTREAM_PSTACK/$dir" "$REPO_ROOT/$dir"
  fi
done
cp "$UPSTREAM_PSTACK/LICENSE" "$REPO_ROOT/LICENSE"
cat - "$UPSTREAM_PSTACK/README.md" > "$REPO_ROOT/README.md" <<'HEADER'
> **Antigravity & Codex Port of [`cursor/plugins/pstack`](https://github.com/cursor/plugins/tree/main/pstack)**
>
> **Quick Install (Antigravity + Codex):**
> ```bash
> git clone https://github.com/steph4n-gh/pstack.git ~/.gemini/config/plugins/pstack
> ~/.gemini/config/plugins/pstack/install.sh
> ```
>
> **Sync with Upstream (`cursor/plugins/pstack`):**
> ```bash
> ~/.gemini/config/plugins/pstack/scripts/sync-upstream.sh
> ~/.gemini/config/plugins/pstack/install.sh
> ```
>
> **What this port adapts automatically:**
> 1. **Antigravity Plugin Manifest ([`plugin.json`](./plugin.json)):** Generates a valid Antigravity plugin bundle with all 54 skills and 2 subagents (`poteto-agent` and `comment-sicko`).
> 2. **Frontmatter Normalization (`skills/*/SKILL.md`):** Strips Cursor-only YAML frontmatter keys (`disable-model-invocation: true`, `icon`, `color`, `paths`) and normalizes `name` to kebab-case so Antigravity exposes the skills in `<skills>` and all 54 skills pass Codex's `quick_validate.py`.
> 3. **Subagent Capabilities ([`agents/poteto-agent.md`](./agents/poteto-agent.md)):** Equips `poteto-agent` with Antigravity write/command tools, `inheritMcp: true`, `preloadSkills: [poteto-mode]`, and cross-agent lookup paths (`~/.gemini/config/plugins/pstack/skills/` and `~/.codex/skills/`).
> 4. **Cross-Agent Model Defaults ([`config/pstack-models.mdc`](./config/pstack-models.mdc)):** Configures `inherit-parent` across all roles so subagents in Antigravity and Codex inherit the active session model cleanly.

---

HEADER

echo "==> Applying Antigravity & Codex compatibility transforms..."
python3 - "$REPO_ROOT" <<'PY'
import glob
import json
import os
import sys
import yaml

repo_root = sys.argv[1]

# 1. Generate Antigravity-compatible plugin.json from .cursor-plugin/plugin.json
cursor_manifest_path = os.path.join(repo_root, ".cursor-plugin", "plugin.json")
with open(cursor_manifest_path, "r", encoding="utf-8") as f:
    cursor_manifest = json.load(f)

agy_manifest = {
    "name": "pstack",
    "displayName": cursor_manifest.get("displayName", "pstack"),
    "version": cursor_manifest.get("version", "0.15.25"),
    "description": cursor_manifest.get(
        "description",
        "If you want to go fast, go deep first. pstack helps you write less, but higher quality code.",
    ),
    "logo": "assets/logo.png",
    "suggestedPrompts": [
        "Use poteto-mode to reproduce a bug, trace its root cause, and fix it with runtime proof",
        "Use how to walk me through how a subsystem works end-to-end",
        "Use interrogate to run an adversarial review on my changes before shipping",
    ],
}

with open(os.path.join(repo_root, "plugin.json"), "w", encoding="utf-8") as f:
    json.dump(agy_manifest, f, indent=2)
    f.write("\n")

# 2. Normalize SKILL.md YAML frontmatter across all skills
#    - Ensure 'name' matches the kebab-case directory name
#    - Strip Cursor-proprietary keys (disable-model-invocation, icon, color, paths)
ALLOWED_KEYS = {"name", "description", "license", "allowed-tools", "metadata"}
skill_dirs = sorted(glob.glob(os.path.join(repo_root, "skills", "*")))
for skill_dir in skill_dirs:
    skill_md = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(skill_md):
        continue
    folder_name = os.path.basename(skill_dir)
    with open(skill_md, "r", encoding="utf-8") as f:
        text = f.read()
    if not text.startswith("---\n"):
        continue
    parts = text.split("\n---\n", 1)
    if len(parts) != 2:
        continue
    fm_raw, body = parts[0][4:], parts[1]
    data = yaml.safe_load(fm_raw) or {}
    cleaned = {"name": folder_name, "description": data["description"]}
    for k in ("license", "allowed-tools", "metadata"):
        if k in data:
            cleaned[k] = data[k]
    new_fm = yaml.safe_dump(cleaned, sort_keys=False, allow_unicode=True, width=1000).strip()
    with open(skill_md, "w", encoding="utf-8") as f:
        f.write(f"---\n{new_fm}\n---\n{body}")

# 3. Patch agents/poteto-agent.md with Antigravity write/command tools, preloadSkills, and cross-agent lookup paths
poteto_agent_md = os.path.join(repo_root, "agents", "poteto-agent.md")
if os.path.isfile(poteto_agent_md):
    with open(poteto_agent_md, "r", encoding="utf-8") as f:
        agent_text = f.read()
    parts = agent_text.split("\n---\n", 1)
    if len(parts) == 2:
        fm_data = yaml.safe_load(parts[0][4:]) or {}
        body = parts[1]
        agent_fm = {
            "name": fm_data.get("name", "poteto-agent"),
            "description": fm_data.get("description", ""),
            "inheritMcp": True,
            "preloadSkills": ["poteto-mode"],
            "tools": [
                "view_file",
                "write_to_file",
                "replace_file_content",
                "run_command",
                "manage_task",
                "read_url_content",
                "search_web",
                "send_message",
                "schedule",
                "generate_image",
            ],
        }
        body = body.replace(
            "search `~/.cursor/plugins/` for a file whose path ends in `skills/poteto-mode/SKILL.md`. If more than one file matches, use the copy whose `.cursor-plugin/plugin.json` has the highest `version`.",
            "check `~/.gemini/config/plugins/pstack/skills/poteto-mode/SKILL.md` (Antigravity), `~/.codex/skills/poteto-mode/SKILL.md` (Codex), or search `~/.cursor/plugins/` for a file whose path ends in `skills/poteto-mode/SKILL.md`. If more than one file matches, use the copy whose `plugin.json` has the highest `version`.",
        )
        new_agent_fm = yaml.safe_dump(agent_fm, sort_keys=False, allow_unicode=True, width=1000).strip()
        with open(poteto_agent_md, "w", encoding="utf-8") as f:
            f.write(f"---\n{new_agent_fm}\n---\n{body}")

# 4. Patch skills/poteto-mode/SKILL.md Subagents section with Antigravity & Codex tool/model mapping notes
poteto_mode_md = os.path.join(repo_root, "skills", "poteto-mode", "SKILL.md")
if os.path.isfile(poteto_mode_md):
    with open(poteto_mode_md, "r", encoding="utf-8") as f:
        pm_text = f.read()
    pm_text = pm_text.replace(
        '**Use `subagent_type: "poteto-agent"` for any subagent you spawn inside a playbook step** (code-writing delegates, ad-hoc helpers).',
        '**Use `subagent_type: "poteto-agent"` for any subagent you spawn inside a playbook step** (code-writing delegates, ad-hoc helpers; in Antigravity, use `invoke_subagent` with `TypeName: "poteto-agent"` or `"self"` and pass the path `~/.gemini/config/plugins/pstack/skills/poteto-mode/SKILL.md`; in Codex, spawn a subagent thread and instruct it to read `~/.codex/skills/poteto-mode/SKILL.md`; use `ask_question` / `request_user_input` anywhere a skill names `AskQuestion`).',
    )
    pm_text = pm_text.replace(
        "(configurable via `/setup-pstack`. Defaults `grok-4.7-xhigh-fast` for code, `claude-opus-5-5-xhigh` for prose and judgment).",
        "(configurable via `/setup-pstack`. In Antigravity and Codex, when Cursor-specific model slugs like `grok-4.7-xhigh-fast` or `claude-opus-5-5-xhigh` are not available, default to `inherit` / `inherit-parent` or map code/fast tasks to `pro`/`flash` in Antigravity and appropriate reasoning effort in Codex).",
    )
    with open(poteto_mode_md, "w", encoding="utf-8") as f:
        f.write(pm_text)

print(f"Transformed {len(skill_dirs)} skills to version {agy_manifest['version']}.")
PY

VALIDATOR="$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py"
if [ -f "$VALIDATOR" ]; then
  echo "==> Validating all skills with Codex quick_validate.py..."
  FAIL_COUNT=0
  for s in "$REPO_ROOT"/skills/*; do
    res=$(python3 "$VALIDATOR" "$s" 2>&1)
    if [ "$res" != "Skill is valid!" ]; then
      echo "FAILED $(basename "$s"): $res"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done
  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Validation failed on $FAIL_COUNT skill(s)." >&2
    exit 1
  fi
  echo "==> All skills passed Codex validation!"
fi
