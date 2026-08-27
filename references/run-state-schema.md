# Run state schema

Version 1. This file is the D24 contract for the df run-state store. One run gets one
authoritative state directory. Every dispatch is counted before it spawns. Budget
exhaustion is a stop, not a flag.

`scripts/df-state.sh` is the reference implementation and the only sanctioned writer.
`scripts/test-df-state.sh` is its acceptance test.

## Layout

A run lives in one directory:

```
.dark-factory/runs/<run-id>/
  run.tsv           one row of run facts, including the current state
  dispatches.tsv    append-only dispatch ledger
  dispositions.tsv  append-only finding dispositions from review stages
  lock/             mkdir-based mutex, holds an owner file
```

The root defaults to `.dark-factory/runs` under the working directory. The
`DF_STATE_ROOT` environment variable overrides it. `<run-id>` matches
`[A-Za-z0-9._-]+`.

Every `.tsv` file is tab-separated with one header row. Field values never contain a
tab or a newline. The writer replaces both with a space.

## run.tsv

One header row, one value row. Every change rewrites the whole file through a temp file
and an atomic `mv`, so a lock-free reader always sees a complete row.

| column | meaning |
|---|---|
| run_id | matches the directory name |
| lane | quick, standard, or high-consequence |
| created | ISO 8601 UTC timestamp of `init` |
| finish_predicate | the finish predicate recorded at lane entry, free text |
| artifact_sha | git HEAD of the working directory at `init`, or `-` outside a repo |
| budget_dispatches | maximum reservations for the whole run, nesting included |
| budget_wall_minutes | wall-clock budget, measured from `created` |
| state | running, paused, done, stopped-budget, or stopped-operator |

`done`, `stopped-budget`, and `stopped-operator` are terminal, and every terminal state
is explicit in the file. Nothing infers "probably finished" from silence. `paused` is
not terminal. A paused run refuses new reservations and waits for the operator.

## dispatches.tsv

Append-only. One row per reserved dispatch. Rows are never deleted, and a recorded
outcome never changes again.

| column | meaning |
|---|---|
| seq | 1-based reservation number, unique and monotonic within the run |
| ts | ISO 8601 UTC timestamp of the reservation |
| role | the dispatch role, resolved through model-policy |
| purpose | one line saying what the dispatch is for |
| parent_seq | the spawning dispatch's own seq for a nested dispatch, `-` for top level |
| outcome | pending, ok, failed, or expired |

`pending` means reserved, spawned or about to spawn, not yet finished. `ok` and
`failed` are recorded by `complete`. `expired` marks a dispatch whose owner died with
the row still pending. Resume logic records it through the same `complete` machinery.

## Reservation rules

1. Reservation happens before spawning. The caller runs `reserve`, receives a seq, and
   only then spawns the dispatch. A refused reservation means the dispatch does not
   happen. There is no spawn-first-log-later path.
2. A reservation is spent the moment its row is appended. No outcome refunds it. A
   failed or expired dispatch still consumed budget, because the spawn was authorized.
3. A nested dispatch reserves with its parent's seq as `parent_seq` and draws from the
   same per-run budget. Nesting cannot mint budget. One coordinator spawning eight
   workers costs nine reservations.
4. When a reservation would exceed `budget_dispatches`, or the wall clock has passed
   `budget_wall_minutes`, `reserve` sets the state to `stopped-budget` and refuses with
   exit 3. The stop lands in the store itself, not as a flag the caller may ignore.
5. `reserve` refuses on every state other than `running`, also with exit 3.
6. `complete` and `status` work in every state, terminal included. Recording the outcome
   of an already-spawned dispatch must always be possible.

## Lock and leases

`lock/` is the run's mutex. `mkdir` is the atomic acquire. Immediately after acquiring,
the holder writes `lock/owner` containing `pid=<pid>` and `ts=<ISO 8601 UTC>` on one
line, and it removes the directory on release. Every write to any file in the run
directory happens under this lock.

The owner file is the lease. A lock whose owner pid is dead is stale and may be
reclaimed. Reclaim renames the lock directory to a unique name before deleting it, so
two contenders cannot both believe they reclaimed the same lock. A lock directory with
no owner file gets a short grace period for the in-flight owner write, then is treated
the same way. A live owner is never preempted. Acquisition waits a bounded time and
then fails with exit 5 rather than blocking forever.

## Resume

Resume reads the store. It never re-runs a seq whose outcome is `ok`. Rows still
`pending` after their owner died are recorded as `expired` and then judged. Seq numbers
stay monotonic across resume, so a re-attempted piece of work gets a new reservation
and a new seq. A resumed run keeps its original budgets and its original `created`
timestamp. The wall clock keeps running through a crash.

## dispositions.tsv

Append-only. One row per review-finding disposition, written by review stages under the
run lock with the same temp-file-plus-mv discipline.

| column | meaning |
|---|---|
| ts | ISO 8601 UTC timestamp |
| stage | the review stage recording the disposition |
| finding_id | the finding's id inside that stage's report |
| disposition | accepted, rejected, deferred, or duplicate |
| note | one line of lead-adjudication rationale |

Version 1 tooling does not append this file. Review stages append it directly, under
the lock, until a subcommand earns its place.

## Tooling

`scripts/df-state.sh <subcommand>`:

| subcommand | arguments | effect |
|---|---|---|
| init | run-id lane budget-dispatches budget-wall-minutes finish-predicate... | create the run directory in state `running` |
| reserve | run-id role purpose [parent-seq] | append a pending row and print the seq, or refuse |
| complete | run-id seq ok\|failed\|expired | record a pending row's outcome, idempotent per outcome |
| status | run-id | print the run row, dispatch counts, and budget headroom |
| stop | run-id done\|budget\|operator | set the matching terminal state |

Exit codes: 0 success, 1 usage or argument error, 2 unknown run or seq, 3 reservation
refused, 4 outcome already recorded differently, 5 lock acquisition timed out.
