<!--
Racer issue template.

This is the brief each competing agent receives. It lives here as a versioned
file rather than buried inside a workflow heredoc for two reasons: it is content
an agent reads, so it belongs under the same review process as every other
instruction in this repo; and a change to how agents are briefed is a governance
change that should show up in a diff.

Placeholders substituted by .github/workflows/agent-race.yml:
  {{TASK}} {{STRATEGY}} {{RACER}} {{LOGIN}} {{PARENT}}
-->

## Task

{{TASK}}

## Your strategy brief: **{{STRATEGY}}**

You are one of several agents attempting this task independently, each with a
different brief. Optimise for *your* brief specifically. Do not try to be
balanced — another racer is arguing the opposite case, and the entire point of
the race is to make that trade-off visible to the human reviewer rather than
having a single agent quietly split the difference.

## Rules (from `AGENTS.md` — non-negotiable)

- Work on your own branch. Never commit to `main`.
- Never merge and never approve. A human decides.
- Every claim in your pull request description must be backed by an artifact CI
  produced. Do not state a build time, a package count, or a deviation you did
  not measure.
- `env-validate` and `skills-lint` must pass.
- Never hand-edit a generated file or a committed fixture.

## What you will be scored on

`harness/scoreboard.R` ranks racers on recorded metrics only, in this order:

1. **Delta verdict** — did the analysis results stay stable?
2. **Tolerance utilisation** — how much headroom is left before failure?
3. **Package churn** — how much must a human review?
4. **Build time** — last, deliberately. Speed never outranks the numbers.

Failing PQ is disqualifying, not a scoring penalty.

Read `skills/env-delta/SKILL.md` and `skills/performance-qualification/SKILL.md`
before you start.

## Deliverable

One pull request. In its description, state:

- your strategy and what you changed,
- the measured outcome, with links to the artifacts,
- **and where your approach is worse than a rival brief's would be.**

That last point is not a formality. An honest trade-off statement is worth more
to the reviewer than a claim of being best overall, and the scoreboard will
expose the trade-off anyway.

---
Racer: `{{RACER}}` ({{LOGIN}}) · Parent: {{PARENT}}
