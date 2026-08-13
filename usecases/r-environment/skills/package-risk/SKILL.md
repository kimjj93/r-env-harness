---
name: package-risk
description: Assess the qualification risk of R packages newly introduced into the environment using riskmetric scores across unit testing, documentation, community engagement, and maintenance dimensions. Use whenever a PR adds a package that was not previously in the lockfile.
---

# Skill: Package Risk Assessment

## Purpose

When a package enters the environment for the first time, produce an objective,
auditable risk score so the reviewer can calibrate how much scrutiny it deserves.

This implements the R Validation Hub's **risk-based** qualification approach:
effort should be proportional to risk, not uniform across all packages.

## Critical scope limitation

`{riskmetric}` scores a package's **development practices and community trust**.
It does **not** verify statistical correctness.

- `riskmetric` → *should we trust this package's maintenance?*
- Performance Qualification → *does this environment produce the right numbers?*

Never present a good riskmetric score as evidence of correctness. They are
complementary and both are required.

## Metric dimensions

| Dimension | Representative assessments |
|---|---|
| Unit testing | `assess_has_tests()`, `assess_covr_coverage()` |
| Documentation | `assess_has_vignettes()`, `assess_has_news()`, `assess_has_examples()`, `assess_exported_namespace()` |
| Community | `assess_downloads_1yr()`, `assess_has_bug_reports_url()` |
| Maintenance | `assess_last_30_days_downloads()`, `assess_license()`, `assess_maintainer_country()` |

## Workflow

```r
library(riskmetric)

ref    <- pkg_ref(new_packages)
assess <- pkg_assess(ref)
scores <- pkg_score(assess)      # 0 = high risk … 1 = low risk
summarize_scores(scores)
```

Scan **only newly added packages** — re-scoring the entire library on every PR is
noise that trains reviewers to ignore the section.

## Interpreting the score

Scores are a triage signal, not a pass/fail gate. Do not auto-block on a
threshold; surface the score and let the human decide.

| Score | Suggested response |
|---|---|
| ≥ 0.8 | low risk — note it and move on |
| 0.5–0.8 | medium — flag which dimensions are weak |
| < 0.5 | high — call it out prominently; enumerate the failing dimensions and consider whether a PQ test case should cover its behaviour directly |

Always report *which* dimensions drove a low score. "0.42" is not actionable;
"no test suite, no NEWS file, single maintainer, 300 downloads/year" is.

## Reporting

In the PR body:

```markdown
### Package risk (newly added)

| Package | Version | Score | Weakest dimensions |
|---|---|---|---|
| somepkg | 0.3.1   | 0.42  | no tests, no vignettes |

No newly added packages.   ← say this explicitly when true
```

## Rules

- Never skip the scan because a package "looks fine."
- Never let a good score substitute for a PQ test case.
- Record scores in `evidence/metrics/metrics.jsonl` so trends are visible over time.
- If `riskmetric` cannot assess a package (not on CRAN, internal, GitHub-only),
  say so explicitly rather than omitting the row.

## Forward compatibility

The R Validation Hub is moving development toward `{val.meter}` as riskmetric's
successor. Keep the scan behind `bin/riskmetric_scan.R` so the backend can be
swapped without touching workflows.

## References

- `{riskmetric}` — <https://github.com/pharmaR/riskmetric>
- R Validation Hub — <https://www.pharmar.org/>
