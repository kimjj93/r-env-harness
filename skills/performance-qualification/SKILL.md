---
name: performance-qualification
description: Run and extend the three-phase Performance Qualification framework that proves an R environment reproduces known-good numeric results, using strict comparison when the environment matches the baseline and tolerant comparison with recorded deviations when it does not. Use when validating an environment change or adding a new test case.
---

# Skill: Performance Qualification

## Purpose

Prove that a *collection of packages in a specific environment* still produces the
numeric results it produced before. This is not unit testing of a function; it is
qualification of an environment.

Adapted from Pfizer R&D's `rvalidation-refactored` framework.

## Three decoupled phases

The phases communicate **only through artifacts on disk**. That decoupling is the
point: each phase is independently auditable, and the report can never
accidentally re-run the tests it is reporting on.

```
Phase 1  build fixtures    (once, on a trusted environment)
         data-raw/build-fixtures.R
           └─→ validation/fixtures/references/R-4.4/*.rda
               (numeric results + .validation_env_meta)

Phase 2  execute           (every validation run, inside the container)
         Rscript validation/run-validation.R
           └─→ test-results.xml   (JUnit)
           └─→ exit 1 on any failure  ← the CI gate

Phase 3  render report     (human-readable audit trail)
         quarto render validation/report/pq-report.qmd
           └─→ pq-report.html
           reads test-results.xml ONLY — never re-runs tests
```

## Strict vs. tolerant — the central design

Do **not** demand bit-for-bit equality unconditionally. Demand it only when the
environment is provably identical to the one that produced the baseline:

```r
helper_reference_env_matches <- function(meta, critical_packages = character(0)) {
  if (!identical(as.character(getRversion()), as.character(meta$r_version))) {
    return(FALSE)
  }
  for (pkg in critical_packages) {
    live <- as.character(utils::packageVersion(pkg))
    if (!identical(as.character(meta$critical_pkgs[[pkg]]), live)) return(FALSE)
  }
  TRUE
}
```

| Environment matches baseline? | Path | Criterion |
|---|---|---|
| R version **and** all critical packages match | **Strict** | `expect_equal()`, bit-for-bit |
| R version **or** any critical package differs | **Tolerant** | `max(abs(object - reference)) <= tolerance` |

The rationale is regulatory, not merely practical: when the environment provably
did not change, *any* numeric difference is a defect. When it did change, bounded
numeric drift is expected — but it must be quantified, declared in advance, and
recorded.

## Declaring critical packages

Each test case declares which packages gate strict comparison, in a roxygen block
read by the fixture builder at build time:

```r
#' @section Critical Packages:
#' admiral, dplyr.
```

Adding or removing a critical dependency is therefore a one-line documentation
change — no build system edits.

## The recorder

For every assertion, record and carry into the report:

- `Path` — `"Strict (exact)"` or `"Tolerant"`
- `Business tol` — the tolerance declared for that assertion
- `Applied tol` — `0` under strict, else the declared tolerance
- `Max abs dev` — the deviation actually observed
- `Critical` — the packages that gated the strict path

`Max abs dev` is the single most useful number in the report: it shows how much
headroom remains before a tolerance would be breached.

## Fixture metadata

Every `.rda` baseline stores, alongside its numeric results, a
`.validation_env_meta` record containing `r_version`, the `critical_pkgs` named
version list, and a full `sessioninfo::session_info()` dump. Without this, a
baseline is an unattributable number.

## Environment variables

| Variable | Effect |
|---|---|
| `RVALIDATION_FIXTURE_DIR` | base directory for fixture storage |
| `VALIDATION_REF_VERSION` | compare against a different `R-<major.minor>` baseline, enabling cross-version regression testing |

## Adding a test case

1. Create `validation/R/testcase_<name>.R` with a generator function that is
   deterministic — set every RNG seed and RNG kind explicitly.
2. Add the `@section Critical Packages:` block.
3. Declare the tolerance for each assertion, with a short justification comment.
4. Regenerate fixtures (Phase 1) in a clean environment.
5. Commit fixtures together with the test case in the same PR.

## Rules

- Phase 2 must run **inside** the built container image. Running it beside the
  image invalidates the evidence.
- A failing PQ is never fixed by raising a tolerance. Investigate the cause;
  a tolerance change is a separate, justified, human-reviewed PR.
- Tests must be deterministic. Any unseeded randomness makes the whole framework
  meaningless.
- Never edit a fixture by hand.

## References

- Pfizer R validation — <https://github.com/pfizer-rd/rvalidation-refactored>
- `{testthat}` — <https://testthat.r-lib.org/>
