# AGENTS.md — Contract for Autonomous Agents

This file is the **root contract** for every AI agent working in this repository.
It is deliberately vendor- and model-independent: no proprietary syntax, no
model-specific directives. Any agent — Copilot, Claude, Codex, or a human
reading it — must be able to follow it.

Vendor pointer files (`.github/copilot-instructions.md`, `CLAUDE.md`) exist only
to redirect here. They must never contain rules of their own.

---

## 0. What this repository is

A **harness** for supervised autonomous work: agents propose on branches, CI
produces evidence, an automated research loop tunes proposals, and a human
merges. The rules governing the agents are plain text under version control,
which makes the agents' own behaviour diffable and reviewable.

The harness is domain-independent. What it currently governs is declared in
`harness.yml` and lives entirely under the `usecase.root` directory it names.
Read that use case's own `AGENTS.md` **in addition to this file** — it carries
the rules that only make sense in its domain.

If it is not in git, it did not happen.

---

## 1. Non-negotiable rules

These are absolute. An agent that violates any of them has failed its task
regardless of the quality of its output.

1. **Never commit directly to `main`.** Always create a branch and open a pull
   request. This is enforced by a repository ruleset, but you must not attempt to
   work around it.
2. **Never merge a pull request.** Only a human may merge. You may not use
   `gh pr merge`, the merge API, auto-merge, or any equivalent.
3. **Never approve a pull request.** AI reviews must be posted as `COMMENT`.
   Submitting an `APPROVE` review is prohibited even if you believe the change is
   correct — approval is the human's sole signal of accountability.
4. **Never edit generated files by hand.** A file carrying a `GENERATED` banner
   has a generator. Change the generator, then regenerate. The use case lists
   which of its files are generated and by what.
5. **Never hand-edit committed baselines.** Reference fixtures are qualification
   evidence, not test inputs to be adjusted. Regenerate them through the
   documented procedure and explain why in the PR.
6. **Never weaken a gate to make a build pass.** Do not raise a tolerance,
   disable a test, add `continue-on-error`, or delete an assertion in order to go
   green. If a gate blocks you, the finding *is* the deliverable — report it.

   This rule bans a *motive*, not an edit. An acceptance criterion may legitimately
   be corrected, and the test that separates the two cases is:

   > Would this change still be correct if the test were currently passing?

   A tolerance derived from numerical analysis — the conditioning of the problem,
   the magnitude of the quantity, the precision of the arithmetic — is a criterion,
   and correcting it is legitimate even though it happens to unblock a build. A
   tolerance chosen because it is slightly larger than the deviation you happened
   to observe is a rationalisation, and is prohibited.

   When you change any acceptance criterion you must, in the same PR:
   - derive the new value from stated principles, showing the arithmetic;
   - report the observed deviation as a **percentage of the new criterion**, so a
     reviewer can see the margin rather than a bare pass;
   - state the hard cap the derivation can never exceed, and why the cap is safe
     for a reported clinical result.

   A derived criterion with no cap is an unbounded criterion. Always bound it.
7. **Never introduce a floating version.** No `latest` tags, no unpinned
   `install.packages()`, no undated repository URLs. Every dependency resolves to
   a fixed version, date, or digest.
8. **Never commit secrets, credentials, or patient data.** All clinical data in
   this repository is synthetic.

## 2. Branch and commit conventions

Branch names are prefixed by intent:

| Prefix | Purpose |
|---|---|
| `usecase/` | changes inside the use case the harness governs |
| `harness/` | tooling: dispatcher, metrics, scoreboard, learning log |
| `skills/` | changes to `AGENTS.md` or any `SKILL.md` |
| `research/` | outputs of the automated research loop |
| `race/<task>/<strategy>` | competing agent entries (see §6) |

A use case may declare finer prefixes of its own; check its `AGENTS.md`.

Commits follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`,
`build:`). One logical change per commit.

## 3. Definition of done

A pull request is complete only when **all** of the following hold:

- [ ] It targets a branch, not `main`, and the branch prefix matches the intent.
- [ ] Every variant declared in `harness.yml` was qualified, or the failure is
      explained and is the *point* of the PR.
- [ ] A delta report against the merge base is attached. "No change" is an
      acceptable and expected result — say so explicitly.
- [ ] A verdict from the schema in `docs/schema/evidence.md` is recorded for
      each variant, with the JUnit record attached.
- [ ] The PR body states what changed, why, what evidence supports it, and what
      the reviewer should look at first.
- [ ] Claims are backed by cited evidence — a metrics row, a test result, or a
      reference URL. Never assert an improvement you did not measure.
- [ ] Any additional checklist items in the use case's `AGENTS.md` are satisfied.

## 4. Evidence standards

Hold yourself to the bar of evidence someone else will be accountable for.

- **Measure, don't estimate.** "Build time improved" is meaningless without the
  before and after numbers, and both must come from `evidence/metrics/metrics.jsonl`.
- **Show the delta, including when it is empty.** A reviewer must be able to see
  that you checked, not infer it.
- **Distinguish strict from tolerant results.** If a comparison ran in tolerant
  mode, state the declared margin and the observed maximum deviation.
- **Cite upstream sources** when proposing a version bump: release notes, NEWS
  files, package index pages, or issue threads.
- **Record what you could not verify.** An honest "unsupported on this variant"
  is worth more than a guess.

## 5. Working across variants

`harness.yml` may declare several variants — independent implementations of the
same requirement, qualified side by side so they can be compared.

When you change one variant, state explicitly in the PR whether the others
agree, diverge, or are unsupported for that change. **Divergence between
variants is a finding worth reporting, not a bug to hide.** Two independent
implementations disagreeing is the cheapest signal you will ever get that one of
them is wrong.

## 6. Competing agents

Multiple agents may be dispatched on the same task, each on its own branch with a
different **strategy brief** (for example: minimise version churn; prefer newest
packages that still pass PQ; optimise build time). When racing:

- Stay in your lane. Implement *your* assigned strategy faithfully, even if you
  suspect another strategy is better. The comparison is the experiment.
- Emit metrics in the standard schema so the scoreboard can rank you objectively.
- Do not modify another agent's branch.
- Losing is a valid, useful outcome. Do not inflate results to win.

## 7. Proposing changes to the rules

You may propose changes to `AGENTS.md` and `skills/**/SKILL.md` — that is an
intended part of the loop. Requirements:

- Open a PR on a `skills/` branch. Never edit these files as a side effect of an
  unrelated change.
- Cite the merged commits or metrics that justify the revision.
- Keep the files vendor-neutral and human-readable.
- Rule changes that would weaken §1 will be rejected automatically.

## 8. Skills index

Harness skills — these apply whatever the use case:

| Skill | Use it when |
|---|---|
| [`research-loop`](skills/research-loop/SKILL.md) | running the autonomous research cycle |

Use-case skills live under the `usecase.root` named in `harness.yml` and are
indexed by that use case's own `AGENTS.md`. Read both indexes before starting.

## 9. Escalate instead of guessing

Stop and report rather than proceeding if: a gate fails for a reason you do not
understand; a change would require violating §1; committed baselines appear
inconsistent with what produced them; or the task is ambiguous enough that two
reasonable interpretations lead to materially different results.

A blocked task reported clearly is a success. Silently wrong output that nobody
knows is wrong is the worst possible outcome.
