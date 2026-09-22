# ai-agent-toolkit

A toolkit for AI coding assistants: **auto-execute** (cross-platform auto-execution mode) + **statusline-suite** (cross-platform progress-bar statusline).

## auto-execute — Auto-Execute Mode

Make AI coding assistants (**Cursor / Codex CLI / Claude Code**) stop asking yes/no at every step: clarify all key decisions upfront in one round, decide autonomously mid-flight under "minimal intrusion, reversible", and show a live `[✓]/[→]/[ ]/[!]` progress checklist in every reply.

```bash
cd auto-execute
./install.sh              # auto-detect installed platforms and install all
./install.sh --cursor     # Cursor only
./install.sh --codex      # Codex CLI only
./install.sh --claude     # Claude Code only
./install.sh --project    # project-level install (run at repo root)
```

Platform config entry points and safety boundaries (operations that keep human confirmation) are documented in [auto-execute/README.md](auto-execute/README.md).

## Platform Comparison

| | **Cursor** | **Codex CLI** | **Claude Code** |
|------|-----------|---------------|-----------------|
| Automation mechanism | `permissions.json` global allow + agent approval mode | `approval_policy="never"` + `sandbox_mode="workspace-write"` | `permissions.defaultMode="acceptEdits"` |
| File edits | ✅ automatic | ✅ automatic | ✅ auto-accepted |
| Terminal commands | ✅ automatic (Run Everything mode) | ✅ automatic (workspace-scoped) | ⚠️ confirm once, similar commands allowed |
| Network / outside workspace | depends on approval mode | 🚫 sandboxed | per-permission confirmation |
| Behavior rules injected | User Rules + project `.cursor/rules/` | `~/.codex/AGENTS.md` | `~/.claude/CLAUDE.md` |
| Manual steps after install | ① paste User Rules ② pick approval mode | none | none |
| Autonomy level | ★★★☆ ~ ★★★★★ | ★★★★★ | ★★★☆ |
| Best for | daily dev with one approval gate | scripted/batch tasks, throughput first | production codebases, safety first |

TL;DR: full autonomy → **Codex**; balanced → **Cursor**; conservative → **Claude Code**.

## statusline-suite — Cross-platform progress-bar statusline

Model name / directory / git branch / **task progress bar** (Claude Code only) / context progress bar / platform-specific segments (MCP servers, vim mode, worktree, etc.).

| Platform | Mechanism | Config file |
|----------|-----------|-------------|
| Claude Code | `statusLine.command` (custom script, stdin JSON) | `~/.claude/settings.json` |
| Cursor CLI | `statusLine.command` (same mechanism, different payload) | `~/.cursor/cli-config.json` |
| Codex CLI | `tui.status_line` built-in items array (v0.128.0+) | `~/.codex/config.toml` |

Segment availability per platform (one self-adapting script, no per-platform config needed):

| Segment | Claude Code | Cursor CLI | Codex CLI |
|---------|:-----------:|:----------:|:---------:|
| Model name | ✅ | ✅ | ✅ built-in |
| Current directory | ✅ | ✅ | ✅ built-in |
| Context progress bar | ✅ dim `ctx 6%` text (demoted to a watermark reference) | ✅ straight from official payload, green→yellow→red | ✅ built-in `context_usage` |
| **Task progress bar** (estimated completion) | ✅ transcript todo list, `Tasks 2/5` + active task name | ❌ | ❌ |
| git branch + dirty flag | ✅ | ✅ | ❌ (branch only in terminal title) |
| MCP server list | ✅ | ❌ | ❌ |
| Lines added/removed (+n -n) | ✅ | ❌ | ❌ |
| (Thinking)/max/vim/worktree | ❌ | ✅ | ❌ |
| Implementation | custom Python script | same script, field-adaptive | official built-in items, no custom styling |

```bash
bash plugins/statusline-suite/scripts/install.sh            # all detected platforms (idempotent)
bash plugins/statusline-suite/scripts/install.sh --verify   # verify final state
bash plugins/statusline-suite/scripts/install.sh --uninstall # uninstall (restore backups)
```

## Demo

After install, open a **new session** and it works. Give the agent a small task: no more yes/no at every step — the reply starts with a progress checklist and runs to completion:

```text
[✓] Diagnose: statusline usage fields came back empty
[→] Fix: support both message.usage and usage field locations
[ ] Regression: run all three platform payloads
```

The statusline at the bottom refreshes live. The bar shows **task completion progress** (fills up when all tasks complete); context usage is demoted to a dim watermark:

```text
MiniMax-M3[1m] | my-project | git:( main* ) | MCP: apifox mysql dbhub | +3396 -363 lines | █████░░░░░░░ Tasks 2/5 40% | → Implement export Controller | ctx 38%
```

Codex CLI uses official built-in items, rendering a `model · cwd · context_usage · spinner` combination; Cursor CLI additionally shows `(Thinking)`, vim mode and worktree.

## Common conventions

- Every config change is **backed up first** (`*.bak.*` / `*.bak-statusline-suite`) then merged; user config is never overwritten
- All installers are idempotent; re-running produces the same result
- Uninstall simply restores backups

## License

MIT