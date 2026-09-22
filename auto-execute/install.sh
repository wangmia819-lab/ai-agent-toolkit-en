#!/usr/bin/env bash
# ============================================================
# auto-execute one-shot installer for three platforms (Cursor / Codex / Claude Code)
#
# Usage:
#   ./install.sh                    # detect installed platforms and install all
#   ./install.sh --cursor           # Cursor only
#   ./install.sh --codex            # Codex CLI only
#   ./install.sh --claude           # Claude Code only
#   ./install.sh --project          # project-level install (run at repo root; Cursor project rules only)
#
# Safety: every existing config is backed up before merging; user config is never overwritten
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="${SCRIPT_DIR}/templates"
TS="$(date +%Y%m%d%H%M%S)"
TARGETS=()

for arg in "$@"; do
  case "$arg" in
    --cursor) TARGETS+=("cursor") ;;
    --codex)  TARGETS+=("codex") ;;
    --claude) TARGETS+=("claude") ;;
    --project) TARGETS+=("project") ;;
    -h|--help)
      grep '^#' "$0" | head -14 | sed 's/^# \{0,2\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg (use --help for usage)"; exit 1 ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  # auto-detect
  [[ -d "$HOME/.cursor" ]]          && TARGETS+=("cursor")
  [[ -d "$HOME/.codex" ]]           && TARGETS+=("codex")
  command -v claude >/dev/null 2>&1 && TARGETS+=("claude")
  [[ ${#TARGETS[@]} -eq 0 ]] && { echo "No Cursor/Codex/Claude platform detected; specify with --cursor/--codex/--claude"; exit 1; }
  echo "Detected platforms: ${TARGETS[*]}"
fi

json_merge() {
  # json_merge <target.json> <patch.json>  deep merge, patch wins
  python3 - "$1" "$2" << 'PYEOF'
import json, sys
def deep_merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict):
            deep_merge(a[k], v)
        else:
            a[k] = v
    return a
target, patch = sys.argv[1], sys.argv[2]
try:
    base = json.load(open(target))
except Exception:
    base = {}
merged = deep_merge(base, json.load(open(patch)))
json.dump(merged, open(target, 'w'), indent=2, ensure_ascii=False)
print(f"    merged into: {target}")
PYEOF
}

json_ok() { python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" 2>/dev/null; }

backup() { [[ -f "$1" ]] && cp "$1" "$1.bak.$TS" && echo "    backed up: $1.bak.$TS"; return 0; }

append_if_missing() {
  # append_if_missing <target file> <marker> <source file>
  local dst="$1" mark="$2" src="$3"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]] && grep -qF "$mark" "$dst"; then
    echo "    already present, skipping: $dst"
    return 0
  fi
  backup "$dst"
  { echo ""; echo "# ==== auto-execute ($TS) ===="; cat "$src"; } >> "$dst"
  echo "    appended: $dst"
}

# ---------- Cursor ----------
install_cursor() {
  echo "==> [Cursor] global execution permissions"
  mkdir -p "$HOME/.cursor"
  local dst="$HOME/.cursor/permissions.json"
  backup "$dst"
  cp "$TPL/permissions.global.json" "$dst"
  json_ok "$dst" && echo "    written: $dst"

  echo "==> [Cursor] User Rules (copied to clipboard, paste manually)"
  if command -v pbcopy >/dev/null 2>&1; then
    cat "$TPL/user-rules.txt" | pbcopy
    echo "    copied to clipboard -> paste into Cursor Settings -> Customize -> Rules -> User Rules and save"
  else
    echo "    manually paste $TPL/user-rules.txt into Cursor User Rules"
  fi

  echo "==> [Cursor] execution mode (manual only): Settings -> Agents -> Approvals & Execution"
  echo "    Run Everything = zero prompts / Auto-review = review on high-risk ops (recommended)"
}

# ---------- Codex ----------
install_codex() {
  echo "==> [Codex] approval_policy + sandbox config"
  local dst="$HOME/.codex/config.toml"
  mkdir -p "$HOME/.codex"
  # TOML top-level keys must precede any [section]: insert at file head; section block appended at tail
  if [[ -f "$dst" ]] && grep -qF "approval_policy" "$dst"; then
    echo "    already present, skipping: $dst"
  else
    backup "$dst"
    local tmp="/tmp/auto-exec-codex.$TS.toml"
    { echo "# ==== auto-execute ($TS) ===="; cat "$TPL/codex-config-top.toml"; echo ""; cat "$dst"; echo ""; echo "# ==== auto-execute sandbox ($TS) ===="; cat "$TPL/codex-config-section.toml"; } > "$tmp"
    mv "$tmp" "$dst"
    echo "    merged into: $dst"
  fi

  echo "==> [Codex] global behavior rules"
  append_if_missing "$HOME/.codex/AGENTS.md" "Auto-Execute Mode" "$TPL/behavior-rules.md"
}

# ---------- Claude Code ----------
install_claude() {
  echo "==> [Claude] permissions.defaultMode = acceptEdits"
  local dst="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"
  local patch="/tmp/auto-execute-claude-patch.$TS.json"
  echo '{"permissions":{"defaultMode":"acceptEdits"}}' > "$patch"
  backup "$dst"
  json_merge "$dst" "$patch"
  rm -f "$patch"
  json_ok "$dst" || { echo "    warning: merged JSON failed validation; backup kept at $dst.bak.$TS"; return 1; }

  echo "==> [Claude] global behavior rules (CLAUDE.md)"
  append_if_missing "$HOME/.claude/CLAUDE.md" "Auto-Execute Mode" "$TPL/behavior-rules.md"

  echo "==> [Claude] note: bypassPermissions in settings.json has no effect (official limitation);"
  echo "    for temporary full access use: claude --dangerously-skip-permissions (isolated environments only)"
}

# ---------- Project-level (Cursor project rules) ----------
install_project() {
  local root="${PWD}"
  echo "==> [project] $root"
  mkdir -p "$root/.cursor/rules"
  cp "$TPL/permissions.project.json" "$root/.cursor/permissions.json"
  json_ok "$root/.cursor/permissions.json" && echo "    written: $root/.cursor/permissions.json"
  cp "$TPL/auto-execution.mdc" "$root/.cursor/rules/auto-execution.mdc"
  echo "    written: $root/.cursor/rules/auto-execution.mdc"
  # project-level memory files for other platforms
  append_if_missing "$root/AGENTS.md"  "Auto-Execute Mode" "$TPL/behavior-rules.md"
  append_if_missing "$root/CLAUDE.md"  "Auto-Execute Mode" "$TPL/behavior-rules.md"
  echo "Project-level install complete; takes effect in new sessions."
}

for t in "${TARGETS[@]}"; do
  case "$t" in
    cursor)  install_cursor ;;
    codex)   install_codex ;;
    claude)  install_claude ;;
    project) install_project ;;
  esac
  echo ""
done

echo "All done. Takes effect in new sessions on each platform."
echo "Verify: give the assistant a small task; a [✓]/[→]/[ ] progress checklist at the start of its reply means success."