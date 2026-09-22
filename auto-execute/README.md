# auto-execute

A cross-platform "Auto-Execute Mode" kit for AI coding assistants (**Cursor / Codex CLI / Claude Code**): stop asking yes/no at every step, clarify upfront, and show a live progress checklist in every reply.

## What it does per platform

| Platform | Auto-execution config | Behavior rules (upfront clarification + progress checklist) |
|----------|----------------------|-------------------------------------------------------------|
| Cursor | `~/.cursor/permissions.json` + choose Run Mode in UI | User Rules (paste into UI) + project-level `.cursor/rules/` |
| Codex | `~/.codex/config.toml`: `approval_policy="never"` + `sandbox_mode="workspace-write"` + workspace network | `~/.codex/AGENTS.md` |
| Claude Code | `~/.claude/settings.json`: `permissions.defaultMode="acceptEdits"` | `~/.claude/CLAUDE.md` |

## Install

```bash
./install.sh              # auto-detect installed platforms and install all
./install.sh --cursor     # Cursor only
./install.sh --codex      # Codex only
./install.sh --claude     # Claude Code only
./install.sh --project    # project-level install (run at repo root): Cursor project rules + AGENTS.md + CLAUDE.md
```

Safety policy: every existing config is **backed up first** (`*.bak.<timestamp>`) then merged, never overwriting user config; idempotent on re-run.

## Remaining manual steps per platform

- **Cursor**: 1) paste clipboard content into `Settings -> Customize -> Rules -> User Rules` (script copies it for you) 2) `Settings -> Agents -> Approvals & Execution` choose **Auto-review** (recommended) or **Run Everything**
- **Codex**: none. Config files take effect directly
- **Claude Code**: none. `acceptEdits` is driven by settings; for fully zero prompts use `claude --dangerously-skip-permissions` (isolated environments only — `bypassPermissions` inside settings.json has no effect, an official limitation)

## Verify

Take effect in **new sessions**. Verification: give a small task; if the reply starts with a `[✓]`/`[→]`/`[ ]` progress checklist and no more step-by-step "continue?" prompts, the setup works.

## File structure

```
auto-execute/
├── install.sh                      # one-shot installer (multi-platform, idempotent, auto-backup)
├── templates/
│   ├── behavior-rules.md           # shared behavior rules (all three platforms)
│   ├── auto-execution.mdc          # Cursor project-level rule (with frontmatter)
│   ├── user-rules.txt              # Cursor User Rules text
│   ├── permissions.global.json     # Cursor global permissions
│   ├── permissions.project.json    # Cursor project-level permissions
│   ├── codex-config-top.toml       # Codex TOML top-level keys (must precede sections)
│   └── codex-config-section.toml   # Codex TOML sandbox section
└── README.md
```

## Behavior rules in a nutshell

1. **Just do it**: decompose, execute, verify autonomously; no step-by-step consent
2. **Upfront clarification**: one round of questions covering impact scope / trade-offs / acceptance criteria
3. **No mid-flight interruptions**: unconfirmed forks are decided autonomously under "minimal intrusion, reversible", explained afterwards
4. **Exceptions**: only irreversible operations (production release / database drop / force-push to shared branches) interrupt for confirmation
5. **Progress checklist**: any task that uses tools must carry a `[✓]/[→]/[ ]/[!]` progress checklist at the start of every reply

## Safety boundaries

The following always require human confirmation on every platform:

- Production deploy/release
- Deleting data outside the workspace, force-pushing shared branches
- SQL DDL/DML (blocked by default in project-level config)

## Uninstall

```bash
rm ~/.cursor/permissions.json
# Codex: edit ~/.codex/config.toml, remove the "==== auto-execute" marker block; remove the matching section in ~/.codex/AGENTS.md
# Claude: edit ~/.claude/settings.json, remove permissions.defaultMode; remove the matching section in ~/.claude/CLAUDE.md
# or simply restore the *.bak.<timestamp> backups
```