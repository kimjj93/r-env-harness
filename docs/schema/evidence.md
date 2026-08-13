# Evidence schema (v1)

The harness ranks agents, aggregates research and writes weekly proposals
without knowing what is being validated. It can do that only because every use
case reports through the same small vocabulary.

This document is the contract. A use case that fills these fields honestly gets
the whole harness for free. A use case that invents its own field names gets a
scoreboard full of `NA`.

## Design rule

**Every field below is a question you can ask of any engineering work.** None
of them mention containers, packages, or R. If you find yourself wanting to add
`image_size_mb`, add `artifact_size_mb` instead and let your domain decide what
the artifact is. Domain detail belongs in `detail`, which the harness carries
but never interprets.

## `verdict.json`

Written by `delta`. One per variant. The single field the human gate cares
about.

| Field | Type | Meaning |
|---|---|---|
| `verdict` | enum | See below |
| `variant` | string | Which variant this describes |
| `baseline` | string | What it was compared against (usually a git SHA) |
| `summary` | string | One line a reviewer reads first |
| `report_path` | string | Human-readable report, markdown |

### Verdict values

| Value | Meaning | Merge implication |
|---|---|---|
| `PASS_IDENTICAL` | Nothing changed that affects results | safe |
| `PASS_EXPLAINED` | Something changed; every change is accounted for | review the explanation |
| `FAIL_DEVIATION` | A result moved beyond its declared margin | do not merge |
| `FAIL_NONDETERMINISM` | The same input produced different output twice | **do not merge** — this is the worst one, it means the evidence itself is unreliable |
| `FAIL_INFRASTRUCTURE` | The check could not complete | not a verdict about the change |
| `NO_EVIDENCE` | No artifact was produced | treat as failure |

`FAIL_NONDETERMINISM` is separated from `FAIL_DEVIATION` deliberately. A
deviation is a result you can argue about. Non-determinism means you cannot
argue about any result, because a rerun might say something else.

## `qualify.json`

Written by `qualify`. Alongside JUnit XML, which remains the authoritative
record.

| Field | Type | Meaning |
|---|---|---|
| `variant` | string | |
| `checks_passed` | integer | |
| `checks_failed` | integer | |
| `checks_skipped` | integer | |
| `margin_utilisation` | number 0–1 | Largest fraction of any declared margin actually consumed |
| `cost_seconds` | number | Wall time to qualify |
| `detail` | object | Domain-specific, harness-opaque |

### `margin_utilisation`

The most useful number in the schema, and the least obvious.

Every check declares how much slack it allows — a numeric tolerance, a latency
budget, an acceptable error rate. `margin_utilisation` is the largest fraction
of that slack any check actually used.

A suite that passes at `0.98` is one bad day from failing. A suite that passes
at `0.001` has real headroom. Both report "all checks passed", and only this
field tells them apart. It is why the harness ranks a slower agent above a
faster one that scraped through: it is measuring how close to the edge each
solution sits, which is the thing a pass/fail count hides.

If a use case has no meaningful notion of margin, report `null` — not `0`.
`0` claims perfect headroom; `null` correctly claims no measurement.

## `metrics.jsonl`

Append-only, one object per qualified build. The research loop's raw material.

| Field | Type | Meaning |
|---|---|---|
| `timestamp` | ISO 8601 | |
| `commit` | string | git SHA |
| `variant` | string | |
| `verdict` | enum | |
| `checks_passed`, `checks_failed` | integer | |
| `margin_utilisation` | number \| null | |
| `change_magnitude` | number | How much moved vs baseline, in whatever unit the domain counts |
| `cost_seconds` | number | Time to build and qualify |
| `artifact_size_mb` | number \| null | Size of what was produced, if it produces anything |
| `dimension` | string | Which research dimension was varied, or `none` |
| `candidate_id` | string | Which candidate value, or `adhoc` |

`change_magnitude` is intentionally unitless. For an environment it is packages
changed; for a data pipeline it might be rows differing; for a model it might be
parameters moved. The harness only ever compares it between two agents solving
the *same* task, so the unit cancels.

## Where evidence lives

```
evidence/
  qualify/<variant>-qualify.json      # latest per variant
  qualify/<variant>-junit.xml
  delta/<variant>-verdict.json
  delta/<variant>-delta.md
  metrics/metrics.jsonl               # append-only history
  learnings.jsonl                     # harness-owned, see AGENTS.md
```

Paths are fixed by the harness. Use cases write into them; they do not choose
them. That is what lets a scaffold workflow collect evidence from a domain it
has never heard of.
