#!/usr/bin/env bash
# install.sh — statusline-suite unified install/verify/uninstall for three platforms
# Usage:
#   bash install.sh                    # install for all detected platforms
#   bash install.sh --platform claude  # Claude Code only
#   bash install.sh --platform cursor  # Cursor CLI only
#   bash install.sh --platform codex   # Codex only
#   bash install.sh --verify           # verify final state
#   bash install.sh --uninstall        # uninstall (restore pre-install backups)
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_SRC="$PLUGIN_DIR/scripts/statusline.py"
TEMPLATE_DIR="$PLUGIN_DIR/templates"

MARKER="# ==== statusline-suite"
CLAUDE_STATUSLINE_PY="$HOME/.claude/statusline.py"
CURSOR_STATUSLINE_PY="$HOME/.cursor/statusline.py"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CURSOR_CLI_CONFIG="$HOME/.cursor/cli-config.json"
CODEX_CONFIG="$HOME/.codex/config.toml"

installed=()
skipped=()

backup() {
  local f="$1"
  [ -f "$f" ] || return 0
  local bak="${f}.bak-statusline-suite"
  [ -f "$bak" ] || cp "$f" "$bak"   # never overwrite an existing backup -> idempotent
}

detect_platform() {
  case "$1" in
    claude) [ -d "$HOME/.claude" ] ;;
    cursor) [ -d "$HOME/.cursor" ] ;;
    codex)  [ -d "$HOME/.codex" ] ;;
    *) return 1 ;;
  esac
}

# ---------- Claude Code ----------
install_claude() {
  echo "==> Claude Code"
  command -v python3 >/dev/null || { skipped+=("claude: python3 missing"); return 0; }
  mkdir -p "$HOME/.claude"
  cp "$SCRIPT_SRC" "$CLAUDE_STATUSLINE_PY"
  chmod +x "$CLAUDE_STATUSLINE_PY"
  backup "$CLAUDE_SETTINGS"

  python3 - "$CLAUDE_SETTINGS" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path, errors="ignore") as f:
        data = json.load(f)
cfg = {"type": "command", "command": f"python3 {os.path.expanduser('~/.claude/statusline.py')}"}
if data.get("statusLine") == cfg:
    print("    statusLine already configured, skipping (idempotent)")
else:
    if "statusLine" in data:
        print("    overwriting existing non-plugin statusLine config")
    data["statusLine"] = cfg
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("    statusLine written")
PYEOF
  installed+=("claude")
}

# ---------- Cursor CLI ----------
install_cursor() {
  echo "==> Cursor CLI"
  command -v python3 >/dev/null || { skipped+=("cursor: python3 missing"); return 0; }
  mkdir -p "$HOME/.cursor"
  cp "$SCRIPT_SRC" "$CURSOR_STATUSLINE_PY"
  chmod +x "$CURSOR_STATUSLINE_PY"
  backup "$CURSOR_CLI_CONFIG"

  python3 - "$CURSOR_CLI_CONFIG" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path, errors="ignore") as f:
        data = json.load(f)
cfg = {"type": "command", "command": f"python3 {os.path.expanduser('~/.cursor/statusline.py')}"}
if data.get("statusLine") == cfg:
    print("    statusLine already configured, skipping (idempotent)")
else:
    if "statusLine" in data:
        print("    overwriting existing non-plugin statusLine config")
    data["statusLine"] = cfg
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("    statusLine written")
PYEOF
  installed+=("cursor")
}

# ---------- Codex ----------
install_codex() {
  echo "==> Codex CLI"
  mkdir -p "$HOME/.codex"
  backup "$CODEX_CONFIG"

  if [ -f "$CODEX_CONFIG" ] && rg -q "$MARKER" "$CODEX_CONFIG" 2>/dev/null; then
    echo "    [tui] block already present, skipping (idempotent)"
  else
    {
      echo ""
      cat "$TEMPLATE_DIR/codex-config.toml"
    } >> "$CODEX_CONFIG"
    echo "    [tui] block appended"
  fi
  installed+=("codex")
}

# ---------- Verify ----------
verify() {
  local fail=0
  echo "==> Verify final state"
  if [ -x "$CLAUDE_STATUSLINE_PY" ] && python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/.claude/settings.json'))); assert d['statusLine']['type']=='command'" 2>/dev/null; then
    echo "  [✓] claude: script executable + statusLine config present"
  else
    echo "  [x] claude: config missing"; fail=1
  fi
  if [ -x "$CURSOR_STATUSLINE_PY" ] && python3 -c "import json,os; d=json.load(open(os.path.expanduser('~/.cursor/cli-config.json'))); assert d['statusLine']['type']=='command'" 2>/dev/null; then
    echo "  [✓] cursor: script executable + statusLine config present"
  else
    echo "  [x] cursor: config missing"; fail=1
  fi
  if [ -f "$CODEX_CONFIG" ] && rg -q "$MARKER" "$CODEX_CONFIG" 2>/dev/null; then
    echo "  [✓] codex: [tui] block present"
  else
    echo "  [x] codex: config missing"; fail=1
  fi
  return $fail
}

# ---------- Uninstall ----------
uninstall() {
  echo "==> Uninstall"
  for f in "$CLAUDE_SETTINGS" "$CURSOR_CLI_CONFIG" "$CODEX_CONFIG"; do
    bak="${f}.bak-statusline-suite"
    if [ -f "$bak" ]; then
      cp "$bak" "$f"
      echo "  [✓] restored $f"
    fi
  done
  rm -f "$CLAUDE_STATUSLINE_PY" "$CURSOR_STATUSLINE_PY"
  # Strip the appended Codex block as a fallback (backup restore covers most cases)
  if [ -f "$CODEX_CONFIG" ] && rg -q "$MARKER" "$CODEX_CONFIG" 2>/dev/null; then
    python3 - "$CODEX_CONFIG" <<'PYEOF'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = re.sub(r"\n?# ==== statusline-suite.*?(?=\n\[|\Z)", "", text, flags=re.S)
open(path, "w").write(text)
PYEOF
    echo "  [✓] codex [tui] block removed"
  fi
  echo "Uninstall complete"
}

# ---------- main ----------
platform="all"
action="install"
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) platform="$2"; shift 2 ;;
    --verify) action="verify"; shift ;;
    --uninstall) action="uninstall"; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

case "$action" in
  verify) verify ;;
  uninstall) uninstall ;;
  install)
    [ "$platform" = "all" -o "$platform" = "claude" ] && detect_platform claude && install_claude || true
    [ "$platform" = "all" -o "$platform" = "cursor" ] && detect_platform cursor && install_cursor || true
    [ "$platform" = "all" -o "$platform" = "codex" ] && detect_platform codex && install_codex || true
    echo ""
    echo "Installed: ${installed[*]:-none}"
    verify || true
    ;;
esac