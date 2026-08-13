---
name: research-loop
description: Run the autonomous nightly research cycle that tests candidate environment upgrades in the background, records metrics to a telemetry branch without opening pull requests, and batches the best finding into a single weekly proposal with evidence. Use when adding candidates, tuning the loop, or preparing the weekly proposal.
---

# Skill: Research Loop

## Purpose

Explore candidate environment upgrades continuously and autonomously, then spend
the human's review budget on **one** well-evidenced proposal per week.

The loop's real product is not the code change — it is the *evidence* that the
change is safe.

## Two-speed design

| | Nightly | Weekly |
|---|---|---|
| Trigger | cron, nightly | cron, Monday |
| Writes to | `research/telemetry` branch | a PR against `main` |
| Human load | **zero** | one review |
| Purpose | gather evidence | request a decision |

Separating these is what makes the automation tolerable. Hundreds of experiments
cost nothing in attention; only conclusions reach a person.

## Nightly: gather

Read the use case's `candidates.yml` — the search space:

```yaml
candidates:
  - id: ppm-2026-07-01
    track: renv
    dimension: ppm_snapshot     # change ONE dimension per candidate
    value: "2026-07-01"
  - id: nixpkgs-2026-07-01
    track: nix
    dimension: nixpkgs_date
    value: "2026-07-01"
  - id: base-digest-bump
    track: renv
    dimension: base_digest
    value: "sha256:..."
```

For each candidate: build → run PQ inside the image → generate the four-layer
delta → riskmetric scan → append a metrics row.

Rules:

- **`continue-on-error: true` is mandatory.** A failing candidate is *data*. The
  loop's job is to discover which upgrades break things, cheaply, at night.
- **One dimension per candidate.** Two simultaneous changes produce an
  uninterpretable delta.
- **Never target `main`.** Telemetry goes to `research/telemetry` only.
- **Never open a PR from the nightly job.**

## Metrics schema

One JSON object per run, appended to `evidence/metrics/metrics.jsonl`:

```json
{
  "timestamp": "2026-08-12T03:00:00Z",
  "candidate_id": "ppm-2026-07-01",
  "track": "renv",
  "dimension": "ppm_snapshot",
  "commit": "abc123",
  "image_digest": "sha256:...",
  "base_digest": "sha256:...",
  "build_seconds": 412,
  "image_size_mb": 1840,
  "package_count": 214,
  "pq_passed": 18, "pq_failed": 0, "pq_skipped": 0,
  "pq_strict": 12, "pq_tolerant": 6,
  "max_abs_deviation": 1.2e-14,
  "result_checksums": {"adsl": "...", "adae": "..."},
  "riskmetric_min": 0.81,
  "delta_churn": 7,
  "tracks_agree": true,
  "verdict": "PASS_WITH_CHANGES",
  "status": "success"
}
```

Append-only. Never rewrite history — a corrected row is a new row.

## Weekly: propose

1. Aggregate the week's telemetry.
2. Filter to candidates that passed **every** gate: PQ green, no
   `FAIL_DEVIATION`, no unexplained result change, no high-risk new package.
3. Rank survivors: result stability first, then PQ headroom (`max_abs_deviation`
   far from tolerance), then low delta churn, then build time.
4. If the best survivor does not beat the incumbent, **open nothing**. Silence is
   a valid and valuable output; a proposal every week regardless of merit trains
   reviewers to rubber-stamp.
5. Otherwise open exactly one PR with `PROPOSAL.md`:
   - what changes, in one sentence
   - metrics table: candidate vs. incumbent, with the deltas
   - the full four-layer environment delta
   - riskmetric scores for anything new
   - PQ strict/tolerant breakdown with max observed deviations
   - **citations**: release notes, NEWS, CRAN pages, issues
   - what a reviewer should check first
   - what was rejected this week and why

## Rules

- Every claim cites a metrics row or an external source. No unmeasured assertions.
- Report rejected candidates too — negative results are how the team learns which
  upgrades are risky.
- Never propose a change that failed PQ, however attractive the other metrics.
- Keep the candidate list small (3–4) at first; the matrix multiplies across two
  tracks and consumes Actions minutes.

## References

- `AGENTS.md` §4 — evidence standards
- the use case's delta skill — what a delta report must contain
- the use case's qualification skill — what "passing" means
