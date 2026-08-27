# Why the challenge loop works this way

Instructions live in `SKILL.md` and the other reference files. This file holds
the evidence and reasoning behind them, so the instructions can stay
imperative — the same separation the skill requires of the PRDs it reviews
(`prd-structure-rules.md` § 3).

The measurements below come from three concurrent PRD challenge runs of an
earlier version of this skill: roughly forty review rounds and four hundred
findings in total, referred to here as runs A, B and C.

| Run | Rounds | Findings | Outcome |
|---|---|---|---|
| A | 15 (9 Phase A + 5 Phase B + a consolidation pass) | 8C / 49H / 9M | Approved with open items |
| B | 10 (3 Phase A + 6 Phase B + a consistency pass) | 13C / 60H / 64M / 35L | Approved with open items |
| C | 18 (15 Phase A + 3 Phase B) | 5C / 51H + ~96 M/L | Approved |

**Convergence in every case came from changing method, not from running more
rounds.** That single observation is why the loop now has round *types*, a
trend check that can switch method, and a termination rule.

---

## Harness correctness

**An empty review that reports success is worse than a crash.** In one run, the
Codex reviewer blocked on stdin and produced a file containing a header and zero
findings. The only validation was the script's exit code, so the round was
reported as successful. The natural next step on a "clean" round is to approve —
so a silent empty review manufactures false confidence in exactly the situation
where confidence is least warranted. It was caught only because a human noticed
the file size. Hence: stdin is closed on the reviewer invocation, and the round
is accepted only if the output contains a findings section and either structured
findings or an explicit no-findings declaration.

**A fixed scratch path loses data.** The output path was a single fixed file.
With three runs going at once, one clobbered another and a completed review was
lost outright. Hence the run-scoped `REVIEW_ROOT`.

**Substring matching over reviewer output is not a signal.** Limit detection
grepped the reviewer's stderr for phrases like "usage limit" and matched *repo
content the reviewer had read*, nearly aborting a healthy run. A reviewer's
output is arbitrary text about the codebase; it will match anything you look
for. Hence the status file, and the rule that only structured signals — exit
code plus an anchored error envelope — may declare a limit.

**Ten foreground minutes is too short.** On a two- to three-thousand-line PRD at
high reasoning effort, a hard foreground timeout killed healthy rounds
mid-exploration; one run lost two consecutive rounds that way. The run that
switched to a detached process with a wide window and polling completed all
three of its rounds normally. Hence detach-and-poll, with the window and the
poll slice as pinned parameters.

---

## Why the loop did not terminate

Observed identically in all three runs: from roughly the ninth round in run C,
and across three consecutive rounds in run B, **the great majority of new
Critical/High findings lived in prose the previous round's remediation had
added** — not in the original PRD. Those rounds spent about half their yield on
defects the previous round's own fixes created. The loop was feeding on itself.

The mechanism: a PRD states each load-bearing rule in three to five places.
Every fix therefore has three to five propagation targets, and every round
missed some. In run A's final discovery round, **eight of nine remaining
Critical/High findings were pure satellite drift**; exactly one was a genuine
semantic error.

Two things follow.

**The consistency gate has to be mechanical.** Every defect that the consistency
work found was mechanically detectable — a stale cross-reference, an old
threshold value, a term used against its own definition. "Check consistency" as
an instruction produces nothing; re-resolving a list of touched identifiers
produces everything. One redirected consistency pass in run B found thirty-eight
defects, *all* drift and zero requirement gaps, and the round that followed
returned zero Criticals for the first time in that run.

**A consistency-only pass needs a binding charter, and needs verifying.** Run
B's pass overstepped its charter in four places, including changing a threshold,
and was caught only by the next verification round. Restructuring fixes drift
and introduces regressions in the same motion: run A's consolidation repaired
six rounds of drift and, while doing it, introduced two substantive regressions
— one would have shipped the wrong user-facing copy, the other silently removed
the normative force of an earlier fix that protected user configuration from
being erased. Hence: charter is explicit, and no approval ever comes directly
off a restructure.

**Verification terminates loops that discovery rounds cannot.** Once the
original document is exhausted, another discovery pass mostly re-reads prose the
loop itself wrote. A pass scoped to the remediation delta, emitting a
per-finding `CONFIRMED` / `NOT CONFIRMED` verdict, was what actually ended all
three runs. The explicit verdict matters: "partially addressed" is the phrasing
that lets an unfinished fix pass as done.

**Verification belongs to the remediation, not to the end of the phase.** The
first version of this skill made a verification the closing round of a phase,
run after a discovery round came back clean. That leaves every earlier
remediation unchecked until the end — which is precisely how a self-feeding loop
starts, since the defects the runs measured lived in the prose the previous
remediation had just added. Verifying each delta as it is made catches that
prose while the reviewer still has the finding in mind, and it makes the closing
round redundant: a discovery round that comes back clean has already read the
whole document including the last remediation, and that remediation was already
verified. So the phase ends on a clean **discovery** round, and there is no
separate closing verification to forget, to run in the wrong mode, or to skip at
a cap.

**The reviewer that raised a finding is the right one to verify its fix — with a
guard.** It knows what it meant, so it can tell a fix that resolves the concern
from a fix that merely responds to the words. The cost is self-acceptance bias:
a reviewer handed a fix made for it is inclined to accept. Hence the explicit
counter-instruction in the verification prompt — quote the evidence or return
NOT CONFIRMED, judge the outcome against the concern rather than compliance with
the suggestion. In the cross-model phase the verifier is inherently a fresh
process, which removes the bias and costs the context; there the delta file has
to carry what the thread would have carried.

**The class is what makes termination rules usable.** Classifying each finding
`SUBSTANTIVE` or `CONSISTENCY` at the source is what allows the termination rule
to say that consistency-class residue is acceptable at approval — implementation
review catches it — while substantive residue is not. Without the class, every
round looks equally blocking, and the only available moves are "loop again" or
"approve anyway".

**Trend is information the skill could not previously see.** Run B's trajectory
was 3C/7H → 3C/15H → 2C/10H → 1C/5H → 0C/4H → 0C/0H. A binary pass/fail gate
reads the first five of those rounds identically. A monotonic decline is
evidence of convergence and justifies another round; a flat or rising count, or
a round whose findings are mostly in freshly-added prose, is evidence that
another round of the same kind will not help.

**Counting rounds was the wrong meter, and this is the correction.** The
hardened generation of this skill capped rounds, and a run still reached
fifteen of them legally, because the expensive work was typed as something
other than a round. Delta verifications were exempt by design. Adopted orphan
reviews were exempt. A convergence extension added rounds past the cap. The cap
was real and the work went around it. So the cap is now a **single budget of
reviewer dispatches that everything consumes**, reserved before the spawn in a
store that refuses rather than warns. A mechanism that cannot be reached
without a reservation cannot be exempted from one.

**Growth was a sensor wired to the wrong actuator.** The old
`GROWTH_WARN_ROUND_PCT` and `GROWTH_WARN_TOTAL_PCT` flagged; nothing stopped. On
the measured run the PRD went from 4,265 words to 62,445, a 14.6x expansion,
flagging the whole way. The sensors were right and the actuator was a note in a
report. They are now one hard stop at twice the interview's output, and
crossing it terminates the run as non-converging. There is no extension,
because "converging" is exactly what a self-feeding loop reports about itself:
run B's trend looked monotonic while half its yield was defects its own fixes
had created.

**Remediation that adds mechanism is the ratchet's engine.** Each round's fixes
added queues, DLQs, signed admission permits, watchdogs, a 131-entry producer
manifest. The next round then found technically real Critical/High gaps in that
new prose. Every individual step was locally correct and the aggregate was a
47-hour program with zero visible product. Autonomy over wording is safe;
autonomy over mechanism compounds. So a fix that would introduce
infrastructure escalates to the operator instead of landing.

**Model-enumerated inventories are hallucination bait by construction.** The one
systematic worker failure class in the forensics was a 94-entry census with
guessed and nonexistent boundaries. A model asked to enumerate exhaustively
will produce a complete-looking list whether or not it can see the whole set.
Generating the census from source and reviewing it costs less and is true.

**Most work does not need the loop at all.** The multi-round persona challenge
was calibrated for models that half-followed instructions; models that follow
maximally never run out of legitimate findings, so a zero-findings exit
condition never fires. For a typical feature the single pass is the better
trade: two families on one prompt, adjudicated by a lead who is told that an
Act-On list over five items means under-filtering. The adversarial signal comes
from model diversity rather than assigned personas, and one remediation wave
with one delta verification is where the yield curve flattens. The multi-round
loop survives only where wrongness is a security incident, and there it runs
under the budget above.

**Re-review survives, in bounded forms.** The operator's original observation
was right: a review pass is a sample, and resampling catches real findings.
What blew up was the coupling. Same-model reruns are correlated draws,
autonomous remediation between draws manufactures fresh review surface, and a
zero-findings exit needs reviewer exhaustion. So resampling is kept and the
couplings are cut: delta verification instead of rediscovery, one fresh verdict
per new artifact version, and an operator-invoked second opinion that is
decorrelated by construction, budget-counted, and cannot move the gates.

**Open items belong at the top of the PRD.** When a PRD is approved with
residue, full disclosure to the implementing agent beats an extra round of
polish. The implementer is the party who will hit the ambiguity, and the one
positioned to stop and ask.

---

## Document structure

**One normative home per rule** is the highest-leverage change of all: a
satellite that cross-references cannot go stale, and a satellite that restates
always will. Run C implemented this as a pinned parameters table plus explicit
reading conventions, and it ended the drift class outright.

**Rationale leaks into the specification.** Prose written to stop a reviewer
re-raising a finding is audit trail addressed to reviewers, sitting inside a
document written for an implementer with no context. Run A measured it:
justification-connective density (*because*, *otherwise*, *rather than*) tripled
from 1.19 to 3.56 per thousand words while the document grew from ten thousand
to thirty-three thousand words. Rationale is relocated, never deleted — it
encodes hard-won corrections a future implementer would otherwise undo.

**Growth is a risk signal.** Remediation instinctively appends rather than
edits: run B accumulated sixty-two inline "challenge round:" annotations and
grew by 130%. Every appended qualifier is new surface for the next round.
Structured tables and matrices are the good pattern — dense, scannable,
single-location. Prose paragraphs are where redundancy breeds.

**Assertion-checked replacements catch the remediator's own errors.** Run B
applied fixes through replacements that had to match their target exactly once;
that discipline caught two of its own mistakes at application time rather than
letting them land silently and reappear as the next round's findings.

---

## Remediation discipline

**A remediator that applies whatever a reviewer suggests is a liability.** In
the measured runs the good behaviour showed up anyway — one remediator declined
a recommended fix that would have permanently raised infrastructure cost by
about 25% to recover a gigabyte of disk, kept the finding, and recorded the
reasoning; another checked a confident-sounding claim against the code and found
the reviewer had misread it. Both outcomes came from an individual agent
happening to be careful. Nothing in the skill required it, and a less careful
agent on the same findings would have shipped the expensive change and the fix
for a defect that did not exist. Hence the judgment mandate: consult the
register, verify the claim, form your own view of the fix, record the
disposition.

**A recorded decline is worth more than a silent one.** The register is what
makes a re-raised finding cheap to dismiss, and what stops a review loop
quietly eroding scope the operator ratified — two runs saw reviewers propose
descoping requirements that had already been decided. A decline that is not
written down gets re-litigated every round.

---

## Model and cost policy

**Never skip a clean persona; downgrade it.** The alternative considered was
skipping personas that came back clean. Skipping removes the only regression net
over remediation churn — and remediation churn is precisely where the new
defects come from. A recheck is genuinely a cheaper task than discovery: it is
scoped to the sections that changed. A persona whose recheck surfaces a
Critical/High is promoted back to full strength.

**The recheck tier has a floor for a reason.** Pinning it in an agent definition
rather than at the call site is partly mechanical — reasoning effort cannot be
set per-spawn on the Agent tool — and partly defensive: a stated floor means a
future model substitution cannot silently degrade the loop's only regression
net. The discovery tier is deliberately left unpinned so the operator controls
it from the orchestrating session.

**Model diversity is load-bearing.** In run C, the Codex phase surfaced five
Critical and thirty-two High findings of a visibly different class — unresolved
decisions, missing determinism, unbounded payloads — that three Claude personas
had read past for fifteen rounds, including a migration story still sitting as
an unresolved blocker while the document claimed to be hardened. If rounds have
to be cut for budget, cut Phase A rounds; never drop the cross-model phase.

**A tooling-blocked phase defers approval; it never waives it.** Run B was
briefly marked Approved because the Codex CLI's authentication had expired. The
operator rejected that outcome, and it is now a hard rule.

**Independent runs of the same text merge, not stack.** Runs A and B each found
a predecessor's completed-but-unsynthesized review, verified that the PRD text
was byte-identical, and merged the findings into the current round rather than
discarding free signal. Merging is documented behaviour, and the byte-identity
check is what makes it safe.
