#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

manifest="$REPO_ROOT/manifests/skills.tsv"
agent_manifest="$REPO_ROOT/manifests/agents.tsv"
profile_file=""
dry_run="false"

usage() {
  cat <<USAGE
Usage: scripts/sync-to-global.sh [--dry-run] [--manifest <path>]
                                 [--agent-manifest <path>] [--profile <path>]

Copy managed skills and agent definitions from this repo into global native
directories.
- Claude skills           -> ~/.claude/skills/
- Codex skills            -> ~/.codex/skills/
- Claude agent definitions -> ~/.claude/agents/
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run="true"
      shift
      ;;
    --manifest)
      manifest="$2"
      shift 2
      ;;
    --agent-manifest)
      agent_manifest="$2"
      shift 2
      ;;
    --profile)
      profile_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$profile_file" ]]; then
  if [[ ! -f "$profile_file" ]]; then
    echo "Profile not found: $profile_file" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$profile_file"
fi

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_SKILLS_HOME="${CODEX_SKILLS_HOME:-$CODEX_HOME/skills}"

if [[ ! -f "$manifest" ]]; then
  echo "Manifest not found: $manifest" >&2
  exit 1
fi

if command -v rsync >/dev/null 2>&1; then
  has_rsync="true"
else
  has_rsync="false"
fi

copy_file() {
  local src="$1"
  local dest="$2"

  if [[ "$dry_run" == "true" ]]; then
    echo "DRY-RUN cp '$src' -> '$dest'"
    return
  fi

  mkdir -p "$(dirname "$dest")"
  cp -f "$src" "$dest"
}

copy_dir() {
  local src="$1"
  local dest="$2"

  if [[ "$dry_run" == "true" ]]; then
    if [[ "$has_rsync" == "true" ]]; then
      rsync -a -n -v "$src/" "$dest/"
    else
      echo "DRY-RUN cp fallback: rm -rf '$dest' && mkdir -p '$dest' && cp -R '$src/.' '$dest/'"
    fi
    return
  fi

  mkdir -p "$dest"

  # NOTE: --delete ensures each skill directory exactly mirrors the repo (removes
  # stale files within a skill). This WILL delete any files the user added directly
  # in the global skill directory. Use sync-from-global.sh first to pull back local edits.
  #
  # NOTE: this script does NOT remove top-level skill directories that are no longer
  # in the manifest (e.g., after renaming a skill). To remove stale skill directories,
  # run: rm -rf <target_root>/<old-skill-name>
  if [[ "$has_rsync" == "true" ]]; then
    rsync -a --delete "$src/" "$dest/"
    return
  fi

  # cp fallback: clean destination first to mirror rsync --delete behavior
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$src/." "$dest/"
}

line_no=0
while read -r platform source_path target_name _; do
  line_no=$((line_no + 1))

  if [[ -z "${platform:-}" || "$platform" == "#"* ]]; then
    continue
  fi

  if [[ -z "${source_path:-}" || -z "${target_name:-}" ]]; then
    echo "Skipping malformed manifest entry at line $line_no" >&2
    continue
  fi

  src="$REPO_ROOT/$source_path"
  if [[ ! -d "$src" ]]; then
    echo "Missing source directory: $src" >&2
    exit 1
  fi
  if [[ ! -f "$src/SKILL.md" ]]; then
    echo "Source does not look like a skill (missing SKILL.md): $src" >&2
    exit 1
  fi

  case "$platform" in
    claude)
      target_root="$CLAUDE_HOME/skills"
      ;;
    codex)
      target_root="$CODEX_SKILLS_HOME"
      ;;
    *)
      echo "Unsupported platform '$platform' at line $line_no" >&2
      exit 1
      ;;
  esac

  dest="$target_root/$target_name"

  echo "Syncing $platform skill: $source_path -> $dest"
  copy_dir "$src" "$dest"
done < "$manifest"

# Agent definitions are single files, not skill directories, and install to a
# different global root. The manifest is optional: a checkout without it still
# syncs skills.
if [[ -f "$agent_manifest" ]]; then
  agent_line_no=0
  while read -r platform source_path target_name _; do
    agent_line_no=$((agent_line_no + 1))

    if [[ -z "${platform:-}" || "$platform" == "#"* ]]; then
      continue
    fi

    if [[ -z "${source_path:-}" || -z "${target_name:-}" ]]; then
      echo "Skipping malformed agent manifest entry at line $agent_line_no" >&2
      continue
    fi

    src="$REPO_ROOT/$source_path"
    if [[ ! -f "$src" ]]; then
      echo "Missing agent definition: $src" >&2
      exit 1
    fi

    case "$platform" in
      claude)
        target_root="$CLAUDE_HOME/agents"
        ;;
      *)
        echo "Unsupported agent platform '$platform' at line $agent_line_no" >&2
        exit 1
        ;;
    esac

    dest="$target_root/$target_name"
    echo "Syncing $platform agent: $source_path -> $dest"
    copy_file "$src" "$dest"
  done < "$agent_manifest"
fi

echo "Sync complete."
