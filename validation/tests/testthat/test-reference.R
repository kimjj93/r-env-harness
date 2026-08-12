# PQ assertions.
#
# Tolerances are declared per assertion, with a justification. Raising one to
# make a build pass is prohibited (AGENTS.md §1.6) — a tolerance change is a
# separate, argued, human-reviewed PR.

test_that("ADSL summary statistics reproduce the reference", {
  fx   <- load_fixture("adsl_summary")
  meta <- fx[[".validation_env_meta"]]
  ref  <- fx[["adsl_summary_reference"]]
  crit <- read_critical_packages(harness_path("validation/R/testcase_adsl.R"))

  obs <- testcase_generate_adsl_summary()

  # Counts must be exact under any environment: a differing subject count is a
  # data or logic defect, never floating-point drift.
  helper_expect_reference_match(
    obs$n_subjects, ref$n_subjects, meta,
    case = "ADSL: subject count", critical_packages = crit, tolerance = 0
  )
  helper_expect_reference_match(
    obs$n_safety, ref$n_safety, meta,
    case = "ADSL: safety population", critical_packages = crit, tolerance = 0
  )

  # Continuous summaries: 1e-10 is far tighter than any clinically meaningful
  # difference while still absorbing legitimate FP variation across builds.
  helper_expect_reference_match(
    obs$age_mean, ref$age_mean, meta,
    case = "ADSL: mean age", critical_packages = crit, tolerance = 1e-10
  )
  helper_expect_reference_match(
    obs$age_sd, ref$age_sd, meta,
    case = "ADSL: SD age", critical_packages = crit, tolerance = 1e-10
  )
  helper_expect_reference_match(
    obs$trtdur_mean, ref$trtdur_mean, meta,
    case = "ADSL: mean treatment duration",
    critical_packages = crit, tolerance = 1e-10
  )

  # Age group counts depend on boundary handling; exact by construction.
  helper_expect_reference_match(
    c(obs$n_agegr_lt65, obs$n_agegr_6574, obs$n_agegr_ge75),
    c(ref$n_agegr_lt65, ref$n_agegr_6574, ref$n_agegr_ge75),
    meta, case = "ADSL: age group distribution",
    critical_packages = crit, tolerance = 0
  )
})

test_that("ADAE summary statistics reproduce the reference", {
  fx   <- load_fixture("adae_summary")
  meta <- fx[[".validation_env_meta"]]
  ref  <- fx[["adae_summary_reference"]]
  crit <- read_critical_packages(harness_path("validation/R/testcase_adae.R"))

  obs <- testcase_generate_adae_summary()

  helper_expect_reference_match(
    obs$n_ae, ref$n_ae, meta,
    case = "ADAE: event count", critical_packages = crit, tolerance = 0
  )

  # Treatment-emergent flagging depends on date imputation. If an admiral
  # upgrade changes imputation behaviour this is the assertion that catches it,
  # which is exactly why it is exact rather than tolerant.
  helper_expect_reference_match(
    obs$n_te, ref$n_te, meta,
    case = "ADAE: treatment-emergent count",
    critical_packages = crit, tolerance = 0
  )
  helper_expect_reference_match(
    obs$n_serious, ref$n_serious, meta,
    case = "ADAE: serious event count", critical_packages = crit, tolerance = 0
  )
  helper_expect_reference_match(
    obs$adur_mean, ref$adur_mean, meta,
    case = "ADAE: mean event duration",
    critical_packages = crit, tolerance = 1e-10
  )
  helper_expect_reference_match(
    c(obs$n_sev_mild, obs$n_sev_mod, obs$n_sev_severe),
    c(ref$n_sev_mild, ref$n_sev_mod, ref$n_sev_severe),
    meta, case = "ADAE: severity distribution",
    critical_packages = crit, tolerance = 0
  )
})

test_that("RNG streams are stable across the environment", {
  fx   <- load_fixture("rng_kinds")
  meta <- fx[[".validation_env_meta"]]
  ref  <- fx[["rng_kinds_reference"]]
  crit <- read_critical_packages(harness_path("validation/R/testcase_numeric.R"))

  obs <- testcase_generate_rng_kinds()

  # A seeded RNG stream that changes means the RNG implementation changed. That
  # invalidates every simulation-based result, so tolerance is zero.
  for (nm in c("unif", "norm", "binom", "samp")) {
    helper_expect_reference_match(
      obs[[nm]], ref[[nm]], meta,
      case = paste0("RNG: ", nm), critical_packages = crit, tolerance = 0
    )
  }
})

test_that("linear algebra results are stable across the environment", {
  fx   <- load_fixture("linalg")
  meta <- fx[[".validation_env_meta"]]
  ref  <- fx[["linalg_reference"]]
  crit <- read_critical_packages(harness_path("validation/R/testcase_numeric.R"))

  obs <- testcase_generate_linalg()

  # BLAS/LAPACK implementations legitimately differ at the ULP level, so these
  # are tolerant even under a matching environment. 1e-12 is well below any
  # threshold that could affect a reported result.
  for (nm in c("det", "eigen1", "solve_11", "chol_11", "svd_1")) {
    helper_expect_reference_match(
      obs[[nm]], ref[[nm]], meta,
      case = paste0("LinAlg: ", nm), critical_packages = crit, tolerance = 1e-12
    )
  }
})

test_that("analysis dataset checksums are recorded", {
  path <- file.path(fixture_dir(), "result-checksums.rds")
  skip_if_not(file.exists(path), "no committed checksums")
  ref <- readRDS(path)

  obs <- list(adsl = testcase_adsl_checksum(), adae = testcase_adae_checksum())

  # Checksums intentionally do NOT fail the build: a checksum change under a
  # changed environment is expected and is reported as Layer 4 of the delta.
  # Failing here would duplicate the assertions above and block legitimate
  # upgrades. The information still reaches the reviewer via the delta report.
  for (nm in names(ref)) {
    if (!identical(ref[[nm]], obs[[nm]])) {
      message(sprintf("NOTE: %s checksum changed (%s -> %s); see delta report Layer 4",
                      nm, substr(ref[[nm]], 1, 12), substr(obs[[nm]], 1, 12)))
    }
  }
  expect_true(all(nzchar(unlist(obs))))
})
