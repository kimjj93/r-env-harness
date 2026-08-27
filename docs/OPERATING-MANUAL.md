# Operating manual

For the person who has to run this on a Monday morning.

`README.md` explains what the harness is. `GOVERNANCE.md` explains why the human
gate holds. This document explains **what you actually do**, what the failure
modes look like, and how to tell a real problem from noise.

---

## 1. Your weekly job

One PR. That is the design target, and in a normal week it is the whole job.

Monday morning `weekly` opens at most one PR titled
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
gh run list --workflow weekly.yml --limit 1
```

A green run with no PR is the quiet-week path working correctly.

---

## 2. What runs without you

| When | What | Touches `main`? |
|---|---|---|
| Every PR | `env-validate` (both tracks), `lint` | no — gates |
| Agent PR opened | `ai-review` (advisory `COMMENT`) | no |
| Nightly | `nightly-research` → `research/telemetry` | **no** |
| Merge to `main` | `publish-image` → `evidence/images` | **no** |
| Merge to `main` | `weekly` | opens a PR at most |
| Monday | `weekly` | opens ≤1 PR |
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
racer that weakens a gate to win will fail `lint`.

If a racer cannot be assigned, its issue is closed automatically — an unassigned
racer issue is litter, because nothing will ever work on it.

### You must approve CI on each racer PR

Agent PRs show **no checks** until you click **"Approve and run workflows"**.
GitHub treats a coding agent as an external contributor, and its workflow runs
sit in `action_required` until a human releases them.

Do not read "no checks" as "passed". Because the checks are required, the PR is
blocked either way — but the evidence you need in order to judge the race does
not exist yet.

This is the one place the loop is genuinely not unattended, and it is worth the
cost: workflows can read secrets, so this is the last checkpoint before
AI-written code runs with your repository's credentials.

`close/reopen` does **not** clear it (verified). To get build and PQ evidence for
an agent branch without granting it CI:

```bash
gh workflow run env-validate.yml --ref <agent-branch>
```

You are the triggering actor, so it runs immediately.

---

## 5. Changing the rules

`AGENTS.md` and `skills/**/SKILL.md` are the AI's instructions, and they are
version-controlled for the same reason the code is: so a change to them shows up
in a diff and gets reviewed.

Change them exactly like code — branch, PR, review. `lint` gates them, and
`ai-review` flags any diff touching them as the highest-consequence change in the
repository, because it is.

`weekly` proposes such changes automatically after merges to `main`, when
recent accepted commits contradict what the docs claim. It opens a PR. It never
commits.

---

## 6. Changing what "correct" means

Fixtures are the answer key. Changing one changes the answer, so it is the single
most consequential edit in the repository — and it is deliberately awkward.

**Never regenerate fixtures on your laptop.** Use:

```bash
gh workflow run usecase-build-fixtures.yml
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
| PR shows no checks, workflow-opened | opened by `GITHUB_TOKEN` | set `HARNESS_BOT_TOKEN`; or close/reopen |
| PR shows no checks, agent-opened | runs in `action_required` | click **Approve and run workflows** |
| Track B `unsupported` | package unavailable in nixpkgs | expected for ~5% of CRAN; not a failure |
| Nightly candidate red | candidate is bad | none — that is the loop working |
| `agent-race` fails immediately | no agent assignable | set `HARNESS_BOT_TOKEN` |
| Proposal PR touches only `evidence/` | should be impossible now | see §8 |

The first row is the one to take seriously: "same R, same critical packages,
same recorded backend — different numbers."

We saw it twice, and the first diagnosis was **wrong**, which is worth recording
because the wrong answer was the plausible one. Candidate `ppm-2025-07-01` failed
two assertions at 1.42e-14 with `pq_strict=20, pq_tolerant=0`, and we concluded
the critical-package declaration must be incomplete. Then an agent race produced
the *identical* deviation from a change that touched only the Dockerfile — no
package moved at all. That ruled the package theory out.

The real cause was **BLAS thread count**. `rocker/r-ver` links R against threaded
OpenBLAS, which splits reductions across threads and sums the partials, so the
last bits depend on how many threads it chose — decided at runtime from the host
core count, and recorded in no lockfile, digest or manifest. Measured on one
fixed image digest, varying nothing but the thread count:

```
threads=1  svd_1=1.02006622600000116563e+03
threads=2  svd_1=1.02006622600000127932e+03
threads=4  svd_1=1.02006622600000207512e+03
threads=8  svd_1=1.02006622600000184775e+03
```

Every value differs.

**And pinning threads was still not enough.** Fixtures regenerated with threads
pinned self-validated at deviation 0 in the run that produced them, then failed
at 1.42e-14 in the *next* run on main — same commit, same image digest, different
runner. OpenBLAS also selects a *kernel* at runtime from the detected CPU, and
GitHub's runner fleet is heterogeneous. One digest, one thread, kernel varied:

```
HASWELL      solve_11=3.14491662711728885843e-03
SANDYBRIDGE  solve_11=3.14491662711728929211e-03
NEHALEM      solve_11=3.14491662711728885843e-03
```

Both Dockerfiles now pin `OPENBLAS_NUM_THREADS=1` **and** `OPENBLAS_CORETYPE`,
and both are part of the recorded backend identity, so a future unpinned
environment is reported as an environment change rather than a numeric mystery.
Verified afterwards: three independent runs on separate runners, all
`strict=20, tolerant=0, max_abs_deviation=0`.

⚠️ Forcing a kernel the CPU cannot execute **hangs** rather than failing
cleanly. Pick for the oldest CPU in your fleet; override with
`--build-arg OPENBLAS_CORETYPE=NEHALEM` if you need to.

The general lesson generalises past BLAS: **when results move but the recorded
environment does not, suspect something real that you are not recording yet.**
Widening the critical-package list is one hypothesis, not the conclusion.

It is also worth noticing *how* this was found. A container image is not
sufficient for numerical reproducibility. A digest pins the bits on disk; it does
not pin the CPU that executes them, and an optimised BLAS is specifically
designed to behave differently on different CPUs. Anyone claiming
"reproducible because containerised" has not tested this.

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

These are recorded permanently in `evidence/learnings.jsonl`, not just here. This
section is prose a human wrote once; the log is a structured record that agents
append to as they work and that `weekly.yml` reads. When the same
lesson lands there twice, it is proposed for `AGENTS.md` automatically.

---

## 8a. Recording what the work taught you

If something cost you real time and was not obvious from reading the repository,
append it to the learning log before you finish:

```
Rscript harness/learnings.R add evidence/learnings.jsonl \
  signal_type=failure \
  recurrence_key=short-slug-naming-the-lesson \
  summary='one specific line' \
  detail='what happened, with the measurement if there was one' \
  root_cause='why it was possible' \
  target_artifact=AGENTS.md \
  source=pr:123
Rscript harness/learnings.R validate evidence/learnings.jsonl
```

The `recurrence_key` is the important field. **Reuse an existing key** when you
hit a lesson that is already recorded — that reuse is the entire mechanism by
which a repeated mistake becomes a rule. A new key for an old problem hides the
pattern and the lesson stays an anecdote forever.

You will not normally open a PR for this. Add the entry alongside the work that
taught it to you, in the same pull request.

**What you review, and how often.** `weekly.yml` opens a PR only when a
lesson crosses the threshold, which should be rare. It adds evidence to
`AGENTS.md`, never rule text — deciding whether a recurring mistake warrants a
hard rule in §1 is your judgement, made while reviewing that PR. If you decide it
does not, set `promoted` on the entries with your reason; they then retire from
the generated block and stop being proposed.

---

## 9. What this is not

This is a **methodology demonstration**, not a validated system. Using it for an
actual regulatory submission requires your own IQ/OQ documentation, your own QA
sign-off, and your own SOPs. The harness produces evidence; it does not produce
compliance.

---

## 10. Taking the harness to a different problem

The R environment work is the **example**, not the product. Everything at the
repository root is domain-independent and is meant to be lifted out.

### Extract

```bash
./tools/extract-template.sh ../my-harness
cd ../my-harness
```

The script copies the harness, drops the use case, writes a stub that satisfies
the contract, and then **verifies its own output** — the manifest must be
coherent, the boundary check must pass, and no trace of the old domain may
survive. If any of that fails the extraction aborts rather than handing you a
broken template.

### Implement five commands

| Verb | What it must do | Evidence it writes |
|---|---|---|
| `build` | materialise a candidate state | `evidence/build/<variant>-build.json` |
| `qualify` | prove that state correct | `evidence/qualify/<variant>-qualify.json` + JUnit |
| `delta` | compare against a baseline | `evidence/delta/<variant>-verdict.json` + `.md` |
| `candidates` | list what research may vary | JSON array on stdout |
| `apply` | write a candidate into the repo | exit 0 applied, 3 already current |

They can be written in any language. The harness invokes them as commands and
reads only the documented schema in `docs/schema/evidence.md`.

### The one field worth understanding

`margin_utilisation` — the largest fraction of any declared margin that a check
actually consumed.

A suite passing at `0.98` is one bad day from failing. A suite passing at
`0.001` has real headroom. **Both report "all checks passed"**, and only this
field tells them apart. It is why the scoreboard ranks a slower agent above a
faster one that scraped through.

If your domain has no meaningful notion of margin, report `null` — not `0`.
Zero claims perfect headroom it has not earned.

### Worked examples of the mapping

| Domain | `build` | `qualify` | `delta` | `margin_utilisation` |
|---|---|---|---|---|
| R environments (this repo) | build the container | run PQ inside it | four-layer image delta | observed deviation ÷ declared tolerance |
| SAS → R migration | render both programs | compare outputs to the SAS reference | which datasets differ, and how | numeric difference ÷ allowed difference |
| Statistical model pipeline | fit on pinned data | back-test against held-out results | parameter and prediction drift | drift ÷ acceptance band |
| Data ingestion | build the transform | row/column contracts + referential checks | schema and row-count diff | rejected rows ÷ allowed reject rate |

### Keep the boundary honest

```bash
./harness/check_boundary
```

Run it before every push. It fails if a harness file names a use case path or a
domain tool. There is exactly one exemption — `harness.yml` and the extractor,
whose job *is* to name the seam — and adding a second is how the separation
dies.

If the harness genuinely cannot express what you need, **add a capability verb
in its own pull request** and argue for it. Do not reach into harness code from
the use case; that lets the domain edit its own referee.
