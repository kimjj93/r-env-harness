# r-env-harness

**Harness Engineering for Statistical Programming** — a working reference
implementation of a human-in-the-loop, agent-driven workflow for building
**reproducible, validated R environments** with the evidence trail a regulated
submission requires.

The premise: AI agents do the work autonomously on branches, an unattended
research loop fine-tunes proposals in the background using measured metrics,
and a human only ever has to do one thing — **approve or deny a pull request**.

---

## The idea in one paragraph

Everything an agent needs to know, everything it learns, and everything it
proposes is a **plain-text file under version control**. The agent's own
operating instructions (`AGENTS.md`, `skills/**/SKILL.md`) are reviewed through
the same pull request process as the code. That makes the AI's behaviour
diffable, auditable, and reversible — which is exactly what a regulated
environment demands, and what a chat transcript can never provide.

---

## The six-step loop

| Step | What happens | Who does it | Review cost |
|---|---|---|---|
| 1 | Agents read `AGENTS.md` + `skills/**/SKILL.md` | AI | none |
| 2 | Agent branches and works — **never on `main`** | AI | none |
| 3 | CI gates run; a second AI posts an advisory review | AI | none |
| 4 | **Human approves or denies the PR** | **Human** | *the only mandatory step* |
| 5 | Merged commits feed back into the instructions | AI proposes, human approves | occasional |
| 6 | Unattended research explores upgrades nightly | AI | **zero** — batched to 1 PR/week |

Steps 1–3 and 6 cost you nothing. Step 4 is the point of the whole system.

---

## Why the human gate cannot be bypassed

This is enforced in three independent layers, because a promise in a
documentation file is not a control:

1. **Repository ruleset on `main`** — direct pushes and force pushes blocked,
   pull request required, one approving review required, stale approvals
   dismissed on new commits, CODEOWNERS review required, and the
   `env-validate` + `skills-lint` checks must pass.
2. **`CODEOWNERS`** — every path is owned, so every PR needs a named human.
3. **Workflow design** — AI reviews are posted as GitHub `COMMENT` reviews,
   which **cannot** satisfy an approval requirement. `skills-lint` greps the
   whole repository to prove no workflow can self-approve or self-merge.

Layer 3 matters most. An agent asked to "get this merged" cannot comply even if
it wants to, because the capability was never granted.

---

## The example use case: R environment validation

Two pinning strategies run side by side so the harness can measure them against
each other rather than assert which is better:

| | **Track A** | **Track B** |
|---|---|---|
| Method | `renv` + dated Posit Package Manager snapshot | Nix via [`{rix}`](https://github.com/ropensci/rix) |
| Base | `rocker/r-ver:4.4.2`, pinned by **digest** | `nixos/nix`, pinned by digest |
| Pins | R + R packages | R + packages + OS + system libraries |
| Familiarity | The pharma-standard path | Stronger, less familiar to reviewers |
| Caveat | OS drift is not captured by the lockfile | ~5% of CRAN unavailable; slow without Cachix |

The payload is a pharmaverse ADaM pipeline (`admiral`, `pharmaversesdtm`,
`dplyr`) producing ADSL and ADAE. It exists so the question stops being "did
the environment change?" and becomes **"what did the change do to the
numbers?"**

### The four-layer delta

`harness/image_delta.R` answers that question in the form the PR reviewer needs:

1. **Digest** — did the image change at all?
2. **Base / OS** — Ubuntu release, glibc, system libraries.
3. **R packages** — added, removed, version-changed.
4. **Results** — do ADSL/ADAE checksums still match, and if not, what is the
   maximum absolute numeric deviation?

Six verdicts are possible. Only `FAIL_DEVIATION` and `FAIL_NONDETERMINISM` fail
the build — a qualified, in-tolerance upgrade must be allowed to pass, or every
legitimate change would need a CI override and the gate would be routinely
disabled.

`FAIL_NONDETERMINISM` is the interesting one: the environment did *not* change
but the results did. That means something in the pipeline is unpinned.

### Validation methodology

Three decoupled phases, adopted from `pfizer-rd/rvalidation-refactored`. Each
phase communicates only through on-disk artifacts, so each is independently
auditable:

```
Phase 1  build fixtures    → committed .rda baselines + environment metadata
Phase 2  run-validation.R  → test-results.xml (JUnit), exit 1 on failure
Phase 3  render report     → PQ report, reads the XML only, never re-runs tests
```

Comparison is **strict when it can be**: bit-for-bit equality is demanded only
when the R version and every declared critical package match the fixture.
Otherwise the comparison is tolerant, and the observed deviation is recorded
rather than hidden by a pass.

---

## Containers are the unit of immutability

The lockfile says what *should* be installed; the image is what *actually ran*.

- Base images are pinned **by digest**, not by tag — a tag can be re-pushed
  underneath you, which is precisely the silent OS drift that makes "we used
  rocker 4.4.2" insufficient as submission evidence.
- Images are published to GHCR **only after a human merge**, tagged by commit
  SHA, never `latest`.
- The resulting digest is appended to an **append-only ledger branch**,
  `evidence/images` — the bridge between *the code a human reviewed* and *the
  bits that ran*. It is not committed to `main`, for two reasons: pushing to
  `main` would violate the repository's own first rule (the ruleset blocks it,
  as it should), and opening a PR for it would loop forever — merging the PR
  publishes an image, which locks a digest, which opens a PR. The copy of
  `images.lock.json` on `main` therefore records the *approved* environment and
  moves only through review; the ledger records every build.
- Images are cosign-signed (keyless) with an SBOM and build provenance.
- **Validation runs inside the image**, not beside it. Evidence produced by a
  runner that merely has similar packages installed is not evidence.
- `.devcontainer/` points at the same digest, so local development is
  bit-identical to CI.

Digest pinning has a real cost: security updates no longer arrive on their own.
That is the correct trade-off for submission work, and the harness compensates
by making the base digest itself a research candidate the nightly loop tracks.

---

## Workflows

| Workflow | Trigger | What it does | Human load |
|---|---|---|---|
| `env-validate.yml` | every PR | Builds both tracks, runs PQ inside the image, computes the four-layer delta, scans package risk, posts a sticky comment | none — a gate |
| `skills-lint.yml` | every PR | Proves the governance rules are intact and no workflow can self-approve or self-merge | none — a gate |
| `publish-image.yml` | merge to `main` | Signed, SBOM'd GHCR push; commits the digest to the lock file | none |
| `agent-race.yml` | dispatch / `agent-race` label | Fans one task out to competing agents with different strategy briefs, then ranks them | none |
| `ai-review.yml` | agent PR opened | Advisory `COMMENT` review — cannot approve | none |
| `nightly-research.yml` | nightly cron | Explores candidate upgrades; writes to the `research/telemetry` branch | **zero** |
| `weekly-proposal.yml` | Monday cron | Aggregates the week and opens **at most one** PR | **~1 review/week** |
| `skills-drift.yml` | push to `main` | Detects instructions that no longer match reality | occasional |
| `learning-promote.yml` | every PR / Monday cron | Validates the learning log; proposes a lesson for the contract once it has recurred | rare |

### The repository remembers its own mistakes

`skills-drift.yml` catches *mechanical* drift — a skill referencing a path that
no longer exists. It cannot catch a rule that is present, accurate, and still
misread every time somebody works here. That knowledge only exists in what the
work taught us, so it is written down.

`evidence/learnings.jsonl` is an append-only log of observations, classified by
whether the gap was **context**, **instruction**, **workflow**, or **failure**
(the four signal types from Martin Fowler's [feedback flywheel][ff]). Agents are
instructed to append to it (`AGENTS.md` §10); it costs one command.

Recording is cheap on purpose. **Promotion is not.** `learning-promote.yml`
surfaces a lesson in `AGENTS.md` only once it has been recorded **twice**, on the
reasoning that one occurrence is an anecdote and two in different places is a
property of how this repository is built. Without that threshold the contract
grows until agents skim it, and a skimmed contract governs nothing.

The seeded log already contains two lessons that recurred during construction —
the same metric field-name mismatch made in two different scripts, and two gates
that degraded silently rather than failing.

[ff]: https://martinfowler.com/articles/reduce-friction-ai/feedback-flywheel.html

### Measuring the agents, not just the environment

The 26 telemetry fields per research run all describe the *environment*. None of
them says whether an agent reading `AGENTS.md` could do the job.
`harness/agent_metrics.R` closes that gap from data the repository already
produces, and reports it in the weekly proposal:

- **first-pass acceptance** — share of PRs whose *first* gate run passed
- **iteration cycles** — gate runs needed before the first green
- **never green** — opened, iterated, still failing

Human-authored PRs are measured alongside as a control: if agents need three
attempts where humans need one, the contract is underspecified; if both need
three, the gate is flaky and rewriting the contract would treat the wrong cause.

Deliberately **not** measured: lines changed, commits, time to first push. Volume
is not the constraint here — review capacity is.

### The research loop is the autopilot

`nightly-research.yml` runs candidate environments — new snapshot dates,
nixpkgs pins, base digests — through the full build → PQ → delta pipeline every
night, with `continue-on-error` set deliberately: **a failing candidate is data,
not an incident.** Even a candidate that fails to build emits a metrics row,
because "this does not build" is a finding worth keeping.

Nothing it produces targets `main`. Findings append to
`evidence/metrics/metrics.jsonl` on the `research/telemetry` branch, so hundreds
of experiments cost exactly zero review time.

`weekly-proposal.yml` then turns a week of that into **at most one** pull
request, with a generated `PROPOSAL.md` that answers, without the reviewer
opening anything else: what changed, what it did to the results, how much
tolerance headroom was consumed, what was rejected and why, and the references
justifying it.

**If nothing beat the incumbent, it opens nothing.** A quiet week is a correct
outcome, not a broken pipeline.

### Competing agents

This repository has three assignable coding agents — Copilot, Anthropic, and
OpenAI — so `agent-race.yml` runs a genuinely **multi-vendor** race rather than
one model prompted three ways. That matters: same-model racers produce
correlated answers, and correlated answers do not stress-test a decision.

Each racer gets a different strategy brief (*minimise churn* / *prefer newest* /
*optimise build time*), so the race surfaces the real trade-off instead of three
similar PRs. `harness/scoreboard.R` ranks them on **CI artifacts only, never on
what the PR description claims** — the failure mode of a multi-agent race is
rhetorical, where the most confident writer wins.

Failing validation is disqualifying, not a scoring penalty.

---

## Getting started

> **Running this on a team?** [`docs/OPERATING-MANUAL.md`](docs/OPERATING-MANUAL.md)
> is the practical companion to this file: what you do each week, how to read a
> failure, and the failure modes we have already hit.


```bash
gh repo clone kimjj93/r-env-harness && cd r-env-harness

# Read the contract first — it is what the agents read.
less AGENTS.md

# Build Track A locally
docker build -f env/renv/Dockerfile -t r-env-harness:local .

# Run the validation suite inside the image
docker run --rm -v "$PWD/artifacts:/project/artifacts" \
  r-env-harness:local Rscript /project/validation/run-validation.R
```

To start an agent race:

```bash
gh workflow run agent-race.yml -f task="Advance the PPM snapshot to 2025-04-01"
```

### One-time setup: `HARNESS_BOT_TOKEN`

Before the first race, create a PAT and store it as a repository secret:

```bash
gh secret set HARNESS_BOT_TOKEN   # paste a PAT with repo (or Issues + PRs) scope
```

This is **required**, not optional. GitHub refuses to assign a coding agent
using `GITHUB_TOKEN` — `replaceActorsForAssignable` returns `FORBIDDEN` for App
installation tokens — and `copilot-swe-agent` is not even visible to that token.
The same secret also makes workflow-opened PRs trigger the validation gate
automatically. See [`GOVERNANCE.md`](GOVERNANCE.md) for the detail.

Without it the harness still works; you just have to close-and-reopen
agent-opened PRs by hand, and `agent-race` will refuse to run.

---

## Repository map

```
AGENTS.md              the contract every agent reads — start here
GOVERNANCE.md          who may merge, and what AI may never do
skills/                vendor-neutral capability specs (SKILL.md)
env/renv/              Track A: lockfile, digest-pinned Dockerfile, PPM pin
env/nix/               Track B: rix generator, default.nix, Nix image
env/images/            images.lock.json — the APPROVED pin (ledger: evidence/images)
analysis/              the ADaM payload (ADSL, ADAE)
validation/            three-phase PQ framework, fixtures, testcases
harness/               delta engine, manifests, metrics, scoreboard
harness/research/      candidates.yml, aggregate.R, propose.R
evidence/              committed audit trail: metrics, manifests, proposals
```

---

## Honest limitations

- **This is a methodology demonstration, not a validated system.** Using it for
  an actual submission requires your own IQ/OQ documentation and QA sign-off.
- **Fixtures must be generated before the gate means anything.** Until Phase 1
  baselines exist on `main`, the delta engine reports
  `BASELINE_ESTABLISHED` rather than comparing.
- **Track B is `continue-on-error` until proven stable.** Some CRAN packages are
  unavailable in nixpkgs; those candidates are recorded as `unsupported` rather
  than worked around.
- **Nix builds are slow without the `rstats-on-nix` Cachix cache.**
- **Agent availability varies by account and plan.** A racer that cannot be
  assigned is skipped with a warning; a two-way race is still a race.
- **`{riskmetric}` is being succeeded by `{val.meter}`** by the R Validation
  Hub; `skills/package-risk/SKILL.md` notes the migration path.
- **The tolerances shipped here are illustrative.** Real tolerances are a
  statistical and clinical judgement, not a default.

---

## Reference basis

- Posit — *Containerization in Posit Connect: stable, repeatable deployments*
- [`philbowsher/Open-Source-in-New-Drug-Applications-NDAs-FDA`](https://github.com/philbowsher/Open-Source-in-New-Drug-Applications-NDAs-FDA)
  — submissions cite exact R and package versions
- [`ropensci/rix`](https://github.com/ropensci/rix) — dated nixpkgs pinning
- [`pfizer-rd/rvalidation-refactored`](https://github.com/pfizer-rd/rvalidation-refactored)
  — three-phase PQ, strict/tolerant criteria, JUnit output
- [`nbafrank/uvr`](https://github.com/nbafrank/uvr) — fast lockfile resolution;
  noted as a candidate third track
- R Validation Hub [`{riskmetric}`](https://github.com/pharmaR/riskmetric),
  `{renv}`, `rocker-versioned2`, Posit Package Manager dated snapshots

---

## License

MIT — see [`LICENSE`](LICENSE).
