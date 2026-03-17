# port-cc

Portable Bash porter for syncing ClaudeKit globals into Codex and Gemini, plus building a portable bundle for another machine.

Main files:

- [`port-claudekit.sh`](./port-claudekit.sh)
- [`port-claudekit-windows.sh`](./port-claudekit-windows.sh)

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

The Windows helper can also build a repo-local bundle at `./portable-home-bundle/` with these same scoped assets so another machine can install them without already having Claude.

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
bash ./port-claudekit-windows.sh --bundle --yes
```

Or from anywhere:

```bash
bash /path/to/port-claudekit.sh --dry-run
bash /path/to/port-claudekit.sh --yes
bash /path/to/port-claudekit-windows.sh --install --yes
```

Target-specific:

```bash
bash ./port-claudekit.sh --dry-run --codex-only
bash ./port-claudekit.sh --dry-run --gemini-only
```

Portable bundle flow:

```bash
# On this machine: snapshot only the same scoped assets the porter uses
bash ./port-claudekit-windows.sh --bundle --yes

# Copy ./portable-home-bundle/ to the Windows machine

# On Windows via Git Bash: install into $HOME/.claude, $HOME/.codex, and $HOME/.gemini
bash ./port-claudekit-windows.sh --install --yes
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

For the Windows handoff flow, the intended end state is:

```bash
bash port-claudekit-windows.sh --bundle --yes
```

then copy `./portable-home-bundle/` to the other machine and run:

```bash
bash port-claudekit-windows.sh --install --yes
```
