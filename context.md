# port-cc context

## Purpose

This repo exists for one job only:

- sync ClaudeKit global `skills`
- sync ClaudeKit global `workflows`
- derive Codex `AGENTS.md` from Claude `CLAUDE.md`
- derive Gemini `GEMINI.md` from Claude `CLAUDE.md`

## Source Of Truth

- `~/.claude/skills/`
- `~/.claude/workflows/`
- `~/.claude/CLAUDE.md`

## Target Model

Codex:

- `~/.codex/skills/*`
- `~/.codex/workflows/*`
- `~/.codex/AGENTS.md`

Gemini:

- `~/.gemini/antigravity/skills/*`
- `~/.gemini/antigravity/global_workflows/*`
- `~/.gemini/GEMINI.md`

Legacy `~/.antigravity` is not a target anymore.

## Script Contract

[`port-claudekit.sh`](/Users/mza/Project/port-cc/port-claudekit.sh):

- uses only `$HOME`-based source and target paths
- supports `--dry-run`, `--yes`, `--codex-only`, `--gemini-only`
- preserves existing destination structure
- updates file contents in place
- skips vendored `node_modules`
- normalizes invalid `SKILL.md`
- rewrites prompt file workflow paths using `${HOME}`, not hardcoded absolute paths

## Prompt File Rules

`AGENTS.md` and `GEMINI.md` should:

- stay structurally close to `CLAUDE.md`
- change only what is target-specific
- rewrite workflow paths
- rename self-references from `./CLAUDE.md` to `./AGENTS.md` or `./GEMINI.md`
- drop Claude-only sections that do not apply in the target runtime

## Current Status

Current repo state is aligned to the final portable model:

- script syncs global targets, not project-local prompt files
- README is written for operator handoff
- context is written for maintainers only

## Operator Goal

Another person should be able to clone or copy this repo anywhere and run:

```bash
bash port-claudekit.sh --yes
```

with no code edits needed.
