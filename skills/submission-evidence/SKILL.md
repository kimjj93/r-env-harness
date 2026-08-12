---
name: submission-evidence
description: Assemble the audit trail that links a regulatory analysis result back to the exact environment that produced it - image digest, lockfile, session info, validation results, and delta history. Use when preparing submission documentation or answering a "what produced this number" question.
---

# Skill: Submission Evidence

## Purpose

An FDA reviewer asks: *what software produced this number?* This skill defines
the chain of artifacts that answers that question completely, and where each link
lives.

Regulatory submissions using open-source R cite the exact R version and package
versions used. The harness must be able to produce that on demand, for any commit,
years later.

## The evidence chain

```
analysis result
  └─ produced by → image digest        (env/images/images.lock.json)
       └─ built from → commit SHA      (git)
            └─ pins → lockfile         (renv.lock / default.nix)
                 └─ resolves to → package versions  (evidence/manifests/)
            └─ qualified by → PQ run   (test-results.xml, pq-report.html)
                 └─ compared against → baseline fixture (.validation_env_meta)
            └─ changed by → delta report (delta.json)
                 └─ approved by → human PR approval (GitHub review record)
```

Every link is committed or attached to a commit. There is no step that exists
only in someone's memory or in a chat log.

## Required artifacts per environment version

| Artifact | Location | Answers |
|---|---|---|
| Image digest | `env/images/images.lock.json` | which bits ran |
| Signature + SBOM | GHCR attestation | provenance and contents |
| Lockfile | `env/renv/renv.lock`, `env/nix/default.nix` | what was requested |
| Environment manifest | `evidence/manifests/<sha>.json` | what was actually installed |
| `sessioninfo` dump | inside manifest and fixtures | the canonical R-side record |
| PQ results | `test-results.xml` | whether numbers reproduced |
| PQ report | `pq-report.html` | human-readable qualification |
| Delta report | `delta.json` | what changed vs. the previous version |
| Risk scores | `metrics.jsonl` | qualification risk of new packages |
| Approval record | GitHub PR | who accepted it, and when |

## Answering "what produced this number"

1. Find the commit that generated the result.
2. Look up its digest in `env/images/images.lock.json`.
3. Pull that digest — it is immutable, so it is the same image.
4. Read `evidence/manifests/<sha>.json` for the full package/OS manifest.
5. Read the PQ report for that commit for qualification status.
6. Read the delta report to see how it differed from its predecessor.
7. Read the PR to see who approved it and what evidence they saw.

If any step cannot be completed, the chain is broken and that is a defect to fix
in the harness, not a documentation gap to paper over.

## Rules

- **Immutability is the foundation.** Tags may be re-pushed; digests may not.
  Cite digests everywhere, always.
- **Never delete evidence.** Retention policies must preserve every digest
  referenced by `images.lock.json` or by an accepted proposal.
- **Record `sessioninfo::session_info()`, not `sessionInfo()`** — it captures the
  package source (CRAN vs. GitHub vs. local), which matters for traceability.
- **The approval record is evidence too.** It is where human accountability is
  captured, which is exactly what a reviewer wants to see.
- **State limitations honestly.** If a track was `unsupported` for a candidate,
  that belongs in the record.

## Scope disclaimer

These artifacts are the *technical* evidence base. They do not by themselves
constitute IQ/OQ/PQ documentation under a quality management system. Producing
that remains the sponsor's responsibility.

## References

- Open source in NDAs — <https://github.com/philbowsher/Open-Source-in-New-Drug-Applications-NDAs-FDA>
- Pfizer R validation — <https://github.com/pfizer-rd/rvalidation-refactored>
- R Validation Hub — <https://www.pharmar.org/>
