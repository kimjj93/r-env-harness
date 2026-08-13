#!/usr/bin/env bash
# tools/extract-template.sh [target-dir] — lift the harness out, leave the domain.
#
# Produces a working repository containing the harness, its governance, its CI
# gates and its research loop, with a stub use case that does nothing but
# satisfy the contract. Point it at a new domain and it runs.
#
# This script exists to make the separation *demonstrable* rather than claimed.
# If it stops producing something that passes `harness/check_boundary`, the
# boundary has rotted, and the test for that is running this script.
#
#   ./tools/extract-template.sh ../my-new-harness
#   cd ../my-new-harness && ./harness/check_boundary

set -euo pipefail

TARGET="${1:-../harness-template}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"

if [ -e "$TARGET" ] && [ -n "$(ls -A "$TARGET" 2>/dev/null)" ]; then
  echo "Refusing to write into a non-empty directory: $TARGET" >&2
  exit 1
fi

cd "$SRC"
OLD_ROOT="$(./harness/usecase root)"
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

echo "Extracting harness from $SRC -> $TARGET"
echo "  dropping use case: $OLD_ROOT"

# ---------------------------------------------------------------------------
# 1. Copy the harness. Everything not listed here is domain or derived.
# ---------------------------------------------------------------------------
for p in AGENTS.md GOVERNANCE.md CLAUDE.md LICENSE harness skills docs tools; do
  [ -e "$p" ] && cp -R "$p" "$TARGET/"
done

mkdir -p "$TARGET/.github/workflows"
# Scaffold workflows only. The `usecase-` prefix is what marks a workflow as
# belonging to the domain, and the domain is exactly what we are removing.
for wf in .github/workflows/*.yml; do
  case "$(basename "$wf")" in
    usecase-*) continue ;;
    *) cp "$wf" "$TARGET/.github/workflows/" ;;
  esac
done
[ -f .gitignore ] && cp .gitignore "$TARGET/"

# The learning log is history about a domain being left behind. The *mechanism*
# travels; the entries do not. Carrying them would seed a new project with
# recurring lessons it has never encountered, which is how you end up with a
# contract full of rules nobody understands the reason for.
mkdir -p "$TARGET/evidence/metrics"
: > "$TARGET/evidence/learnings.jsonl"
: > "$TARGET/evidence/metrics/.gitkeep"

# ---------------------------------------------------------------------------
# 2. Write a stub use case that satisfies the contract and nothing more.
# ---------------------------------------------------------------------------
STUB="$TARGET/usecases/example"
mkdir -p "$STUB/bin" "$STUB/skills"

cat > "$TARGET/harness.yml" <<'EOF'
# harness.yml — the seam.
#
# Replace this stub with your domain. The harness reads this file and never
# reads inside `root`, so everything below is the complete list of things the
# harness knows about what it is governing.

schema: 1

usecase:
  id: example
  name: Example use case
  root: usecases/example
  summary: >-
    A stub that satisfies the capability contract and validates nothing.
    Replace it.

variants:
  - id: default
    name: Default

capabilities:
  build:
    cmd: usecases/example/bin/build
  qualify:
    cmd: usecases/example/bin/qualify
  delta:
    cmd: usecases/example/bin/delta
  candidates:
    cmd: usecases/example/bin/candidates

scoring:
  - field: verdict
    direction: prefer_pass
  - field: margin_utilisation
    direction: lower
  - field: change_magnitude
    direction: lower
  - field: cost_seconds
    direction: lower

reserved:
  - AGENTS.md
  - GOVERNANCE.md
  - harness/
  - harness.yml
  - evidence/learnings.jsonl
EOF

cat > "$STUB/AGENTS.md" <<'EOF'
# AGENTS.md — Example use case

This file is **additional** to the root `AGENTS.md`, which is the harness
contract and always applies. Nothing here may relax a rule in root §1.

This is a stub. Replace every section below with rules that are true of your
domain, and delete the ones that are not.

## What this use case is for

Describe the deliverable, and be specific about what counts as evidence that it
is correct. If you cannot write that sentence, the capability adapters cannot be
written either — the ambiguity does not disappear, it just moves into the code.

## Variants

One variant, `default`. Add more only when you genuinely have independent
implementations worth comparing. Two variants that always agree cost twice the
CI time for no information; two that sometimes disagree are the cheapest bug
detector you will ever build.

## Generated files (root §1.4)

List any file with a generator, and name the generator. If there are none, say
so explicitly rather than leaving the section empty — an empty section reads
like an oversight.

## Committed baselines (root §1.5)

Say where the answer key lives and how it is regenerated.

## Additional definition of done

Add checklist items beyond root §3 that are specific to this domain.

## Skills index

Add `SKILL.md` files under `skills/` and index them here.
EOF

cat > "$STUB/bin/build" <<'EOF'
#!/usr/bin/env bash
# build <variant> — materialise a candidate state. Replace this.
set -euo pipefail
VARIANT="${1:?usage: build <variant>}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"; cd "$ROOT"
mkdir -p evidence/build
START=$(date +%s)
echo "stub build for variant '$VARIANT' — nothing was built"
END=$(date +%s)
cat > "evidence/build/${VARIANT}-build.json" <<JSON
{"variant":"${VARIANT}","cost_seconds":$((END-START)),"artifact_size_mb":null,"status":0}
JSON
EOF

cat > "$STUB/bin/qualify" <<'EOF'
#!/usr/bin/env bash
# qualify <variant> — prove the state correct. Replace this.
#
# Must write evidence/qualify/<variant>-qualify.json per docs/schema/evidence.md.
# Note margin_utilisation is null, not 0: nothing measured a margin here, and 0
# would claim perfect headroom it has not earned.
set -euo pipefail
VARIANT="${1:?usage: qualify <variant>}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"; cd "$ROOT"
mkdir -p evidence/qualify
cat > "evidence/qualify/${VARIANT}-qualify.json" <<JSON
{"variant":"${VARIANT}","checks_passed":0,"checks_failed":0,"checks_skipped":0,
 "margin_utilisation":null,"cost_seconds":0,"detail":{"stub":true}}
JSON
echo "stub qualify for variant '$VARIANT' — no checks were run"
EOF

cat > "$STUB/bin/delta" <<'EOF'
#!/usr/bin/env bash
# delta <variant> [baseline] — compare against a baseline. Replace this.
set -euo pipefail
VARIANT="${1:?usage: delta <variant> [baseline]}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"; cd "$ROOT"
mkdir -p evidence/delta evidence/metrics
cat > "evidence/delta/${VARIANT}-delta.md" <<MD
# Delta: ${VARIANT}

Stub. Nothing was compared.
MD
cat > "evidence/delta/${VARIANT}-verdict.json" <<JSON
{"variant":"${VARIANT}","verdict":"NO_EVIDENCE","baseline":"${2:-none}",
 "summary":"stub delta — replace usecases/example/bin/delta",
 "report_path":"evidence/delta/${VARIANT}-delta.md"}
JSON
echo "stub delta for variant '$VARIANT' — verdict NO_EVIDENCE"
EOF

cat > "$STUB/bin/candidates" <<'EOF'
#!/usr/bin/env bash
# candidates — what the research loop may vary. Replace this.
#
# An empty list is the correct stub answer: the loop then explores nothing,
# which is better than exploring something arbitrary that nobody agreed to.
set -euo pipefail
echo '[]'
EOF

chmod +x "$STUB/bin/"*

cat > "$TARGET/README.md" <<'EOF'
# Harness template

A general-purpose harness for supervised autonomous work: agents propose on
branches, CI produces evidence, an automated research loop tunes proposals, and
**a human merges**. The rules the agents follow are plain text under version
control, so the agents' own behaviour is diffable and reviewable.

The harness does not know what it is governing. That knowledge lives in one
file — `harness.yml` — and one directory, and a CI gate fails the build if any
of it leaks back into the harness.

## Getting started

1. Read `AGENTS.md`. It is the contract the agents read.
2. Read `docs/schema/evidence.md`. It is the vocabulary every use case reports in.
3. Replace `usecases/example/` with your domain, and point `harness.yml` at it.
4. Implement four commands: `build`, `qualify`, `delta`, `candidates`.
5. Run `./harness/check_boundary`. If it passes, the harness stays reusable.

```bash
./harness/usecase check                # is the manifest coherent?
./harness/usecase variants             # what will CI fan out over?
./harness/usecase run qualify default  # invoke a capability
./harness/check_boundary               # has the harness learned about the domain?
```

## What you get

| | |
|---|---|
| `AGENTS.md` | the non-negotiable rules, including human-only merge |
| `GOVERNANCE.md` | who decides what, and how it is enforced rather than promised |
| `harness/usecase` | the dispatcher; the only thing that reads `harness.yml` |
| `harness/check_boundary` | fails the build if the harness learns about the domain |
| `harness/scoreboard.R` | ranks competing agents on evidence, not on prose |
| `harness/learnings.R` | append-only learning log; recurring lessons promote into the contract |
| `harness/agent_metrics.R` | first-pass acceptance and iteration cycles, with humans as the control group |
| `.github/workflows/` | PR gates, the agent race, AI review, the research loop, the weekly proposal |

## One-time repository setup

The human-only merge guarantee is enforced by a repository ruleset, not by
asking politely. Before running anything, protect `main`: require a pull
request, require at least one approving review, and **do not** grant the
`Copilot` or `github-actions` actor bypass. See `GOVERNANCE.md` for what each
setting buys and where the residual risks are.

## The one rule worth repeating

**Only a human merges.** Everything else is automatable and most of it is
automated. That single gate is what makes the rest safe to run unattended.
EOF

# ---------------------------------------------------------------------------
# 3. Prove the extraction is not merely a copy.
# ---------------------------------------------------------------------------
cd "$TARGET"
echo
echo "Verifying the extracted template ..."
./harness/usecase check || {
  echo "EXTRACTION FAILED: the stub does not satisfy its own contract." >&2; exit 1; }
./harness/check_boundary || {
  echo "EXTRACTION FAILED: harness files still reference the old use case." >&2; exit 1; }

# Any surviving mention of the old domain is a leak the boundary check missed,
# most likely in prose the check deliberately exempts.
if grep -rIl --exclude-dir=.git "$OLD_ROOT" . 2>/dev/null | grep -q .; then
  echo "EXTRACTION FAILED: '$OLD_ROOT' still appears in:" >&2
  grep -rIl --exclude-dir=.git "$OLD_ROOT" . >&2
  exit 1
fi

echo
echo "Template extracted to $TARGET"
echo "Next: replace usecases/example/, then point harness.yml at your domain."
