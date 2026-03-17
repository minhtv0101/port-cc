#!/usr/bin/env bash
# ============================================================================
# port-claudekit-windows.sh
# Build a portable bundle from this machine and install it elsewhere.
#
# Scope:
# - Bundle only top-level skill folders containing SKILL.md
# - Bundle only top-level workflow markdown files
# - Include CLAUDE.md, AGENTS.md, and GEMINI.md
# - Install by syncing the bundle into $HOME/.claude, $HOME/.codex, and $HOME/.gemini
# - Do not prune destination-only directories automatically
# ============================================================================

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BUNDLE_ROOT_DEFAULT="$SCRIPT_DIR/portable-home-bundle"
BUNDLE_ROOT="${PORT_CLAUDEKIT_BUNDLE_ROOT:-$BUNDLE_ROOT_DEFAULT}"

MODE=''
DRY_RUN=false
ASSUME_YES=false

LOCAL_CLAUDE_SKILLS="$HOME/.claude/skills"
LOCAL_CLAUDE_WORKFLOWS="$HOME/.claude/workflows"
LOCAL_CLAUDE_PROMPT="$HOME/.claude/CLAUDE.md"

BUNDLE_CLAUDE_ROOT="$BUNDLE_ROOT/.claude"
BUNDLE_CLAUDE_SKILLS="$BUNDLE_CLAUDE_ROOT/skills"
BUNDLE_CLAUDE_WORKFLOWS="$BUNDLE_CLAUDE_ROOT/workflows"
BUNDLE_CLAUDE_PROMPT="$BUNDLE_CLAUDE_ROOT/CLAUDE.md"

BUNDLE_CODEX_ROOT="$BUNDLE_ROOT/.codex"
BUNDLE_CODEX_SKILLS="$BUNDLE_CODEX_ROOT/skills"
BUNDLE_CODEX_WORKFLOWS="$BUNDLE_CODEX_ROOT/workflows"
BUNDLE_CODEX_PROMPT="$BUNDLE_CODEX_ROOT/AGENTS.md"

BUNDLE_GEMINI_ROOT="$BUNDLE_ROOT/.gemini"
BUNDLE_GEMINI_SKILLS="$BUNDLE_GEMINI_ROOT/antigravity/skills"
BUNDLE_GEMINI_WORKFLOWS="$BUNDLE_GEMINI_ROOT/antigravity/global_workflows"
BUNDLE_GEMINI_PROMPT="$BUNDLE_GEMINI_ROOT/GEMINI.md"

TMP_DIRS=()
PLANNED_DIR_ROOT=''

ACTION_COUNT=0
MKDIR_COUNT=0
COPY_COUNT=0
UPDATE_COUNT=0
SKIP_COUNT=0

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
  for tmp in "${TMP_DIRS[@]:-}"; do
    if [ -n "${tmp:-}" ] && [ -d "$tmp" ]; then
      rm -rf "$tmp" || true
    fi
  done
  return 0
}
trap cleanup EXIT

new_temp_dir() {
  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/port-claudekit-win.XXXXXX")
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

action() {
  local kind="$1"
  shift
  ACTION_COUNT=$((ACTION_COUNT + 1))
  case "$kind" in
    mkdir) MKDIR_COUNT=$((MKDIR_COUNT + 1)) ;;
    copy-new) COPY_COUNT=$((COPY_COUNT + 1)) ;;
    update-file) UPDATE_COUNT=$((UPDATE_COUNT + 1)) ;;
    skip-unchanged) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
  esac
  printf '  [%s] %-20s %s\n' "$(mode_label)" "$kind" "$*"
}

usage() {
  cat <<EOF
Usage:
  bash $SCRIPT_NAME --bundle [--dry-run] [--yes] [--bundle-root PATH]
  bash $SCRIPT_NAME --install [--dry-run] [--yes] [--bundle-root PATH]

Modes:
  --bundle              Snapshot the current machine into a portable bundle in this repo
  --install             Install the portable bundle into \$HOME on another machine

Options:
  --bundle-root PATH    Override the portable bundle directory
  --dry-run             Print planned actions without writing
  --yes                 Skip confirmation prompt for real runs
  --help                Show this help
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --bundle)
        [ -z "$MODE" ] || die "Choose only one mode: --bundle or --install"
        MODE='bundle'
        ;;
      --install)
        [ -z "$MODE" ] || die "Choose only one mode: --bundle or --install"
        MODE='install'
        ;;
      --bundle-root)
        shift
        [ "$#" -gt 0 ] || die "Missing value for --bundle-root"
        BUNDLE_ROOT="$1"
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      --yes)
        ASSUME_YES=true
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

  [ -n "$MODE" ] || die "You must choose --bundle or --install"
}

print_banner() {
  printf '\n%sClaudeKit portable bundle helper%s\n' "$BOLD" "$NC"
  printf '  mode:              %s\n' "$MODE"
  printf '  bundle root:       %s\n' "$(display_path "$BUNDLE_ROOT")"
  if [ "$MODE" = 'bundle' ]; then
    printf '  source skills:     %s\n' "$(display_path "$LOCAL_CLAUDE_SKILLS")"
    printf '  source workflows:  %s\n' "$(display_path "$LOCAL_CLAUDE_WORKFLOWS")"
    printf '  source prompt:     %s\n' "$(display_path "$LOCAL_CLAUDE_PROMPT")"
  else
    printf '  install claude:    %s\n' "$(display_path "$HOME/.claude")"
    printf '  install codex:     %s\n' "$(display_path "$HOME/.codex")"
    printf '  install gemini:    %s\n' "$(display_path "$HOME/.gemini")"
  fi
  if $DRY_RUN; then
    printf '  run mode:          %sDRY RUN%s\n' "$YLW$BOLD" "$NC"
  else
    printf '  run mode:          %sREAL RUN%s\n' "$GRN$BOLD" "$NC"
  fi
}

confirm_real_run() {
  local prompt="$1"
  if $DRY_RUN || $ASSUME_YES; then
    return
  fi
  printf '\n%s [y/N] ' "$prompt"
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

copy_tree_sync_all() {
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
    sync_file "$file" "$dst_root/${file#$src_root/}"
  done < <(find "$src_root" \( -type d -name node_modules -prune \) -o \( -type f -o -type l \) -print | LC_ALL=C sort)
}

sync_skill_roots() {
  local src_root="$1"
  local dst_root="$2"
  local skill_dir
  local skill_name

  ensure_dir "$dst_root"
  while IFS= read -r skill_dir; do
    [ -n "$skill_dir" ] || continue
    [ -f "$skill_dir/SKILL.md" ] || continue
    skill_name=$(basename "$skill_dir")
    copy_tree_sync_all "$skill_dir" "$dst_root/$skill_name"
  done < <(find "$src_root" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
}

sync_workflows() {
  local src_root="$1"
  local dst_root="$2"
  local src_file

  ensure_dir "$dst_root"
  while IFS= read -r src_file; do
    [ -n "$src_file" ] || continue
    sync_file "$src_file" "$dst_root/$(basename "$src_file")"
  done < <(find "$src_root" -mindepth 1 -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
}

preflight_bundle() {
  section "0. Preflight"
  [ -d "$LOCAL_CLAUDE_SKILLS" ] || die "Source skills not found at $(display_path "$LOCAL_CLAUDE_SKILLS")"
  [ -d "$LOCAL_CLAUDE_WORKFLOWS" ] || die "Source workflows not found at $(display_path "$LOCAL_CLAUDE_WORKFLOWS")"
  [ -f "$LOCAL_CLAUDE_PROMPT" ] || die "Source CLAUDE.md not found at $(display_path "$LOCAL_CLAUDE_PROMPT")"
  [ -f "$SCRIPT_DIR/port-claudekit.sh" ] || die "Missing porter at $SCRIPT_DIR/port-claudekit.sh"
  ok "Local Claude sources exist"
}

preflight_install() {
  section "0. Preflight"
  [ -d "$BUNDLE_CLAUDE_SKILLS" ] || die "Bundle Claude skills not found at $(display_path "$BUNDLE_CLAUDE_SKILLS")"
  [ -d "$BUNDLE_CLAUDE_WORKFLOWS" ] || die "Bundle Claude workflows not found at $(display_path "$BUNDLE_CLAUDE_WORKFLOWS")"
  [ -f "$BUNDLE_CLAUDE_PROMPT" ] || die "Bundle CLAUDE.md not found at $(display_path "$BUNDLE_CLAUDE_PROMPT")"
  [ -d "$BUNDLE_CODEX_SKILLS" ] || die "Bundle Codex skills not found at $(display_path "$BUNDLE_CODEX_SKILLS")"
  [ -d "$BUNDLE_CODEX_WORKFLOWS" ] || die "Bundle Codex workflows not found at $(display_path "$BUNDLE_CODEX_WORKFLOWS")"
  [ -f "$BUNDLE_CODEX_PROMPT" ] || die "Bundle AGENTS.md not found at $(display_path "$BUNDLE_CODEX_PROMPT")"
  [ -d "$BUNDLE_GEMINI_SKILLS" ] || die "Bundle Gemini skills not found at $(display_path "$BUNDLE_GEMINI_SKILLS")"
  [ -d "$BUNDLE_GEMINI_WORKFLOWS" ] || die "Bundle Gemini workflows not found at $(display_path "$BUNDLE_GEMINI_WORKFLOWS")"
  [ -f "$BUNDLE_GEMINI_PROMPT" ] || die "Bundle GEMINI.md not found at $(display_path "$BUNDLE_GEMINI_PROMPT")"
  ok "Portable bundle exists"
}

bundle_claude_payload() {
  section "1. Snapshot Claude Payload"
  sync_skill_roots "$LOCAL_CLAUDE_SKILLS" "$BUNDLE_CLAUDE_SKILLS"
  sync_workflows "$LOCAL_CLAUDE_WORKFLOWS" "$BUNDLE_CLAUDE_WORKFLOWS"
  sync_file "$LOCAL_CLAUDE_PROMPT" "$BUNDLE_CLAUDE_PROMPT"
}

bundle_ported_payloads() {
  local porter_args

  section "2. Build Codex and Gemini Payloads"
  if $DRY_RUN; then
    porter_args="--dry-run"
  else
    porter_args="--yes"
  fi

  PORT_CLAUDEKIT_SRC_SKILLS="$LOCAL_CLAUDE_SKILLS" \
  PORT_CLAUDEKIT_SRC_WORKFLOWS="$LOCAL_CLAUDE_WORKFLOWS" \
  PORT_CLAUDEKIT_SRC_CLAUDE="$LOCAL_CLAUDE_PROMPT" \
  PORT_CLAUDEKIT_CODEX_SKILLS="$BUNDLE_CODEX_SKILLS" \
  PORT_CLAUDEKIT_CODEX_WORKFLOWS="$BUNDLE_CODEX_WORKFLOWS" \
  PORT_CLAUDEKIT_CODEX_PROMPT="$BUNDLE_CODEX_PROMPT" \
  PORT_CLAUDEKIT_GEMINI_ROOT="$BUNDLE_GEMINI_ROOT" \
  PORT_CLAUDEKIT_GEMINI_SKILLS="$BUNDLE_GEMINI_SKILLS" \
  PORT_CLAUDEKIT_GEMINI_WORKFLOWS="$BUNDLE_GEMINI_WORKFLOWS" \
  PORT_CLAUDEKIT_GEMINI_PROMPT="$BUNDLE_GEMINI_PROMPT" \
  bash "$SCRIPT_DIR/port-claudekit.sh" "$porter_args"
}

install_claude_payload() {
  section "1. Install Claude Payload"
  sync_skill_roots "$BUNDLE_CLAUDE_SKILLS" "$HOME/.claude/skills"
  sync_workflows "$BUNDLE_CLAUDE_WORKFLOWS" "$HOME/.claude/workflows"
  sync_file "$BUNDLE_CLAUDE_PROMPT" "$HOME/.claude/CLAUDE.md"
}

install_codex_payload() {
  section "2. Install Codex Payload"
  sync_skill_roots "$BUNDLE_CODEX_SKILLS" "$HOME/.codex/skills"
  sync_workflows "$BUNDLE_CODEX_WORKFLOWS" "$HOME/.codex/workflows"
  sync_file "$BUNDLE_CODEX_PROMPT" "$HOME/.codex/AGENTS.md"
}

install_gemini_payload() {
  section "3. Install Gemini Payload"
  sync_skill_roots "$BUNDLE_GEMINI_SKILLS" "$HOME/.gemini/antigravity/skills"
  sync_workflows "$BUNDLE_GEMINI_WORKFLOWS" "$HOME/.gemini/antigravity/global_workflows"
  sync_file "$BUNDLE_GEMINI_PROMPT" "$HOME/.gemini/GEMINI.md"
}

verify_bundle() {
  section "3. Verify Bundle"
  if $DRY_RUN; then
    ok "Dry-run only; bundle was not written"
    return
  fi
  [ -f "$BUNDLE_CLAUDE_PROMPT" ] || die "Missing bundled CLAUDE.md"
  [ -f "$BUNDLE_CODEX_PROMPT" ] || die "Missing bundled AGENTS.md"
  [ -f "$BUNDLE_GEMINI_PROMPT" ] || die "Missing bundled GEMINI.md"
  ok "Bundle verify passed"
}

verify_install() {
  section "4. Verify Install"
  if $DRY_RUN; then
    ok "Dry-run only; no files were written"
    return
  fi
  [ -f "$HOME/.claude/CLAUDE.md" ] || die "Missing installed CLAUDE.md"
  [ -f "$HOME/.codex/AGENTS.md" ] || die "Missing installed AGENTS.md"
  [ -f "$HOME/.gemini/GEMINI.md" ] || die "Missing installed GEMINI.md"
  ok "Install verify passed"
}

summary() {
  section "Summary"
  printf '  actions total          %s\n' "$ACTION_COUNT"
  printf '  mkdir                 %s\n' "$MKDIR_COUNT"
  printf '  copy-new              %s\n' "$COPY_COUNT"
  printf '  update-file           %s\n' "$UPDATE_COUNT"
  printf '  skip-unchanged        %s\n' "$SKIP_COUNT"
}

run_bundle() {
  preflight_bundle
  confirm_real_run "Build or update the portable bundle in this repo?"
  bundle_claude_payload
  bundle_ported_payloads
  verify_bundle
}

run_install() {
  preflight_install
  confirm_real_run "Install the portable bundle into \$HOME on this machine?"
  install_claude_payload
  install_codex_payload
  install_gemini_payload
  verify_install
}

main() {
  parse_args "$@"
  print_banner
  case "$MODE" in
    bundle)
      run_bundle
      ;;
    install)
      run_install
      ;;
  esac
  summary
}

main "$@"
