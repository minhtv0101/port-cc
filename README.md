# port-cc

Portable Bash porter for syncing ClaudeKit globals into Codex and Gemini.

Main file: [`port-claudekit.sh`](./port-claudekit.sh)

## What It Does

One run syncs these sources:

- `$HOME/.claude/skills/*`
- `$HOME/.claude/workflows/*`
- `$HOME/.claude/CLAUDE.md`

Into these targets:

- `$HOME/.codex/skills/*`
- `$HOME/.codex/workflows/*`
- `$HOME/.codex/AGENTS.md`
- `$HOME/.gemini/antigravity/skills/*`
- `$HOME/.gemini/antigravity/global_workflows/*`
- `$HOME/.gemini/GEMINI.md`

## Behavior

- Only top-level directories containing `SKILL.md` are treated as skills.
- Files are synced in place: create if missing, overwrite if content changed.
- Existing destination-only directories are left alone.
- `node_modules` inside source skills are skipped.
- Invalid source `SKILL.md` files are normalized with valid YAML frontmatter.
- `AGENTS.md` and `GEMINI.md` are derived from `$HOME/.claude/CLAUDE.md`.
- Prompt files keep the original Claude structure as much as possible.
- Workflow references are rewritten to use `$HOME` paths, not hardcoded user paths.
- Unsupported Claude-only sections are omitted:
  - `## Hook Response Protocol`
  - `## Python Scripts (Skills)`

Managed generated files include:

```html
<!-- managed-by: port-claudekit -->
```

## Requirements

- `bash`
- standard Unix tools available on macOS/Linux: `find`, `awk`, `grep`, `cmp`, `cp`, `mktemp`
- source files must exist:
  - `$HOME/.claude/skills`
  - `$HOME/.claude/workflows`
  - `$HOME/.claude/CLAUDE.md`

## Usage

From the repo directory:

```bash
bash ./port-claudekit.sh --dry-run
bash ./port-claudekit.sh --yes
```

Or from anywhere:

```bash
bash /path/to/port-claudekit.sh --dry-run
bash /path/to/port-claudekit.sh --yes
```

Target-specific:

```bash
bash ./port-claudekit.sh --dry-run --codex-only
bash ./port-claudekit.sh --dry-run --gemini-only
```

## Exit Model

- `--dry-run` prints planned actions without writing
- `--yes` skips the interactive confirmation
- without `--yes`, real runs ask once before writing

## Result

The intended end state is simple:

```bash
bash port-claudekit.sh --yes
```

and the user gets globally usable Codex and Gemini skills/workflows without editing the script.
