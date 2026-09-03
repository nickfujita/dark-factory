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

# Plugin packaging: four manifests carry the version and auto-update reads the
# manifest rather than the git tag, so drift between them ships a plugin that
# never updates. Also guards the one file both plugin roots have to share.
check-plugins:
	bash scripts/check-plugin-manifests.sh

# D24 run-state store acceptance: 37 assertions over concurrent reservation,
# stale-lock reclaim, nested budgets, idempotent completion and resume.
# Offline, no dependencies beyond bash and coreutils, about a second.
check-state:
	bash scripts/test-df-state.sh

# Leakage gate acceptance: the gate must catch a stage name in a product repo,
# honour the router's exemptions, and stay silent in dark-factory itself.
# Offline, git and coreutils only, about a second.
check-leakage:
	bash scripts/test-df-check-leakage.sh

# Claude-only durable Codex worker transport: state, resume, bounded provider
# retry, and a sandbox mode that cannot change silently between turns.
check-claude-codex-transport:
	bash scripts/test-df-codex-exec.sh

# UI design gate: both harnesses route a new visual decision through a driven,
# approved prototype before planning, then consume it in coverage and verification.
check-ui-prototype-flow:
	bash scripts/test-ui-prototype-flow.sh

# Runner smoke tests: drives the df-prd-challenge review runners against fake codex/tmux/
# claude binaries. Takes ~1 minute (it exercises real timeouts), so it is not
# part of `just check`.
test-runners:
	bash scripts/test_prd_review_runners.sh

# Checks that the machine-spawned Claude reviewers opt out of the Matrix phone
# bridge, and that the opt-out survives tmux. Spawns two throwaway tmux
# sessions, so like `test-runners` it is not part of `just check`.
test-bridge-suppression:
	bash scripts/test_bridge_suppression.sh

# Drives the Claude PRD reviewer runner against a REAL tmux server, under both
# base-index settings, with a fake reviewer. `test-runners` stubs tmux with a
# script that exits 0 for everything, so it cannot catch a bad window target;
# this can. Spawns throwaway tmux servers on private -L labels and takes ~40s,
# so it is not part of `just check`.
test-tmux-transport:
	bash scripts/test_tmux_transport.sh

# D30 shared-core parity: every file under codex-plugin/skills/*/references/ and
# codex-plugin/skills/df/playbooks/ must be byte-identical to its skills/ counterpart.
# The allowlist names the files with sanctioned harness deltas (spawn
# transport, reviewer-tier machinery, mirrored reviewer roles). Keep it short;
# a SKILL.md is never in parity scope, and additions need a reason in the
# commit that makes them.
check-parity:
	@echo "Checking codex/claude shared-core parity..."
	@allowlist=" \
	df/playbooks/autonomous-run.md \
	df/playbooks/babysit.md \
	df/playbooks/bug-fix.md \
	df/playbooks/hillclimb.md \
	df/playbooks/orchestrate.md \
	df-prd-challenge/references/personas.md \
	df-prd-challenge/references/rationale.md \
	df-prd-challenge/references/synthesis-prompt.md \
	df-qa-validation/references/synthesis-prompt.md \
	df-qa-validation/references/codex-inline-review-prompt.md \
	df-code-review/references/synthesis-prompt.md \
	df-code-review/references/codex-quality-subagent-prompt.md \
	df-code-review/references/codex-security-subagent-prompt.md \
	df-code-review/references/codex-spec-subagent-prompt.md \
	df-implement/references/implementer-prompt.md \
	df-implement/references/re-review-prompt.md \
	df-implement/references/task-reviewer-prompt.md \
	how/references/critic-prompt.md \
	how/references/explorer-prompt.md \
	"; \
	fail=0; \
	files="$(cd codex-plugin/skills && find */references df/playbooks -type f | sort)"; \
	for rel in $files; do \
		case " $allowlist " in *" $rel "*) continue ;; esac; \
		skill="${rel%%/*}"; rest="${rel#*/}"; \
		src="codex-plugin/skills/$rel"; dst="skills/$skill/$rest"; \
		if [[ ! -f "$dst" ]]; then \
			echo "PARITY FAIL (no skills/ counterpart): $src"; fail=1; \
		elif ! cmp -s "$src" "$dst"; then \
			echo "PARITY FAIL (differs from $dst): $src"; fail=1; \
		fi; \
	done; \
	[[ $fail -eq 0 ]] && echo "Parity OK" || exit 1

# df leaves no trace in a target repo: no skill may write scratch, review output
# or evidence into the repo it operates on. Grep over every SKILL.md, instant.
check-no-repo-scratch:
	bash scripts/check-no-repo-scratch.sh

# D23 invocation contract: proves in clean headless sessions that ordinary
# prompts cannot activate the df router and that explicit /df can. Spends real
# tokens under a budget cap, so it is not part of `just check`.
test-invocation:
	bash scripts/test-df-invocation.sh

# df-eval scenario suite. Some scenarios drive live sessions; those name their
# missing dependency and SKIP rather than fail. Not part of `just check`.
evals *scenarios:
	bash scripts/run-df-evals.sh {{scenarios}}

check:
	just check-shell
	just check-manifest
	just check-references
	just check-agents
	just check-python
	just check-plugins
	just check-parity
	just check-state
	just check-leakage
	just check-claude-codex-transport
	just check-ui-prototype-flow
	just check-no-repo-scratch
