# port-cc context

## Purpose

This repo exists for one job only:

- sync ClaudeKit global `skills`
- sync ClaudeKit global `workflows`
- derive Codex `AGENTS.md` from Claude `CLAUDE.md`
- derive Gemini `GEMINI.md` from Claude `CLAUDE.md`
- snapshot the same scoped payload into a repo-local bundle for another machine

## Source Of Truth

- `$HOME/.claude/skills/`
- `$HOME/.claude/workflows/`
- `$HOME/.claude/CLAUDE.md`

## Target Model

Codex:

- `$HOME/.codex/skills/*`
- `$HOME/.codex/workflows/*`
- `$HOME/.codex/AGENTS.md`

Gemini:

- `$HOME/.gemini/antigravity/skills/*`
- `$HOME/.gemini/antigravity/global_workflows/*`
- `$HOME/.gemini/GEMINI.md`

Legacy `$HOME/.antigravity` is not a target anymore.

Portable bundle:

- `./portable-home-bundle/.claude/*`
- `./portable-home-bundle/.codex/*`
- `./portable-home-bundle/.gemini/*`

## Script Contract

[`port-claudekit.sh`](/Users/mza/Project/port-cc/port-claudekit.sh):

- uses only `$HOME`-based source and target paths
- supports `--dry-run`, `--yes`, `--codex-only`, `--gemini-only`
- preserves existing destination structure
- updates file contents in place
- skips vendored `node_modules`
- normalizes invalid `SKILL.md`
- rewrites prompt file workflow paths using `$HOME`, not hardcoded absolute paths

[`port-claudekit-windows.sh`](/Users/mza/Project/port-cc/port-claudekit-windows.sh):

- builds `./portable-home-bundle/` from the current machine
- installs that bundle into `$HOME` on another machine
- keeps the same scope rules as `port-claudekit.sh`
- includes `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md`

## Prompt File Rules

`AGENTS.md` and `GEMINI.md` should:

- stay structurally close to `CLAUDE.md`
- change only what is target-specific
- rewrite workflow paths
- rename self-references from `./CLAUDE.md` to `./AGENTS.md` or `./GEMINI.md`
- drop Claude-only sections that do not apply in the target runtime

Portable bundle should:

- include only top-level skill folders containing `SKILL.md`
- include only top-level workflow markdown files
- include `.claude/CLAUDE.md`, `.codex/AGENTS.md`, `.gemini/GEMINI.md`
- stay installable into `$HOME` without needing Claude preinstalled on the target machine

## Current Status

Current repo state is aligned to the final portable model:

- script syncs global targets, not project-local prompt files
- windows helper can snapshot a scoped install bundle into the repo
- README is written for operator handoff
- context is written for maintainers only

## Operator Goal

Another person should be able to clone or copy this repo anywhere and run:

```bash
bash port-claudekit.sh --yes
```

with no code edits needed.
