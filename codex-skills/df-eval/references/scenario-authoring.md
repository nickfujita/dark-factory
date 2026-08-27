# Scenario authoring

Scenarios live in `scripts/df-eval-scenarios/`, one executable bash file each. `scripts/run-df-evals.sh` is the only entry point. It runs every scenario, prints a PASS/FAIL/SKIP table, and exits nonzero on any FAIL.

## Contract

- A scenario is an executable `*.sh` in `scripts/df-eval-scenarios/`, bash and coreutils only, plus whatever its own SKIP gate checks for.
- Exit 0 with no SKIP line means PASS.
- Exit 0 after printing one line starting `SKIP: ` means SKIP. The line names the missing dependency, so the table reports the gap without lying about coverage.
- Any nonzero exit means FAIL.
- Print one assertion per line to stdout. End with a one-line summary. The runner keeps the full log and shows the last line in its table.
- Clean up after yourself. Work under a `mktemp -d` directory with a `trap ... EXIT` removal. Never touch the repo tree, the operator's global config, or another run's state.

## Kinds, in order of preference

1. **Deterministic checks.** Store-file assertions against `scripts/df-state.sh`, text invariants over skill files, structural checks over manifests. No model, no cost, no flake. Prove what is provable without a session before spending one. Assert from the files on disk, not from command stdout, wherever both exist.
2. **Live blinded sessions.** A headless session against a throwaway install, graded from its stream-json transcript. Follow `blinding-rules.md` for everything the session can see. Live scenarios spend real model budget and minutes of wall clock. Gate them. SKIP when the CLI they need is missing, and honor `DF_EVAL_SKIP_LIVE=1` with a SKIP so the deterministic suite stays cheap to run alone.

A text invariant is a legitimate scenario when it is labeled as one. `open-pr-never-merges.sh` proves the never-merge language stands in the files that own it. It does not prove a live session obeys it. The scenario's comments say so, and the live version is the named upgrade path.

## Stubs

A scenario whose machinery has not landed ships as a stub. It prints `SKIP:` with the named dependency and exits 0. Stub comments describe what the real scenario will assert, so the stub is a spec, not a placeholder. Current stubs:

- `growth-stop.sh` waits on the df-prd-challenge spine economics.
- `takeover-reanchor.sh` waits on the handoff flow as a scriptable surface.

Replacing a stub with a real scenario counts as a skill change and goes through the same review as any other.

## Delegation

An existing harness stays authoritative for what it covers. A scenario that needs the same proof delegates with `exec bash <harness>` rather than duplicating assertions. `invocation-contract.sh` wraps `scripts/test-df-invocation.sh` this way. Duplicated assertions drift, and drifted assertions grade the wrong thing.
