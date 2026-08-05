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
Usage: scripts/sync-from-global.sh [--dry-run] [--manifest <path>]
                                   [--agent-manifest <path>] [--profile <path>]

Copy managed skills and agent definitions from global native directories back
into this repo.
- Claude skills            <- ~/.claude/skills/
- Codex skills             <- ~/.codex/skills/
- Claude agent definitions <- ~/.claude/agents/
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
      echo "DRY-RUN cp fallback: cp -R '$src/.' '$dest/'"
    fi
    return
  fi

  mkdir -p "$dest"

  # NOTE: No --delete flag here (unlike sync-to-global). The repo may contain
  # files not yet synced to global. Reverse sync adds/overwrites but does not
  # remove repo-only files, preventing accidental deletion of uncommitted work.
  if [[ "$has_rsync" == "true" ]]; then
    rsync -a "$src/" "$dest/"
    return
  fi

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

  case "$platform" in
    claude)
      src="$CLAUDE_HOME/skills/$target_name"
      ;;
    codex)
      src="$CODEX_SKILLS_HOME/$target_name"
      ;;
    *)
      echo "Unsupported platform '$platform' at line $line_no" >&2
      exit 1
      ;;
  esac

  if [[ ! -d "$src" ]]; then
    echo "Skipping missing global skill for line $line_no: $src" >&2
    continue
  fi
  if [[ ! -f "$src/SKILL.md" ]]; then
    echo "Skipping invalid global skill (missing SKILL.md): $src" >&2
    continue
  fi

  dest="$REPO_ROOT/$source_path"

  echo "Syncing $platform skill: $src -> $source_path"
  copy_dir "$src" "$dest"
done < "$manifest"

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

    case "$platform" in
      claude)
        src="$CLAUDE_HOME/agents/$target_name"
        ;;
      *)
        echo "Unsupported agent platform '$platform' at line $agent_line_no" >&2
        exit 1
        ;;
    esac

    if [[ ! -f "$src" ]]; then
      echo "Skipping missing global agent for line $agent_line_no: $src" >&2
      continue
    fi

    dest="$REPO_ROOT/$source_path"
    echo "Syncing $platform agent: $src -> $source_path"
    copy_file "$src" "$dest"
  done < "$agent_manifest"
fi

echo "Sync complete."
