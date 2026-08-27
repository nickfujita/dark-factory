# Delta verification for code review

After the one whole-branch discovery pass and its remediation, the branch is
**not** reviewed again. What is reviewed is the remediation: exactly the fixes
that were applied, plus a regression sweep over the code those fixes touched.

This is the same machinery `df-prd-challenge` uses on a PRD
(`personas.md` § "Mode: delta verification"), restated in review terms. The
reason it exists is the same in both places: once discovery has read the whole
artifact, another discovery pass mostly re-reads work the loop itself created,
and that is where a bounded review turns into an unbounded one.

This file is harness-neutral. Both trees run the same contract.

## What the verifier gets

Assemble the delta before dispatching. The verifier is judging your fixes, so
it needs, per finding:

- the finding **as originally raised** — id, severity, category, location, and
  the reviewer's own words for the issue
- the **disposition** you chose and one line of why: `applied as proposed`,
  `applied, modified`, `declined — not real`, `declined — accepted but not
  worth the cost`, `deferred`
- the **fix itself**: the diff of what changed and where it landed
- the **test evidence**: what you ran after the fix and what it said

Plus, once for the whole delta:

- `git diff <discovery-SHA>..<remediation-SHA>` — everything that moved since
  the pass being verified
- the fixed **unresolved list**: findings from discovery that were deliberately
  not fixed, so the verifier does not re-raise them as new

## Who verifies

Send the delta back to **the reviewer that raised the findings**, in its
existing thread, where the harness can continue one. That reviewer knows what
its finding meant, so it can tell a fix that resolves the concern from a fix
that merely responds to the words.

Where the thread cannot be continued — a CLI or tmux leg is a fresh process
every time — dispatch an in-session reviewer with the same verification block,
the original finding text quoted **verbatim**, and the delta. Record the
substitution in the report. A fresh verifier has no self-acceptance bias, which
is a real gain; what it lacks is the raiser's context, and the verbatim finding
plus the delta is what replaces that.

Either way it is a dispatch, and it reserves against the run's budget before it
spawns.

## The verification block

Send this to the verifier as its instruction. It replaces the discovery prompt.

```
This is a DELTA VERIFICATION, not a review round.

You are given the current branch, the remediation delta, and the list of
findings that were acted on. You are NOT reviewing the branch again.

For EACH listed finding, emit exactly one verdict block:

#### <finding id>: <finding title>
**Verdict:** CONFIRMED | NOT CONFIRMED
**Evidence:** [the file:line and the code that settles it — quote it]
**Reason (only if NOT CONFIRMED):** [what is still wrong, or now wrong]

- CONFIRMED means: the fix is present, correct, complete, and does not break
  the code around it.
- NOT CONFIRMED means anything else — including a fix that is present but
  incomplete, a fix that handles the reported case and not the class, a fix
  whose test does not actually exercise it, and a fix that moved the bug rather
  than removing it.
- "Partially" is NOT CONFIRMED. Do not leave a listed finding without a
  verdict.

Guard against confirming a fix because it was made for you:

- CONFIRMED requires evidence you can QUOTE from the current code. If you
  cannot quote the lines that settle it, the verdict is NOT CONFIRMED.
- The author may have applied a different fix from the one you suggested, or
  declined your suggestion while accepting the finding, or declined the finding
  outright with a stated reason. Judge the OUTCOME against your CONCERN, not
  compliance with your suggestion. A different fix that resolves the concern is
  CONFIRMED; your exact suggestion applied in a way that does not resolve the
  concern is NOT CONFIRMED.
- If a disposition declines the finding, say whether the stated reason actually
  answers your concern. "Declined" is not a verdict you have to accept, and it
  is not one you get to ignore either — respond to the reasoning.
- Confirming a fix that does not resolve your finding is worse than re-raising
  it: a confirmed finding is retired permanently.

Then emit a regression sweep under your normal findings header, using the
review output contract, over the code the remediation TOUCHED and its
immediate callers. Code the remediation added or rewrote is the single most
likely place for a new defect; read it as adversarially as you read the
original diff.

A NEW Critical or High in this sweep requires specific evidence: the file and
line, the concrete execution path that reaches it, and what goes wrong when it
does. A new Critical or High without that is a Medium at most. This is not a
second discovery pass, and the bar for opening one after discovery has closed
is deliberately high.

Do not re-raise findings that are not in your list and are not regressions. Do
not re-raise anything on the unresolved list; those were adjudicated.
```

## Reading the result

- **All listed findings CONFIRMED, nothing new** → the review is done. Go to
  finalize.
- **Any NOT CONFIRMED, or a regression** → fix those items under the normal
  rules (a NOT CONFIRMED verdict is a finding, not an order — adjudicate it),
  re-run the affected tests, and **verify the new delta**. At most
  `VERIFY_RETRY_LIMIT` such cycles on one remediation. If it still does not come
  back clean, **stop and escalate to the operator** with the outstanding
  verdicts. Do not open a discovery round to paper over it.
- **A new Critical or High arrived with the required evidence** → it is real.
  Fix it, and verify that delta too, still inside `VERIFY_RETRY_LIMIT`. If the
  evidence bar was not met, record it at its evidenced severity and move on.

A remediation whose delta was never verified cannot support a clean review
outcome. Say so in the report rather than quietly finalizing over it.
