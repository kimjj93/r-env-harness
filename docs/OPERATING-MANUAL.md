# Operating manual

For the person who has to run this on a Monday morning.

`README.md` explains what the harness is. `GOVERNANCE.md` explains why the human
gate holds. This document explains **what you actually do**, what the failure
modes look like, and how to tell a real problem from noise.

---

## 1. Your weekly job

One PR. That is the design target, and in a normal week it is the whole job.

Monday morning `weekly-proposal` opens at most one PR titled
`proposal: <candidate>`, labelled `environment-proposal` and `needs-human-review`.
Read it in this order:

1. **`PROPOSAL.md` §2 — effect on results.** This is the only section that
   answers the question that matters: *did the numbers move?* Everything else
   is context.
2. **Tolerance utilisation.** Pass/fail hides risk. An assertion passing at 0.99
   utilisation is one upstream change away from failing and is worth knowing
   about *before* you merge, not after.
3. **Package churn and the risk scan.** Did anything new arrive that you would
   not have chosen deliberately?
4. **The delta report artifact.** Four layers: digest, OS, R packages, results.

Then approve or close. If you close it, say why in a comment — the research loop
does not read your mind, and next week it will propose the same thing again
unless you record the reason.

**A quiet week is a real answer.** If no candidate beat the incumbent, the
workflow opens nothing. Silence means "nothing was worth your attention", not
"the loop is broken". Confirm with:

```bash
gh run list --workflow weekly-proposal.yml --limit 1
```

A green run with no PR is the quiet-week path working correctly.

---

## 2. What runs without you

| When | What | Touches `main`? |
|---|---|---|
| Every PR | `env-validate` (both tracks), `skills-lint` | no — gates |
| Agent PR opened | `ai-review` (advisory `COMMENT`) | no |
| Nightly | `nightly-research` → `research/telemetry` | **no** |
| Merge to `main` | `publish-image` → `evidence/images` | **no** |
| Merge to `main` | `skills-drift` | opens a PR at most |
| Monday | `weekly-proposal` | opens ≤1 PR |
| On demand | `agent-race` | opens issues + agent PRs |

Two of these deserve emphasis, because they are what keeps the review burden at
one PR per week:

- **`nightly-research` never targets `main`.** It appends to a telemetry branch.
  It can run every night forever and generate zero review burden. A failing
  candidate is *data*, not an incident — that is why the matrix runs
  `continue-on-error`.
- **`publish-image` never commits to `main` either.** It appends to the
  append-only `evidence/images` ledger branch, which maps each git SHA to the
  immutable image digest built from it. This is the bridge between "the code we
  reviewed" and "the bits that ran", and it is why it must not be a PR: a PR
  would merge, which would publish a new image, which would open a PR.

---

## 3. One-time setup

```bash
gh secret set HARNESS_BOT_TOKEN    # PAT: repo scope, or Issues + PRs (fine-grained)
```

Do this before your first race. It is not optional, and the reason is a hard
platform constraint rather than a preference:

- `replaceActorsForAssignable` — the mutation that assigns an issue to a coding
  agent — returns `FORBIDDEN` for **GitHub App installation tokens**, and
  `GITHUB_TOKEN` is one. No `permissions:` block can change this.
- `suggestedActors` returns a *different set of agents per token*. Under
  `GITHUB_TOKEN`, `copilot-swe-agent` is not merely unassignable — it is
  invisible.
- Separately, PRs opened using `GITHUB_TOKEN` **do not trigger workflows**
  (GitHub's recursion prevention), so agent-opened PRs show *no checks at all*.

That last one is worth internalising, because it looks benign and is not:

> **A PR with no checks is not a PR that passed quietly. It is the opposite.**

Because the checks are *required*, a missing check counts as unsatisfied and the
PR is **blocked**. The failure mode is fail-closed, which is the right direction —
but if you see a proposal PR with no checks, the fix is the secret above, not
merging it.

---

## 4. Running an agent race

```bash
gh workflow run agent-race.yml \
  -f task="Reduce the Track A image below 1200 MB without changing any package version" \
  -f racers="copilot,anthropic,openai"
```

Each racer gets its own issue, its own strategy brief, its own branch and its own
draft PR. When they finish, `scoreboard.R` ranks them on recorded metrics and
posts a comparison. **You still merge the winner.**

Write the task as a *constraint*, not a wish. `"Reduce image size"` invites an
agent to delete a validation step. `"Reduce image size without changing any
package version in renv.lock and without weakening any validation assertion"`
does not. The agents are graded against the same gates as everyone else, so a
racer that weakens a gate to win will fail `skills-lint`.

If a racer cannot be assigned, its issue is closed automatically — an unassigned
racer issue is litter, because nothing will ever work on it.

---

## 5. Changing the rules

`AGENTS.md` and `skills/**/SKILL.md` are the AI's instructions, and they are
version-controlled for the same reason the code is: so a change to them shows up
in a diff and gets reviewed.

Change them exactly like code — branch, PR, review. `skills-lint` gates them, and
`ai-review` flags any diff touching them as the highest-consequence change in the
repository, because it is.

`skills-drift` proposes such changes automatically after merges to `main`, when
recent accepted commits contradict what the docs claim. It opens a PR. It never
commits.

---

## 6. Changing what "correct" means

Fixtures are the answer key. Changing one changes the answer, so it is the single
most consequential edit in the repository — and it is deliberately awkward.

**Never regenerate fixtures on your laptop.** Use:

```bash
gh workflow run build-fixtures.yml
```

This builds the validated image in CI, regenerates the baselines inside it,
self-validates, and opens a PR with a provenance table.

The reason is worth stating, because it cost real debugging time to learn:

`det()`, `eigen()` and `solve()` are computed by **BLAS/LAPACK, not by R**.
Fixtures generated in a locally *emulated* amd64 image — anything on Apple
Silicon — differ in the last bits from a native runner. Worse, an emulated
container reports the **same** `platform`, `arch` and BLAS strings as a native
one, so no amount of introspection can detect it. The defence is provenance, not
fingerprinting: build fixtures where you can prove the hardware.

---

## 7. Reading a failure

| Symptom | Meaning | Action |
|---|---|---|
| PQ fails, `strict=N, tolerant=0` | environment identical, numbers moved | **investigate** — a real regression |
| PQ fails, assertions `tolerant` | environment changed as expected | read max deviation vs tolerance |
| PR shows no checks | opened by `GITHUB_TOKEN` | set `HARNESS_BOT_TOKEN`; or close/reopen |
| Track B `unsupported` | package unavailable in nixpkgs | expected for ~5% of CRAN; not a failure |
| Nightly candidate red | candidate is bad | none — that is the loop working |
| `agent-race` fails immediately | no agent assignable | set `HARNESS_BOT_TOKEN` |
| Proposal PR touches only `evidence/` | should be impossible now | see §8 |

The first row is the one to take seriously. "Same R, same critical packages, same
numeric backend — different numbers" means something outside the declared
critical set is affecting results, i.e. **the critical-package declaration is
incomplete**. We have already seen this once: candidate `ppm-2025-07-01` failed
two assertions at 1.42e-14 while reporting `pq_strict=20, pq_tolerant=0`. Widen
the `@section Critical Packages:` block until the mismatch is explained.

---

## 8. Failure modes we have already hit

Recorded because each looked healthy from the outside. A gate that is silently
not running is worse than a gate that is loudly broken.

- **A proposal that proposed nothing.** The first real weekly run opened a PR
  whose diff touched only `evidence/`. It spent the week's single review on
  nothing. Four separate defects combined; the dangerous one was that an
  un-appliable candidate could win the ranking and then abort the week, so a
  genuinely good candidate was never proposed. The workflow now refuses to open
  a PR whose staged diff touches nothing outside `evidence/`.
- **An error handler killed by the error it handled.** `bot_id()` ended in
  `grep`, which exits 1 when the login is absent; under `set -euo pipefail` that
  terminated the step *before* the "skip this racer" branch written directly
  below it could run. If you write a fallback path in a `set -e` shell script,
  test it by actually triggering it.
- **`.validation_env_meta` silently vanishing.** `as.list(env)` drops
  dot-prefixed names. Every assertion quietly degraded from strict to tolerant
  while still reporting a clean pass — the worst possible outcome, since the
  suite looked green while checking nothing.
- **A flat tolerance applied across five orders of magnitude.** `1e-12` against
  quantities from 5.7e-3 to 9.4e1 is 2e-10 relative on one and 1e-14 on another.
  Tolerances are now derived (`eps · |x| · κ · safety`) with a floor and a
  **fatal hard cap**, because a derivation fed absurd inputs produces an absurd
  number.

---

## 9. What this is not

This is a **methodology demonstration**, not a validated system. Using it for an
actual regulatory submission requires your own IQ/OQ documentation, your own QA
sign-off, and your own SOPs. The harness produces evidence; it does not produce
compliance.
