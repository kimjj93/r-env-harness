# GOVERNANCE.md — Who Decides What

The purpose of this harness is to let AI do a large amount of work autonomously
**without** transferring decision authority away from a human. This file records
where that line sits and how it is enforced.

---

## 1. The line

| Action | AI | Human |
|---|---|---|
| Research candidate environments | ✅ autonomous | — |
| Build and test containers | ✅ autonomous | — |
| Run Performance Qualification | ✅ autonomous | — |
| Generate delta and risk reports | ✅ autonomous | — |
| Open a branch and a pull request | ✅ autonomous | — |
| Review a PR and post findings | ✅ `COMMENT` only | ✅ |
| **Approve a PR** | ❌ prohibited | ✅ **only** |
| **Merge to `main`** | ❌ prohibited | ✅ **only** |
| Publish a signed image from `main` | ✅ after human merge | — |
| Change these rules | ✅ may propose via PR | ✅ must approve |

The human is not in the loop to catch typos. The human is in the loop because
**accountability for a regulated environment cannot be delegated to a model.**

## 2. How it is enforced

Three independent layers, so no single misconfiguration removes the gate:

**Layer 1 — repository ruleset on `main`**
- direct pushes and force pushes blocked
- pull request required
- 1 approving review required
- stale approvals dismissed when new commits are pushed
- review from a CODEOWNER required
- `env-validate` and `skills-lint` must pass

**Layer 2 — CODEOWNERS**
`*  @kimjj93` — every path requires the owner's review.

**Layer 3 — least-privilege workflow permissions**
Every workflow declares an explicit `permissions:` block. No workflow is granted
merge capability, and none invokes `gh pr merge`. AI review workflows submit
`COMMENT`-type reviews, which by GitHub's design **cannot** satisfy an approval
requirement — so even a compromised or misbehaving agent cannot self-approve.

## 3. Why AI reviews are still worth having

AI reviewers cannot approve, but they front-load the reviewer's work: they check
the delta report for unexplained changes, verify PQ actually ran inside the
image, confirm claimed metrics match `metrics.jsonl`, and flag missing citations.
By the time a human opens the PR, the mechanical checking is done and the human
can spend their attention on the judgement call.

## 4. Managing reviewer load

Review burden is the scarcest resource in this system, so it is budgeted:

- The nightly research loop writes only to the `research/telemetry` branch and
  **never** opens a PR. Hundreds of experiments cost zero review time.
- Research findings are batched into **exactly one** proposal PR per week — and
  none at all if nothing outperformed the incumbent.
- Agent races auto-close losing entries, so only the winner reaches a human.

Target steady-state load: **one substantive review per week**, plus any
task-driven PRs the team initiates.

## 5. Self-authored pull requests

A required approval means you cannot approve your own PR. The repository admin is
therefore on the ruleset bypass list for PRs they author. Agent-authored PRs are
never eligible for bypass and always require explicit human approval.

## 6. Scope disclaimer

This repository demonstrates a **methodology**. It is not itself a validated
system. Using it to support an actual regulatory submission requires your
organisation's own IQ/OQ documentation, QA review, and sign-off under your
quality management system.
