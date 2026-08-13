---
name: env-delta
description: Compare two R environments across four layers - image digest, base OS and system libraries, R package versions, and analysis result checksums - and produce a reviewable delta report. Use when a PR changes any environment pin, or when qualifying a candidate environment against the incumbent.
---

# Skill: Environment Delta

## Purpose

Turn "the environment changed" into "here is precisely what changed, and here is
what it did to the numbers."

A reviewer should never have to diff two environments by hand, and should never
have to *assume* that nothing else moved.

## The four layers

Report all four, in this order. Each answers a different reviewer question.

### Layer 1 — Image digest
*Did anything change at all?*

Compare `sha256` digests from `env/images/images.lock.json`. Identical digests
mean bit-identical environments and the remaining layers are provably empty.
This is the cheapest possible proof of "no change."

### Layer 2 — Base / OS
*Did the ground shift underneath the packages?*

From `docker inspect` and the in-image manifest: base image digest, OS release,
glibc version, locale, and system library versions. This layer catches drift that
`renv.lock` is structurally incapable of seeing — and is the usual explanation
when identical package versions produce different numbers.

### Layer 3 — R packages
*What moved in the library?*

Parse both lockfiles and classify every package as `ADDED`, `REMOVED`, or
`CHANGED`:

```r
old <- jsonlite::fromJSON("renv.lock.baseline")$Packages
new <- jsonlite::fromJSON("renv.lock.candidate")$Packages

old_v <- vapply(old, `[[`, character(1), "Version")
new_v <- vapply(new, `[[`, character(1), "Version")

added   <- setdiff(names(new_v), names(old_v))
removed <- setdiff(names(old_v), names(new_v))
common  <- intersect(names(old_v), names(new_v))
changed <- common[old_v[common] != new_v[common]]
```

For GitHub-sourced packages compare `RemoteSha`, not `Version` — a version string
can stay still while the commit moves.

On Track B the equivalent is `git diff` on `default.nix`, which surfaces the
nixpkgs date pin and package set changes.

### Layer 4 — Results
*Did any of it actually matter?*

The layer that carries regulatory weight. Compare ADSL/ADAE output checksums
between environments. If they differ, report the maximum absolute numeric
deviation from the PQ run and the affected variables.

Interpretation:

| Layers 1–3 | Layer 4 | Meaning |
|---|---|---|
| no change | no change | provably identical; safe |
| changed | no change | environment moved, results stable — the ideal upgrade |
| changed | changed within tolerance | acceptable drift; must be documented |
| changed | changed beyond tolerance | **blocks the PR**; investigate |
| no change | changed | non-determinism in the pipeline — a defect; investigate |

That last row matters: identical environments producing different results means
something is unpinned (an RNG seed, a timestamp, an ordering dependency).

## Output contract

`bin/image_delta.R` writes `delta.json`:

```json
{
  "layer1_digest":   { "changed": true, "baseline": "sha256:...", "candidate": "sha256:..." },
  "layer2_base":     { "changed": false, "fields": [] },
  "layer3_packages": { "added": [], "removed": [],
                       "changed": [{"package":"dplyr","old":"1.1.3","new":"1.1.4"}] },
  "layer4_results":  { "changed": false, "checksums": {}, "max_abs_deviation": 0 },
  "verdict": "PASS_WITH_CHANGES"
}
```

Verdicts: `IDENTICAL`, `PASS_WITH_CHANGES`, `TOLERANT_DRIFT`, `FAIL_DEVIATION`,
`FAIL_NONDETERMINISM`.

Render the same content as a markdown table for the PR comment. Always post it,
even when every layer is empty — a reviewer needs to see that the check ran.

## Rules

- Always compare candidate against the **merge base**, not against whatever
  `main` happens to be right now.
- Never summarise a delta as "minor." State the counts and let the reviewer judge.
- Archive every manifest under `evidence/manifests/` — the delta is only
  trustworthy if both sides are reproducible.
- An empty delta is a result, not a non-event. Report it.

## References

- `{renv}` lockfile format — <https://rstudio.github.io/renv/articles/lockfile.html>
- Pfizer R validation framework — <https://github.com/pfizer-rd/rvalidation-refactored>
