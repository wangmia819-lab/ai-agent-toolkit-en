---
name: statusline-suite
description: >
  Install/verify/uninstall a unified statusline for Claude Code, Codex CLI and Cursor CLI.
  Use when the user mentions statusline, status bar, progress-bar statusline or context usage bar.
---

# Statusline Suite

A unified statusline installer for three platforms.

## Platform capability matrix

| Platform | Mechanism | Config file | Result |
|----------|-----------|-------------|--------|
| Claude Code | `statusLine.command` (stdin JSON → single-line ANSI stdout) | `~/.claude/settings.json` | Full: model/dir/git/**task progress bar (estimated)**/active task/ctx/MCP/lines |
| Cursor CLI | `statusLine.command` (same mechanism, different payload) | `~/.cursor/cli-config.json` | model/dir/git/context bar/vim/worktree |
| Codex CLI | `tui.status_line` built-in items array (no custom command support) | `~/.codex/config.toml` | model/cwd/context_usage/spinner |

## Task progress bar (Claude Code only)

The statusline bar shows **task completion progress**, not context usage:

- Data source: the latest TodoWrite todo list in the current session transcript (`transcript_path`)
- Render: `█████░░░░░░░ Tasks 2/5 40% | → active task name`; the bar fills up when all tasks complete
- Context usage degrades to a dim `ctx 6%` text, kept only as a watermark reference
- Todo lists have been stored in different shapes across Claude Code versions (`attachment.content[]` / `toolUseResult.newTodos` etc.); the script supports all of them and keeps the last one written

## Install

```bash
bash <plugin-dir>/scripts/install.sh            # install for all detected platforms
bash <plugin-dir>/scripts/install.sh --platform claude   # Claude Code only
bash <plugin-dir>/scripts/install.sh --platform cursor   # Cursor CLI only
bash <plugin-dir>/scripts/install.sh --platform codex    # Codex only
bash <plugin-dir>/scripts/install.sh --uninstall         # uninstall (restore backups)
```

## Acceptance criteria

1. `install.sh` is idempotent: re-running produces the same result, no duplicated config blocks
2. Every config file is backed up as `<file>.bak-statusline-suite` before modification
3. Final-state verification: `install.sh --verify` asserts per platform that config exists and the script is executable
4. The script degrades to `statusline error` on bad input instead of raising

## Platform payload differences

- Claude Code payload: `model.display_name` / `workspace.current_dir` / `transcript_path` / `cost.total_lines_added` (task progress does not come from the payload; the script scans TodoWrite records in the transcript itself)
- Cursor payload: additionally `context_window.used_percentage` / `vim.mode` / `worktree.name`
- Codex: only built-in items may be selected: `["model", "approval", "context_usage", "session_id", "sandbox", "cwd", "spinner"]`