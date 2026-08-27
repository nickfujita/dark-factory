# Dark Factory v2 flow diagrams

Drawn from `docs/2026-08-27-dark-factory-v2-decision-plan.md`, revision 4. Solid edges are forward flow. Dashed edges mark bounded loops, bypasses, and optional paths, and each loop label names its bound.

## Top-level routing

The df router is the top of the stack, and it is explicit-invocation-only. A SessionStart hook injects a one-line reminder and the ownership rules every session, but entering the mode takes the operator typing /df. The model may suggest /df when a task looks like a playbook match, and never enters on its own. Once entered, the router picks a lane, which sets budgets and ceremony, then classifies the ask into a playbook. The feature playbook is the artifact spine. When the repo carries a `.dark-factory/project.yaml` manifest, the router pulls the verification skill, feature map, and Spellbook catalog into context selection. df-eval, pause-safely, and session-pickup cut across every branch.

```mermaid
flowchart TD
  HOOK["SessionStart hook"] -.->|injects reminder and ownership rules| DF["df router"]
  ASKIN["Operator types /df"] --> DF
  CASUAL["Any ask without /df"] -.->|model may suggest /df in one line, never enters| PLAIN["Plain reply"]

  subgraph PROJ["Project layer, optional per repo"]
    YAML[".dark-factory/project.yaml"]
    VSK["Verification skill"]
    FMAP["Feature map"]
    CAT["Spellbook catalog"]
    YAML --> VSK
    YAML --> FMAP
    YAML --> CAT
  end
  PROJ -.->|pre-context when the manifest exists| DF

  DF --> LANE{"Pick a lane"}
  LANE --> QUICK["Quick"]
  LANE --> STD["Standard"]
  LANE --> HIGH["High-consequence"]

  QUICK --> PICK{"Classify the ask"}
  STD --> PICK
  HIGH --> PICK

  subgraph PB["Playbooks"]
    INV["investigation"]
    BUG["bug-fix"]
    PERF["perf-issue"]
    REF["refactoring"]
    FEAT["feature, the artifact spine"]
  end
  PICK -->|read-only question| INV
  PICK -->|defect| BUG
  PICK -->|slow path| PERF
  PICK -->|restructure| REF
  PICK -->|feature or enhancement| FEAT
  PICK -.->|no playbook fits| FIO["figure-it-out"]
  PICK -.->|large multi-agent run| ORCH["orchestrate playbook"]

  subgraph SUP["Supporting skills"]
    HOW["how"]
    WHY["why"]
    INT["interrogate"]
    SW["swarm"]
    BR["blast-radius"]
    PROTO["prototype playbook"]
  end
  PB -->|called as needed| SUP

  subgraph XC["Cross-cutting"]
    EVAL["df-eval, capped"]
    PAUSE["pause-safely"]
    PICKUP["session-pickup"]
  end
  DF -.->|at any point in any branch| XC
```

## The feature branch in detail

The feature playbook runs the artifact spine end to end. The Quick lane skips the PRD steps and df records the finish predicate instead. Standard runs the challenge as a single pass, and High-consequence runs the hardened loop under the dispatch budget with delta-only rechecks. Implementation works task by task under the five-round breaker. Code review is one discovery pass followed by delta verification, with an operator-invoked one-shot second opinion available in the Standard lane. Delivery is several small PRs merging behind a flag as each goes green, and the flag-flip PR triggers the full acceptance runbook plus the integrated review pass.

```mermaid
flowchart TD
  ENTRY["feature playbook entry"] --> PRDI["df-prd-interview (lite Standard, full High-consequence)"]
  ENTRY -.->|Quick lane, df records the finish predicate, no PRD, challenge, or runbook| IMPL
  PRDI --> PRDC["df-prd-challenge"]
  PRDC -.->|hardened loop High-consequence, dispatch budget, delta-only recheck| PRDC
  PRDC -->|single pass in Standard| DESIGN["df-design"]
  DESIGN --> PLAN["df-plan (skippable for small changes)"]
  PLAN --> QAGEN["df-qa-runbook-gen"]
  QAGEN --> QAVAL["df-qa-validation"]

  subgraph IMPL["df-implement, per-task loop"]
    TASK["implement task"]
    REV["per-task review, two verdicts"]
    FIX["fix round"]
    ADJ["adjudication"]
    TASK --> REV
    REV -->|findings| FIX
    FIX -.->|re-review, five-round breaker, late rounds fresh implementer| REV
    REV -.->|approved, next task| TASK
    REV -->|cap hit| ADJ
    ADJ -->|verdict recorded| TASK
  end
  QAVAL --> IMPL
  IMPL -->|all tasks done| DEVVER["df-dev-verify"]

  subgraph CR["df-code-review"]
    DISC["discovery pass, one per branch"]
    DELTA["delta verification"]
    SECOP["second-opinion pass"]
    DISC -->|findings remediated| DELTA
    DELTA -.->|changed sections only, one pass per new head SHA| DELTA
    DISC -.->|operator-invoked, one-shot, decorrelated draw| SECOP
    SECOP -->|lead adjudicates| DELTA
  end
  DEVVER --> CR

  CR --> OPENPR["df-open-pr"]
  OPENPR --> PRS["small PR merges behind a flag, typically 3 to 7"]
  PRS -.->|next slice, the loop repeats per PR| IMPL
  PRS -->|last PR| FLIP["flag-flip PR"]
  FLIP --> QAACC["df-qa-acceptance, full runbook"]
  FLIP --> INTEG["df-code-review integrated pass, once per chain"]
```

## Bounded re-review shapes

The multi-round review loops are gone, but resampling is not, because a review pass is a sample and rerunning it catches real findings. What blew up was the coupling. These are the five re-review forms that survive, each with an explicit bound.

```mermaid
flowchart LR
  subgraph S1["Delta verification, df-prd-challenge and df-code-review"]
    A1["remediation lands"] --> A2["re-check changed sections only"] --> A3["verdict per finding, regression sweep of the remediation prose"]
  end
  subgraph S2["Fresh eyes at the cap, df-implement"]
    B1["fix rounds resume the implementer"] --> B2["late rounds, fresh implementer on a stronger model"] --> B3["adjudication at the cap, never another loop"]
  end
  subgraph S3["One verdict per version"]
    C1["changed head SHA"] --> C2["exactly one new pass"]
    C3["unchanged artifact"] --> C4["no new pass"]
  end
  subgraph S4["Flag-flip integrated pass, once per chain"]
    D1["flag-flip PR"] --> D2["one budgeted pass over the PR chain, the flag-removal diff, and dead code"]
  end
  subgraph S5["Second opinion, Standard lane"]
    E1["operator invokes, one-shot"] --> E2["decorrelated draw, other model family or different rubric"] --> E3["lead-adjudicated, budget-counted, gates unchanged"]
  end
```
