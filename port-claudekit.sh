#!/usr/bin/env bash
# ============================================================================
# port-claudekit.sh
# Sync selected Claude skills/workflows for Codex and Gemini.
#
# Scope:
# - Port real skills only (top-level folders containing SKILL.md)
# - Port workflows from ~/.claude/workflows
# - Exclude vendored node_modules trees from copied skills
# - Do not prune existing destination-only directories automatically
# - Generate global AGENTS.md for Codex and global GEMINI.md for Gemini
# - Preserve directory structure and update file content in place
# ============================================================================

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
MANAGED_PREFIX="port-claudekit"

DRY_RUN=false
ASSUME_YES=false
PORT_CODEX=true
PORT_GEMINI=true

SRC_SKILLS="$HOME/.claude/skills"
SRC_WORKFLOWS="$HOME/.claude/workflows"
SRC_CLAUDE="$HOME/.claude/CLAUDE.md"

CODEX_SKILLS="$HOME/.codex/skills"
CODEX_WORKFLOWS="$HOME/.codex/workflows"
CODEX_WORKFLOWS_REF='${HOME}/.codex/workflows'
CODEX_PROMPT="$HOME/.codex/AGENTS.md"
GEMINI_ROOT="$HOME/.gemini"
GEMINI_SKILLS="$HOME/.gemini/antigravity/skills"
GEMINI_WORKFLOWS="$HOME/.gemini/antigravity/global_workflows"
GEMINI_WORKFLOWS_REF='${HOME}/.gemini/antigravity/global_workflows'
GEMINI_PROMPT="$HOME/.gemini/GEMINI.md"

TMP_FILES=()
TMP_DIRS=()
PLANNED_DIR_ROOT=''

ACTION_COUNT=0
MKDIR_COUNT=0
COPY_COUNT=0
UPDATE_FILE_COUNT=0
GENERATED_CREATE_COUNT=0
GENERATED_UPDATE_COUNT=0
SKIP_UNCHANGED_COUNT=0
WARNING_COUNT=0

if [ -t 1 ]; then
  RED=$(printf '\033[0;31m')
  GRN=$(printf '\033[0;32m')
  YLW=$(printf '\033[1;33m')
  BLU=$(printf '\033[0;34m')
  BOLD=$(printf '\033[1m')
  NC=$(printf '\033[0m')
else
  RED=''
  GRN=''
  YLW=''
  BLU=''
  BOLD=''
  NC=''
fi

cleanup() {
  local tmp
  for tmp in "${TMP_FILES[@]:-}"; do
    if [ -n "${tmp:-}" ] && [ -e "$tmp" ]; then
      rm -f "$tmp" || true
    fi
  done
  for tmp in "${TMP_DIRS[@]:-}"; do
    if [ -n "${tmp:-}" ] && [ -d "$tmp" ]; then
      rm -rf "$tmp" || true
    fi
  done
  return 0
}
trap cleanup EXIT

new_temp_file() {
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/port-claudekit.XXXXXX")
  TMP_FILES+=("$tmp")
  printf '%s\n' "$tmp"
}

new_temp_dir() {
  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/port-claudekit-dir.XXXXXX")
  TMP_DIRS+=("$tmp")
  printf '%s\n' "$tmp"
}

display_path() {
  local path="$1"
  printf '%s\n' "${path/#$HOME/~}"
}

mode_label() {
  if $DRY_RUN; then
    printf 'DRY'
  else
    printf 'RUN'
  fi
}

die() {
  printf '%sERROR%s %s\n' "$RED" "$NC" "$*" >&2
  exit 1
}

section() {
  printf '\n%s%s%s\n' "$BOLD$BLU" "$*" "$NC"
}

ok() {
  printf '%sOK%s    %s\n' "$GRN" "$NC" "$*"
}

warn() {
  WARNING_COUNT=$((WARNING_COUNT + 1))
  printf '%sWARN%s  %s\n' "$YLW" "$NC" "$*"
}

action() {
  local kind="$1"
  shift
  ACTION_COUNT=$((ACTION_COUNT + 1))
  case "$kind" in
    mkdir) MKDIR_COUNT=$((MKDIR_COUNT + 1)) ;;
    copy-new) COPY_COUNT=$((COPY_COUNT + 1)) ;;
    update-file) UPDATE_FILE_COUNT=$((UPDATE_FILE_COUNT + 1)) ;;
    create-generated-file) GENERATED_CREATE_COUNT=$((GENERATED_CREATE_COUNT + 1)) ;;
    update-generated-file) GENERATED_UPDATE_COUNT=$((GENERATED_UPDATE_COUNT + 1)) ;;
    skip-unchanged) SKIP_UNCHANGED_COUNT=$((SKIP_UNCHANGED_COUNT + 1)) ;;
  esac
  printf '  [%s] %-20s %s\n' "$(mode_label)" "$kind" "$*"
}

usage() {
  cat <<EOF
Usage: bash $SCRIPT_NAME [options]

Options:
  --dry-run              Print planned actions without writing
  --yes                  Skip confirmation prompt for real runs
  --codex-only           Port only Codex assets
  --gemini-only          Port only Gemini assets
  --help                 Show this help
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        ;;
      --yes)
        ASSUME_YES=true
        ;;
      --codex-only)
        PORT_CODEX=true
        PORT_GEMINI=false
        ;;
      --gemini-only)
        PORT_CODEX=false
        PORT_GEMINI=true
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

print_banner() {
  printf '\n%sClaudeKit skills + workflows porter%s\n' "$BOLD" "$NC"
  printf '  source skills:     %s\n' "$(display_path "$SRC_SKILLS")"
  printf '  source workflows:  %s\n' "$(display_path "$SRC_WORKFLOWS")"
  $PORT_CODEX && printf '  codex skills:      %s\n' "$(display_path "$CODEX_SKILLS")"
  $PORT_CODEX && printf '  codex workflows:   %s\n' "$(display_path "$CODEX_WORKFLOWS")"
  $PORT_CODEX && printf '  codex prompt:      %s\n' "$(display_path "$CODEX_PROMPT")"
  $PORT_GEMINI && printf '  gemini skills:     %s\n' "$(display_path "$GEMINI_SKILLS")"
  $PORT_GEMINI && printf '  gemini workflows:  %s\n' "$(display_path "$GEMINI_WORKFLOWS")"
  $PORT_GEMINI && printf '  gemini prompt:     %s\n' "$(display_path "$GEMINI_PROMPT")"
  if $DRY_RUN; then
    printf '  mode:              %sDRY RUN%s\n' "$YLW$BOLD" "$NC"
  else
    printf '  mode:              %sREAL RUN%s\n' "$GRN$BOLD" "$NC"
  fi
}

count_skill_roots() {
  local count=0
  local dir
  if [ ! -d "$SRC_SKILLS" ]; then
    printf '0\n'
    return
  fi
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    [ -f "$dir/SKILL.md" ] || continue
    count=$((count + 1))
  done < <(find "$SRC_SKILLS" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
  printf '%s\n' "$count"
}

count_workflows() {
  local count=0
  local file
  if [ ! -d "$SRC_WORKFLOWS" ]; then
    printf '0\n'
    return
  fi
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    count=$((count + 1))
  done < <(find "$SRC_WORKFLOWS" -mindepth 1 -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
  printf '%s\n' "$count"
}

preflight() {
  section "0. Preflight"
  [ -d "$SRC_SKILLS" ] || die "Source skills not found at $(display_path "$SRC_SKILLS")"
  [ -d "$SRC_WORKFLOWS" ] || die "Source workflows not found at $(display_path "$SRC_WORKFLOWS")"
  [ -f "$SRC_CLAUDE" ] || die "Source CLAUDE.md not found at $(display_path "$SRC_CLAUDE")"
  ok "Source roots exist"
  printf '  %-22s %s\n' "skills/" "$(count_skill_roots) folders"
  printf '  %-22s %s\n' "workflows/" "$(count_workflows) markdown files"
  printf '  %-22s %s\n' "excluded" "node_modules trees inside skills"
}

confirm_real_run() {
  if $DRY_RUN || $ASSUME_YES; then
    return
  fi
  printf '\nProceed with in-place sync? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) die "Cancelled by user" ;;
  esac
}

ensure_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    return
  fi
  if $DRY_RUN; then
    if [ -z "$PLANNED_DIR_ROOT" ]; then
      PLANNED_DIR_ROOT=$(new_temp_dir)
    fi
    if [ -d "$PLANNED_DIR_ROOT$dir" ]; then
      return
    fi
  fi
  action "mkdir" "$(display_path "$dir")"
  if $DRY_RUN; then
    mkdir -p "$PLANNED_DIR_ROOT$dir"
  else
    mkdir -p "$dir"
  fi
}

sync_file() {
  local src_file="$1"
  local dst_file="$2"
  ensure_dir "$(dirname "$dst_file")"
  if [ ! -e "$dst_file" ] && [ ! -L "$dst_file" ]; then
    action "copy-new" "$(display_path "$src_file") -> $(display_path "$dst_file")"
    if ! $DRY_RUN; then
      cp -pP "$src_file" "$dst_file"
    fi
    return
  fi
  if cmp -s "$src_file" "$dst_file" 2>/dev/null; then
    action "skip-unchanged" "$(display_path "$dst_file")"
    return
  fi
  action "update-file" "$(display_path "$dst_file")"
  if ! $DRY_RUN; then
    cp -pP "$src_file" "$dst_file"
  fi
}

generated_markdown_marker() {
  printf '<!-- managed-by: %s -->\n' "$MANAGED_PREFIX"
}

has_generated_markdown_marker() {
  local target="$1"
  [ -f "$target" ] || return 1
  grep -Fq "$(generated_markdown_marker)" "$target"
}

write_generated_markdown() {
  local tmp_file="$1"
  local dst_file="$2"

  ensure_dir "$(dirname "$dst_file")"
  if [ ! -e "$dst_file" ]; then
    action "create-generated-file" "$(display_path "$dst_file")"
    if ! $DRY_RUN; then
      cp "$tmp_file" "$dst_file"
    fi
    return
  fi

  if cmp -s "$tmp_file" "$dst_file" 2>/dev/null; then
    action "skip-unchanged" "$(display_path "$dst_file")"
    return
  fi

  if has_generated_markdown_marker "$dst_file"; then
    action "update-generated-file" "$(display_path "$dst_file")"
    if ! $DRY_RUN; then
      rm -f "$dst_file"
      cp "$tmp_file" "$dst_file"
    fi
    return
  fi

  action "update-generated-file" "$(display_path "$dst_file")"
  if ! $DRY_RUN; then
    cp "$tmp_file" "$dst_file"
  fi
}

has_frontmatter() {
  local src_file="$1"
  head -n 1 "$src_file" | grep -qx -- '---'
}

first_heading_text() {
  local src_file="$1"
  awk '
    /^# / {
      sub(/^# /, "", $0)
      print
      exit
    }
  ' "$src_file"
}

yaml_quote() {
  local value="$1"
  value=${value//$'\r'/}
  value=${value//$'\n'/ }
  value=${value//\'/\'\'}
  printf "'%s'\n" "$value"
}

build_skill_wrapper() {
  local src_file="$1"
  local skill_name="$2"
  local out="$3"
  local description

  if has_frontmatter "$src_file"; then
    cat "$src_file" > "$out"
    return
  fi

  description=$(first_heading_text "$src_file")
  if [ -z "$description" ]; then
    description="$skill_name"
  fi

  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$skill_name"
    printf 'description: %s\n' "$(yaml_quote "$description")"
    printf '%s\n\n' '---'
    printf '%s\n\n' "$(generated_markdown_marker)"
    cat "$src_file"
  } > "$out"
}

copy_tree_sync_except_skill() {
  local src_root="$1"
  local dst_root="$2"
  local dir
  local file

  ensure_dir "$dst_root"

  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    if [ "$dir" = "$src_root" ]; then
      continue
    fi
    ensure_dir "$dst_root/${dir#$src_root/}"
  done < <(find "$src_root" \( -type d -name node_modules -prune \) -o -type d -print | LC_ALL=C sort)

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [ "$file" = "$src_root/SKILL.md" ]; then
      continue
    fi
    sync_file "$file" "$dst_root/${file#$src_root/}"
  done < <(find "$src_root" \( -type d -name node_modules -prune \) -o \( -type f -o -type l \) -print | LC_ALL=C sort)
}

port_skills_to_target() {
  local dst_root="$1"
  local skill_dir
  local skill_name
  local tmp_wrapper

  ensure_dir "$dst_root"
  while IFS= read -r skill_dir; do
    [ -n "$skill_dir" ] || continue
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill_name=$(basename "$skill_dir")
    copy_tree_sync_except_skill "$skill_dir" "$dst_root/$skill_name"
    tmp_wrapper=$(new_temp_file)
    build_skill_wrapper "$skill_dir/SKILL.md" "$skill_name" "$tmp_wrapper"
    write_generated_markdown "$tmp_wrapper" "$dst_root/$skill_name/SKILL.md"
  done < <(find "$SRC_SKILLS" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
}

port_workflows_to_target() {
  local dst_root="$1"
  local src_file

  ensure_dir "$dst_root"
  while IFS= read -r src_file; do
    [ -n "$src_file" ] || continue
    sync_file "$src_file" "$dst_root/$(basename "$src_file")"
  done < <(find "$SRC_WORKFLOWS" -mindepth 1 -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
}

build_global_prompt() {
  local title="$1"
  local product_name="$2"
  local workflows_ref="$3"
  local out="$4"

  {
    printf '%s\n' "$(generated_markdown_marker)"
    awk \
      -v title="$title" \
      -v product_name="$product_name" \
      -v workflows_ref="$workflows_ref" \
      '
        function rewrite(line) {
          gsub(/^# CLAUDE\.md$/, "# " title, line)
          if (line ~ /^This file provides guidance to Claude Code \(claude\.ai\/code\) when working.*repository\.$/) {
            line = "This file provides guidance to " product_name " when working with code in this repository."
          }
          gsub(/\$HOME\/\.claude\/rules\/primary-workflow\.md/, workflows_ref "/primary-workflow.md", line)
          gsub(/\$HOME\/\.claude\/rules\/development-rules\.md/, workflows_ref "/development-rules.md", line)
          gsub(/\$HOME\/\.claude\/rules\/orchestration-protocol\.md/, workflows_ref "/orchestration-protocol.md", line)
          gsub(/\$HOME\/\.claude\/rules\/documentation-management\.md/, workflows_ref "/documentation-management.md", line)
          gsub(/\$HOME\/\.claude\/rules\/\*/, workflows_ref "/*", line)
          gsub(/\.\/CLAUDE\.md/, "./" title, line)
          return line
        }

        /^## Hook Response Protocol$/ { skip_section = 1; next }
        /^## Python Scripts \(Skills\)$/ { skip_section = 1; next }
        /^## / && skip_section { skip_section = 0 }

        skip_section { next }

        { print rewrite($0) }
      ' "$SRC_CLAUDE"
    printf '\n'
  } > "$out"
}

port_global_prompt_files() {
  local tmp_file

  if $PORT_CODEX; then
    tmp_file=$(new_temp_file)
    build_global_prompt "AGENTS.md" "Codex" "$CODEX_WORKFLOWS_REF" "$tmp_file"
    write_generated_markdown "$tmp_file" "$CODEX_PROMPT"
  fi

  if $PORT_GEMINI; then
    tmp_file=$(new_temp_file)
    build_global_prompt "GEMINI.md" "Gemini" "$GEMINI_WORKFLOWS_REF" "$tmp_file"
    write_generated_markdown "$tmp_file" "$GEMINI_PROMPT"
  fi
}

port_codex() {
  section "1. Port to Codex"
  port_skills_to_target "$CODEX_SKILLS"
  port_workflows_to_target "$CODEX_WORKFLOWS"
}

port_gemini() {
  section "2. Port to Gemini"
  port_skills_to_target "$GEMINI_SKILLS"
  port_workflows_to_target "$GEMINI_WORKFLOWS"
}

port_global_prompts() {
  section "3. Write Global Prompt Files"
  if $PORT_CODEX; then
    ensure_dir "$(dirname "$CODEX_PROMPT")"
  fi
  if $PORT_GEMINI; then
    ensure_dir "$GEMINI_ROOT"
  fi
  port_global_prompt_files
}

verify_postconditions() {
  section "4. Verify"
  if $DRY_RUN; then
    ok "Dry-run only; no filesystem changes were written"
    return
  fi

  if $PORT_CODEX; then
    [ -d "$CODEX_SKILLS" ] || die "Missing Codex skills root"
    [ -d "$CODEX_WORKFLOWS" ] || die "Missing Codex workflows root"
    [ -f "$CODEX_PROMPT" ] || die "Missing global Codex AGENTS.md"
    ok "Codex verify passed"
  fi

  if $PORT_GEMINI; then
    [ -d "$GEMINI_SKILLS" ] || die "Missing Gemini skills root"
    [ -d "$GEMINI_WORKFLOWS" ] || die "Missing Gemini workflows root"
    [ -f "$GEMINI_PROMPT" ] || die "Missing global Gemini GEMINI.md"
    ok "Gemini verify passed"
  fi
}

summary() {
  section "Summary"
  printf '  actions total          %s\n' "$ACTION_COUNT"
  printf '  mkdir                 %s\n' "$MKDIR_COUNT"
  printf '  copy-new              %s\n' "$COPY_COUNT"
  printf '  update-file           %s\n' "$UPDATE_FILE_COUNT"
  printf '  create-generated-file %s\n' "$GENERATED_CREATE_COUNT"
  printf '  update-generated-file %s\n' "$GENERATED_UPDATE_COUNT"
  printf '  skip-unchanged        %s\n' "$SKIP_UNCHANGED_COUNT"
  printf '  warnings              %s\n' "$WARNING_COUNT"
}

main() {
  parse_args "$@"
  print_banner
  preflight
  confirm_real_run
  $PORT_CODEX && port_codex
  $PORT_GEMINI && port_gemini
  port_global_prompts
  verify_postconditions
  summary
}

main "$@"
