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

### Residual risk: the "create and approve pull requests" setting

`build-fixtures`, `weekly-proposal` and `skills-drift` all need to *open* pull
requests. GitHub controls that with a single repository setting —
`can_approve_pull_request_reviews` — and, unhelpfully, the same switch governs
both **creating** and **approving**. It cannot be split. It is enabled here,
which means `github-actions[bot]` is technically able to submit an approving
review.

That does not open the gate, for three reasons that must all remain true:

1. **`require_code_owner_review: true`.** An approval only counts if it comes
   from a CODEOWNER. `github-actions[bot]` is not one and cannot be added to
   `CODEOWNERS`, so its approval never satisfies the requirement.
2. **`require_last_push_approval: true`.** The approval must come from someone
   other than whoever pushed the last commit — so a workflow cannot push a
   change and then bless it.
3. **`skills-lint` fails any workflow containing an approve call.** The
   capability exists at the platform level but is barred at the source level,
   and that check is itself a required status check.

If any one of those three is removed, this setting becomes a real hole. Treat
them as a unit: **a PR that weakens any of the three must be rejected unless it
also disables `can_approve_pull_request_reviews`.**

The stronger alternative is to create PRs with a GitHub App installation token
rather than `GITHUB_TOKEN`, which allows PR creation without granting approval
at all. That is the recommended hardening step before this pattern is used on
anything carrying real submission evidence.

### The `GITHUB_TOKEN` recursion limit, and why it is safe

GitHub deliberately suppresses workflow triggers caused by `GITHUB_TOKEN`, to
stop a workflow from starting itself forever. A consequence is easy to miss and
important to understand:

> **A pull request opened by a workflow using `GITHUB_TOKEN` does not trigger
> `env-validate`.** The PR shows *no checks at all*.

A PR displaying no checks looks superficially like a PR that passed quietly. It
is the opposite. Because `env-validate` and `Governance lint` are **required**
status checks, a missing check is treated as unsatisfied, and the PR is
**blocked** — the failure mode is fail-closed, which is the correct direction.
An unvalidated environment change cannot reach `main` this way.

Note this affects only PRs opened *by workflows*. Pull requests opened by a
coding agent during an `agent-race` come from a bot **user**, not from
`GITHUB_TOKEN`, so they are subject to a different control — described next.

### Agent pull requests require a human to approve running CI

This was originally documented here as "agent PRs trigger the gate normally".
That was **wrong**, and observing a real race corrected it.

When a coding agent opens a PR, GitHub treats it as an external contributor.
Its workflow runs are created but land in **`action_required`** and do not
execute until a human clicks **"Approve and run workflows"** on the PR. Observed
directly: both racer PRs in the first live race showed *no checks*, with
`env-validate` runs sitting at `conclusion=action_required`.

Two things follow, and they matter in opposite directions.

**It is not a bug, and you should not route around it.** Workflows can read
secrets and hold write permissions. Running unreviewed, agent-authored code in
that context, automatically, is precisely the supply-chain risk that
`pull_request_target` misuse has caused in real projects. This approval is the
last checkpoint before AI-written code executes with your repository's
credentials. It is a *stronger* version of the same principle the rest of this
document is built on.

**But it does mean the race is not fully unattended.** The honest statement is:
the research loop and the weekly proposal run with zero human input; an agent
race costs you one click per racer before its evidence appears. Budget for that
rather than being surprised by it.

Note also that `close/reopen` does **not** clear this state — verified. That
remedy works for `GITHUB_TOKEN` PRs, not agent PRs. To evaluate an agent branch
without granting it CI, dispatch the gate against the branch directly:

```bash
gh workflow run env-validate.yml --ref <agent-branch>
```

This runs with *you* as the triggering actor, so no approval is required, and it
produces the same build and PQ evidence.

GitHub does offer a repository setting to skip approval for coding-agent
workflows. **This harness recommends leaving it on.** Turning it off buys a
click and sells the checkpoint.

Two remedies for the `GITHUB_TOKEN` case, in order of preference:

1. **Set a `HARNESS_BOT_TOKEN` secret** — a fine-grained PAT or GitHub App
   installation token with *Contents: read & write* and *Pull requests: read &
   write* on this repository only. All three PR-opening workflows use
   `secrets.HARNESS_BOT_TOKEN || github.token`, so setting it is the only
   required step. PRs then trigger the gate normally.
2. **Close and reopen the pull request.** A human doing this re-triggers
   `pull_request` and the gate runs. No secret needed, but it is manual — which
   defeats the point of an unattended loop.

When no bot token is configured, `build-fixtures` appends an explicit warning to
the PR body so the reviewer is never left to infer why the checks are absent.

### `HARNESS_BOT_TOKEN` is mandatory for `agent-race`

For the workflows above the token is an *improvement*: without it the loop still
runs and fails closed. For `agent-race` it is a hard **prerequisite**, and the
distinction is worth stating plainly because the failure is not obvious.

Assigning an issue to a coding agent uses the `replaceActorsForAssignable`
GraphQL mutation, and GitHub rejects it outright for App installation tokens:

```
FORBIDDEN: Assigning agents is not supported with GitHub App installation
tokens. Use a user token (personal access token or OAuth token) instead.
```

`GITHUB_TOKEN` **is** an App installation token, so no configuration of
`permissions:` can make this work. Verified: the same mutation with the same
actor ID succeeds with a user token and fails with `GITHUB_TOKEN`.

There is a second, quieter consequence. The `suggestedActors` query returns a
*different set of agents depending on the token*:

| Token | Agents returned |
|---|---|
| `GITHUB_TOKEN` | `anthropic-code-agent`, `openai-code-agent` |
| user token / PAT | those **plus `copilot-swe-agent`** |

So under `GITHUB_TOKEN` the Copilot racer is not merely unassignable — it is
invisible, and would silently never appear in a race. The workflow now names
this case explicitly rather than reporting a generic skip.

The token needs `repo` scope (classic) or *Issues: read & write* plus
*Pull requests: read & write* (fine-grained). Until it is set, `agent-race`
fails loudly, closes any issue it created but could not assign, and tells you
exactly which secret is missing. It does not pretend to have started a race.

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
- The learning log (`evidence/learnings.jsonl`) absorbs observations **without**
  opening anything. `learning-promote.yml` converts one into a PR only after the
  same lesson has been recorded twice. This is the reason the threshold exists at
  all: promotion spends the scarce resource, so it has to be earned. A harness
  that proposed a rule for every observation would consume more review time than
  the environment proposals it exists to support.

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
