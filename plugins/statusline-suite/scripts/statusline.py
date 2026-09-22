#!/usr/bin/env python3
"""statusline.py — unified statusline script for Claude Code / Cursor CLI.

Both platforms share the same statusLine mechanism (JSON payload via stdin),
but their payload fields differ. This single file auto-adapts by field
detection and serves both platforms:

  - Claude Code : ~/.claude/settings.json  -> statusLine.command
  - Cursor CLI  : ~/.cursor/cli-config.json -> statusLine.command

Field mapping (missing fields degrade gracefully):
  Model         claude: model.display_name          cursor: model.display_name / model.id
  Directory     workspace.current_dir / cwd
  git branch    local git query (same for both)
  Context       claude: transcript usage estimate (dim text)  cursor: context_window.used_percentage (bar)
  Task progress claude: latest TodoWrite in transcript -> [bar x/y] active task  cursor: N/A
  Extras        claude: MCP/lines  cursor: (Thinking)/max/vim/worktree
"""

import glob
import json
import os
import subprocess
import sys

DIM, GREEN, YELLOW, RED, MAGENTA, CYAN = "2", "32", "33", "31", "35", "36"
BAR_WIDTH = 12


def c(color: str, text: str) -> str:
    return f"\033[{color}m{text}\033[0m"


def bar(pct: float, color: str) -> str:
    pct = max(0.0, min(100.0, pct))
    filled = round(BAR_WIDTH * pct / 100)
    return c(color, "█" * filled) + c(DIM, "░" * (BAR_WIDTH - filled))


def pct_color(pct: float) -> str:
    return GREEN if pct < 50 else YELLOW if pct < 80 else RED


def load_json(path: str):
    try:
        with open(path, errors="ignore") as f:
            return json.load(f)
    except Exception:
        return None


def claude_session_stats(model_name: str, transcript_path: str = ""):
    """Scan the current session transcript in a single pass, collecting both the
    latest usage and the latest todo list.

    Todo lists have been stored in different shapes across Claude Code versions:
    attachment.content[] / toolUseResult.newTodos etc. Try all of them and keep
    the last one written.
    Returns (context_pct | None, tasks_done | None, tasks_total | None, active_task | None)
    """
    path = transcript_path if transcript_path and os.path.exists(transcript_path) else None
    if not path:
        newest = sorted(
            glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")),
            key=os.path.getmtime,
        )
        path = newest[-1] if newest else None
    if not path:
        return None, None, None, None
    usage = None
    todos = None
    try:
        with open(path, errors="ignore") as f:
            for line in f:
                if not any(k in line for k in ('"usage"', '"todos"', '"attachment"')):
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                u = (obj.get("message") or {}).get("usage") or obj.get("usage")
                if u:
                    usage = u
                att = obj.get("attachment")
                att_list = att.get("content") if isinstance(att, dict) else None
                for cand in (
                    att_list,
                    (obj.get("toolUseResult") or {}).get("newTodos"),
                    (obj.get("toolUseResult") or {}).get("oldTodos"),
                    (obj.get("toolUseResult") or {}).get("todos"),
                    obj.get("todos"),
                ):
                    if isinstance(cand, list) and cand and isinstance(cand[0], dict) and "status" in cand[0]:
                        todos = cand
    except OSError:
        pass

    # Context usage
    context_pct = None
    if usage:
        tokens = (usage.get("input_tokens") or 0) \
            + (usage.get("cache_read_input_tokens") or 0) \
            + (usage.get("cache_creation_input_tokens") or 0)
        window = 200_000
        if "[1m]" in model_name.lower() or os.environ.get("CLAUDE_CODE_AUTO_COMPACT_WINDOW") == "1000000":
            window = 1_000_000
        context_pct = tokens / window * 100

    # Task progress: done/total + first in-progress task name
    if not todos:
        return context_pct, None, None, None
    total = len(todos)
    done = sum(1 for t in todos if t.get("status") == "completed")
    active = next(
        (t.get("activeForm") or t.get("content") or t.get("subject") or ""
         for t in todos if t.get("status") == "in_progress"),
        None,
    )
    return context_pct, done, total, (active or None) and str(active)[:24]


def git_info(cwd: str):
    try:
        branch = subprocess.run(
            ["git", "-C", cwd, "branch", "--show-current"],
            capture_output=True, text=True, timeout=1.5,
        ).stdout.strip()
        dirty = subprocess.run(
            ["git", "-C", cwd, "status", "--porcelain"],
            capture_output=True, text=True, timeout=1.5,
        ).stdout.strip() != ""
        return branch or None, dirty
    except Exception:
        return None, False


def render(data: dict) -> str:
    payload = data or {}
    # Platform detection: transcript_path is Claude-only; newer Claude payloads also carry
    # context_window, so it can no longer be used as a Cursor marker (Claude would be
    # misdetected as Cursor and lose the task progress / MCP segments)
    claude_mode = "transcript_path" in payload
    cursor_mode = not claude_mode and "context_window" in payload

    cwd = (payload.get("workspace") or {}).get("current_dir") or payload.get("cwd") or os.getcwd()
    model = payload.get("model") or {}
    model_name = model.get("display_name") or model.get("id") or "agent"
    segs = [c(CYAN, model_name), c(DIM, os.path.basename(cwd))]

    if cursor_mode:
        # Cursor-only segments: thinking/max/vim/worktree
        if model.get("param_summary"):
            segs.append(c(DIM, model["param_summary"]))
        if model.get("max_mode"):
            segs.append(c(YELLOW, "max"))
        if (payload.get("vim") or {}).get("mode"):
            segs.append(c("34", payload["vim"]["mode"]))
        if (payload.get("worktree") or {}).get("name"):
            segs.append(c(DIM, f"wt: {payload['worktree']['name']}"))
    else:
        # Claude-only segments: MCP / line stats
        settings = load_json(os.path.expanduser("~/.claude/settings.json")) or {}
        mcp = list((settings.get("mcpServers") or {}).keys())
        if mcp:
            segs.append(c(DIM, "MCP: ") + c("34", " ".join(mcp)))
        added = (payload.get("cost") or {}).get("total_lines_added") or 0
        removed = (payload.get("cost") or {}).get("total_lines_removed") or 0
        if added or removed:
            segs.append(c(GREEN, f"+{added}") + " " + c(RED, f"-{removed}") + c(DIM, " lines"))

    branch, dirty = git_info(cwd)
    if branch:
        segs.append(c("36", f"git:( {branch}{'*' if dirty else ''} )"))

    # Claude: task progress bar (from latest TodoWrite) + context display; Cursor: context bar (from payload)
    if cursor_mode:
        pct = (payload.get("context_window") or {}).get("used_percentage")
        if pct is not None:
            pct = float(pct)
            segs.append(f"{bar(pct, pct_color(pct))} {c(pct_color(pct), f'{pct:.0f}%')}")
    else:
        ctx, done, total, active = claude_session_stats(model_name, payload.get("transcript_path")) \
            if payload.get("transcript_path") else (None, None, None, None)
        # Prefer the official context data from the payload; fall back to transcript estimation
        official = ((payload.get("context_window") or {}).get("used_percentage"))
        if official is not None:
            ctx = float(official)
        if done is not None:
            tpct = done / total * 100
            segs.append(f"{bar(tpct, GREEN)} {c(GREEN, f'Tasks {done}/{total} {tpct:.0f}%')}")
            if active:
                segs.append(c(DIM, f"→ {active}"))
        if ctx is not None:
            segs.append(c(DIM, f"ctx {ctx:.0f}%"))

    return " | ".join(segs)


if __name__ == "__main__":
    try:
        print(render(json.load(sys.stdin)))
    except Exception:
        # Degrade to a placeholder on bad input so the statusline never breaks
        print(c(DIM, "statusline error"))