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
environment is provably identical to the one that produced the baseline.

Note what "identical" has to include. It is **not** enough that the image digest
matches. An optimised BLAS chooses both a thread count and a CPU kernel at
*runtime*, and both change the last bits of a linear-algebra result. Two runs of
one image digest on two different machines are genuinely different numerical
environments. Pin `OPENBLAS_NUM_THREADS` and `OPENBLAS_CORETYPE` in the image,
and record both, or the strict path is claiming more than the evidence supports:

```r
helper_reference_env_matches <- function(meta, critical_packages = character(0)) {
  if (!identical(as.character(getRversion()), as.character(meta$r_version))) {
    return(FALSE)
  }
  # The numerical backend is part of the environment's identity.
  if (is.null(meta$backend)) return(FALSE)
  live <- numeric_backend_meta()
  for (k in c("platform", "arch", "blas", "lapack",
              "blas_threads", "blas_coretype")) {
    if (!identical(as.character(meta$backend[[k]]),
                   as.character(live[[k]]))) return(FALSE)
  }
  for (pkg in critical_packages) {
    v <- as.character(utils::packageVersion(pkg))
    if (!identical(as.character(meta$critical_pkgs[[pkg]]), v)) return(FALSE)
  }
  TRUE
}
```

| Environment matches baseline? | Path | Criterion |
|---|---|---|
| R version, numerical backend **and** all critical packages match | **Strict** | `all.equal(tolerance = 0)`, bit-for-bit |
| R version, backend **or** any critical package differs | **Tolerant** | shape identical **and** `max(abs(object - reference)) <= tolerance` |

The rationale is regulatory, not merely practical: when the environment provably
did not change, *any* numeric difference is a defect. When it did change, bounded
numeric drift is expected — but it must be quantified, declared in advance, and
recorded.

### Tolerance applies to values, never to shape

A numeric tolerance is a claim about floating-point arithmetic: the same
computation, performed in a different order, lands slightly away from where it
did before. It says nothing about the *shape* of the answer.

That distinction has to be enforced explicitly, because flattening hides it. A
2×3 matrix and a 3×2 matrix holding the same six numbers have a maximum absolute
deviation of **zero** once passed through `as.numeric(unlist(x))`, and so does a
vector whose names have all changed. A comparison built only on flattened values
therefore reports a perfect match between results that are not the same result.

Measured on this harness before the fix, all three of these passed at `1e-8`:

| Comparison | Flattened max deviation | Verdict now |
|---|---|---|
| 2×3 matrix vs 3×2 matrix | `0` | **fails** — `dim` differs |
| matrix vs plain vector | `0` | **fails** — `dim` differs |
| named vector, names all changed | `0` | **fails** — `names` differ |

So `length`, `dim`, `names`, `dimnames` and `class` are compared **exactly on
both paths**, and only the values are permitted to move within tolerance. An
analysis dataset that changed dimensions but stayed numerically close is a
different dataset, not a tolerable deviation. The failure is reported as
`STRUCTURE CHANGED (dim differs)` rather than as a tolerance breach, because the
reviewer needs to know it is not a question of how much drift is acceptable.

### `expect_equal()` is not an exact comparison

The strict path must **not** be written with `testthat::expect_equal()`. Its
default tolerance is `sqrt(.Machine$double.eps)` ≈ `1.49e-8` in every edition, so
a "strict, exact" assertion built on it silently accepts deviations up to that
size — and would report an applied tolerance of `0` while doing so.

That is not hypothetical here: the BLAS thread and CPU-kernel non-determinism
this harness found measured `1.42e-14`, roughly a million times *below* that
threshold. A strict path built on `expect_equal()` would have passed every one
of those runs and the defect would still be undiscovered.

Use `all.equal(object, reference, tolerance = 0)`, and only then may the report
record `Applied tol = 0`.

### Why the numerical backend counts as part of the environment

`det()`, `eigen()` and `solve()` are computed by BLAS/LAPACK, not by R. Identical
R and package versions linked against a different BLAS build, or running on a
different CPU architecture, legitimately disagree in the last bits — the harness
observed exactly this, at `4.19e-16` on `det()` and `1.78e-15` on `eigen()`.
Recording only R and package versions would classify that as a **defect** when it
is in fact an environment change. So `platform`, `arch`, `blas` and `lapack` are
captured into every fixture and compared like any other pin.

A fixture that predates backend capture has no `backend` field. It is routed to
the tolerant path with the reason `not recorded in fixture`, because absence of
evidence cannot support an exactness claim.

### The limit of introspection, and why fixtures are built in CI

An **emulated** x86_64 container — an amd64 image on Apple silicon under
Rosetta or QEMU — reports the same `platform`, `arch` and BLAS strings as a
native x86_64 runner, while still differing in the last bits. No fingerprint
taken from inside the session can detect that.

The defence is therefore provenance, not introspection. Fixtures are generated by
`.github/workflows/build-fixtures.yml`, on a CI runner, inside the validated
image, and the run ID and platform are recorded in the PR body. **Never commit a
fixture generated on a workstation**, even if it appears to pass locally.

## Declaring critical packages

Each test case declares which packages gate strict comparison, in a roxygen block
read by the fixture builder at build time:

```r
#' @section Critical Packages:
#' admiral, dplyr.
```

Adding or removing a critical dependency is therefore a one-line documentation
change — no build system edits.

## Deriving a tolerance

A tolerance is an acceptance criterion and must be derived, not chosen. The
harness learned this the hard way: a flat `1e-12` was applied to five linear
algebra quantities spanning `5.7e-3` to `9.4e1`. That is `2e-10` relative on the
smallest and `1e-14` relative on the largest — simultaneously far too loose and
tighter than double precision can deliver. It passed only until the BLAS changed.

Derive from the arithmetic instead. For a linear algebra result `x` computed from
a matrix with condition number `k`, error is bounded on the order of
`eps * |x| * k`:

```r
linalg_tolerance <- function(ref_value, kappa, safety = 10,
                             floor = 1e-13, ceiling = 1e-6) {
  tol <- max(.Machine$double.eps * abs(ref_value) * kappa * safety, floor)
  if (tol > ceiling) stop("derived tolerance exceeds the hard cap")
  tol
}
```

Three properties make this reviewable:

- **It scales.** Each quantity gets a criterion proportionate to its own
  magnitude and conditioning.
- **It has a floor.** Values near zero do not get a criterion of ~0.
- **It has a hard cap, and the cap is fatal.** A derivation is still capable of
  producing an absurd number if the inputs are absurd. If conditioning is so poor
  that the derived tolerance exceeds `1e-6`, the assertion has stopped being
  meaningful — that is a defect in the test, not a licence to accept the value.

Always report utilisation (`observed / tolerance`) rather than a bare pass. The
harness's linear algebra assertions run at **under 1% of their derived bounds**;
a run at 95% is nominally passing while telling you something is wrong.

See `AGENTS.md` §1.6 for the rule separating a legitimate correction from
weakening a gate: *would this change still be correct if the test were passing?*

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
