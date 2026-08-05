set shell := ["bash", "-cu"]

default:
	@just --list

help:
	@just --list

sync:
	bash scripts/sync-to-global.sh

sync-dry:
	bash scripts/sync-to-global.sh --dry-run

sync-to-global:
	bash scripts/sync-to-global.sh

sync-to-global-dry:
	bash scripts/sync-to-global.sh --dry-run

sync-to-global-profile profile:
	bash scripts/sync-to-global.sh --profile {{profile}}

sync-to-global-profile-dry profile:
	bash scripts/sync-to-global.sh --dry-run --profile {{profile}}

sync-from-global:
	bash scripts/sync-from-global.sh

sync-from-global-dry:
	bash scripts/sync-from-global.sh --dry-run

sync-from-global-profile profile:
	bash scripts/sync-from-global.sh --profile {{profile}}

sync-from-global-profile-dry profile:
	bash scripts/sync-from-global.sh --dry-run --profile {{profile}}

check-shell:
	find . -name '*.sh' -not -path './.git/*' -exec bash -n {} +

check-manifest:
	@echo "Checking manifest integrity..."
	@while IFS=$'\t' read -r platform source_path target_name _rest; do \
		[[ -z "$platform" || "$platform" == \#* ]] && continue; \
		[[ -z "$source_path" || -z "$target_name" ]] && { echo "FAIL: malformed line in skills.tsv"; exit 1; }; \
		[[ -d "$source_path" ]] || { echo "FAIL: missing directory $source_path"; exit 1; }; \
		[[ -f "$source_path/SKILL.md" ]] || { echo "FAIL: missing SKILL.md in $source_path"; exit 1; }; \
	done < manifests/skills.tsv
	@echo "Manifest OK"

check-references:
	@echo "Checking skill reference files..."
	@fail=0; \
	while IFS=$'\t' read -r platform skill_dir target_name _rest; do \
		[[ -z "$platform" || "$platform" == \#* ]] && continue; \
		if [[ -d "$skill_dir/references" ]]; then \
			for ref in "$skill_dir"/references/*.md; do \
				[[ -f "$ref" ]] || { echo "FAIL: missing $ref"; fail=1; }; \
			done; \
		fi; \
	done < manifests/skills.tsv; \
	[[ $fail -eq 0 ]] && echo "References OK" || exit 1

check-agents:
	@echo "Checking agent definitions..."
	@fail=0; \
	while IFS=$'\t' read -r platform source_path target_name _rest; do \
		[[ -z "$platform" || "$platform" == \#* ]] && continue; \
		[[ -z "$source_path" || -z "$target_name" ]] && { echo "FAIL: malformed line in agents.tsv"; fail=1; continue; }; \
		[[ -f "$source_path" ]] || { echo "FAIL: missing agent definition $source_path"; fail=1; continue; }; \
		[[ "$(head -1 "$source_path")" == "---" ]] || { echo "FAIL: $source_path has no YAML frontmatter"; fail=1; continue; }; \
		fm_name="$(sed -n '2,/^---$/p' "$source_path" | sed -n 's/^name:[[:space:]]*//p' | head -1)"; \
		stem="$(basename "$source_path" .md)"; \
		[[ "$fm_name" == "$stem" ]] || { echo "FAIL: $source_path frontmatter name '$fm_name' != filename stem '$stem'"; fail=1; }; \
		[[ "$target_name" == "$stem.md" ]] || { echo "FAIL: $source_path target_name '$target_name' != '$stem.md'"; fail=1; }; \
		effort="$(sed -n '2,/^---$/p' "$source_path" | sed -n 's/^effort:[[:space:]]*//p' | head -1)"; \
		if [[ -n "$effort" ]]; then \
			case "$platform" in \
				claude) case "$effort" in low|medium|high|max) ;; *) echo "FAIL: $source_path effort '$effort' not one of low|medium|high|max (claude)"; fail=1 ;; esac ;; \
				codex) case "$effort" in low|medium|high|xhigh) ;; *) echo "FAIL: $source_path effort '$effort' not one of low|medium|high|xhigh (codex)"; fail=1 ;; esac ;; \
				*) echo "FAIL: $source_path unknown platform '$platform'"; fail=1 ;; \
			esac; \
		fi; \
	done < manifests/agents.tsv; \
	[[ $fail -eq 0 ]] && echo "Agents OK" || exit 1

check-python:
	python3 -m py_compile skills/skill-creator/scripts/*.py

# Runner smoke tests: drives the drk-02 review runners against fake codex/tmux/
# claude binaries. Takes ~1 minute (it exercises real timeouts), so it is not
# part of `just check`.
test-runners:
	bash scripts/test_prd_review_runners.sh

check:
	just check-shell
	just check-manifest
	just check-references
	just check-agents
	just check-python
