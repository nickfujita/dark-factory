# Verification integration handoff

Owner: independently assigned Dark Factory integration agent.
Branch: `feat/role-policy-callers`.
Scope: [continuation plan](plan-verification-continuation.md).

## Source checkpoint

The implementation checkpoint is
`33de1f465741e12c767d0b85df4b06d58ca3ccc8`, with merged main
`c48f21942d3484301e92942208a75bca3e9731b8` integrated. All four plugin manifests
are 1.6.2. These handoff documents do not mark the branch accepted or ready.

The branch introduces `scripts/df-role-caller.sh`, the canonical native caller
inventory, runner integration, paired instruction changes, and caller tests.
`references/role-callers-inventory.md` describes target selection and lifecycle
ownership. Both root and Codex plugin copies must remain consistent.

## Evidence summary and residual

At the checkpoint, 49 caller assertions, the selection-consumer suite, shell,
parity, plugin, and diff checks passed. The original review found fail-open
durable preflight/reservation behavior and incomplete native caller adoption.
Two repair/delta cycles confirmed those scoped fixes. A native acceptance trial
afterward still skipped required planning delegation. It produced a checker-valid
three-task plan but no child preflight, reservation, or launch. A factual
follow-up confirmed the tool was available and no planning skip was recorded.

That residual means NOT READY. The code-review confirmations are not evidence
that the live workflow succeeded. No cross-family review was claimed; the
operator requested Codex-only review.

## Reproduce the missing proof

A fresh subject receives ordinary planning requirements and design, a frozen
plugin root, the consuming checkout, and run/parent identity. Its required
read-only explorer must resolve through the frozen role plan, preflight a
supported native target, reserve before launch, and complete the same ledger
sequence when the actual child terminates. The parent owns completion.

Evidence must bind source SHA, role-plan digest, actual native handles, ordered
tool calls, parent/child sequences, terminal states, plan artifact, and checker
output. Inline exploration and narrative claims are not substitutes. No nested
model CLI is needed. The source checkout remains unchanged during the trial.

## Transfer boundaries

The receiving VM can fetch this branch and read the committed scope without
the originating session or its local paths. Historical private run logs are
supporting evidence only; fresh acceptance is still required. Do not copy
credentials or consuming-project state into this repository.

The previous run consumed 16 of 50 dispatches but its separate four-hour window
expired. Resume under an explicit current allowance and preserve the old usage
and two-cycle review history. Do not resurrect expired counters silently.

Plugin installation and rollout are separate from this PR. Merging a release
does not prove that every existing session loaded it. This handoff authorizes
neither fleet deployment nor PR merge. Follow current repository rules and
skills for execution.
