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

check-python:
	python3 -m py_compile skills/skill-creator/scripts/*.py

check:
	just check-shell
	just check-manifest
	just check-references
	just check-python
