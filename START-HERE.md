# Start here

You do one thing in this repository: **review pull requests.**

Everything else runs itself. If you read nothing further, you can still work
here safely, because nothing reaches `main` without you clicking merge.

---

## The whole loop in five lines

1. You describe what you want in a `.md` file, or an agent picks up an issue.
2. An agent works on a **branch** and opens a **pull request**. Never on `main`.
3. CI builds the environment, runs the validation, and attaches the evidence.
4. You read the PR and merge it or close it. **Only a human can merge.**
5. What the repo learns from that gets proposed back to you — as another PR.

That is the entire method. The rest of this repository is machinery for making
steps 3 and 5 trustworthy.

---

## What you actually have to do

**Merge or close pull requests.** That is the whole job.

There is one predictable window: **Monday morning**, when the harness proposes
its own changes. Outside that window, PRs only appear because you or an agent
started something. If nothing is open, nothing needs you.

```bash
gh pr list                 # anything waiting for me?
gh pr checks <number>      # did the evidence pass?
gh pr diff <number>        # what actually changed?
```

**Before merging, the only question that matters:** does the evidence in the PR
support the claim in its description? Every proposal must show its numbers. If
a PR asserts an improvement without measurements, that alone is grounds to
close it.

---

## What you never have to do

- **Watch the Actions tab.** Failures surface as a red check on a PR.
- **Track branches.** Agents create and delete their own. Two are permanent
  data stores you should never check out: `evidence/images` and
  `research/telemetry`.
- **Run anything locally.** CI is the source of truth. Local runs are for
  debugging, never for evidence.
- **Approve your own work to get it in.** No workflow can merge or approve. That
  is enforced mechanically, not by convention.

---

## The nine workflows, in one table

Only two ever produce a pull request you must decide on.

| workflow | when | asks you for |
|---|---|---|
| `lint` | every PR | nothing — a gate |
| `usecase-lint` | every PR | nothing — a gate |
| `usecase-env-validate` | every PR | nothing — a gate |
| `ai-review` | every PR | nothing — advice only, never a verdict |
| `nightly-research` | nightly | **nothing.** Pure background compute |
| `weekly` | Monday 06:00 | **≤3 PRs**: drift, proposal, promoted lesson |
| `usecase-publish-image` | merge to `main` | nothing — publishes + qualifies |
| `agent-race` | you label an issue | the winner arrives as a PR |
| `usecase-build-fixtures` | manual only | nothing |

---

## Where to look when you need more

Read these when you have a question, not before.

| file | answers |
|---|---|
| `README.md` | what this is and why it is built this way |
| `docs/OPERATING-MANUAL.md` | how to actually operate it day to day |
| `AGENTS.md` | the contract agents obey — **and what the repo has already learned** |
| `GOVERNANCE.md` | why a human must merge, and how that is enforced |
| `harness.yml` | the seam: swap this to point the harness at a different domain |

`AGENTS.md` is worth one read even if you write no code. Its final section is
generated from the repository's own failures — every mistake made twice is
promoted there automatically, so it is the shortest honest description of what
actually goes wrong here.

---

## If something looks wrong

The most valuable habit in this repository: **a green check is not evidence.**

Most defects found while building this failed by *producing less* rather than by
failing — a gate that could not find its input passed, a scan that measured
nothing exited zero, steps named "archive" archived nothing. Every one of them
showed green.

So when a result matters, open the artifact and read the number. If a check
claims success but the evidence is empty, the check is wrong, not the evidence.
Say so in the PR and close it.
