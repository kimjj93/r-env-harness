#' Test case: ADAE derivation reproducibility
#'
#' Exercises partial-date imputation and treatment-emergent flagging — the
#' derivations most sensitive to package version changes, and therefore the most
#' informative canaries for environment drift.
#'
#' @section Critical Packages:
#' admiral, dplyr, lubridate.

testcase_generate_adae_summary <- function() {
  sys.source(harness_path("analysis/adsl.R"), envir = globalenv())
  sys.source(harness_path("analysis/adae.R"), envir = globalenv())
  adsl <- build_adsl()
  adae <- build_adae(adsl)

  list(
    n_ae          = nrow(adae),
    n_te          = sum(adae$TRTEMFL == "Y", na.rm = TRUE),
    n_serious     = sum(adae$AESER == "Y", na.rm = TRUE),
    n_subj_with_ae = length(unique(adae$USUBJID)),
    sev_mean      = mean(adae$AESEVN, na.rm = TRUE),
    adur_mean     = mean(adae$ADURN, na.rm = TRUE),
    adur_max      = max(adae$ADURN, na.rm = TRUE),
    n_sev_mild    = sum(adae$AESEVN == 1L, na.rm = TRUE),
    n_sev_mod     = sum(adae$AESEVN == 2L, na.rm = TRUE),
    n_sev_severe  = sum(adae$AESEVN == 3L, na.rm = TRUE)
  )
}

#' Deterministic checksum of the full ADAE, for Layer 4 of the delta report.
testcase_adae_checksum <- function() {
  sys.source(harness_path("analysis/adsl.R"), envir = globalenv())
  sys.source(harness_path("analysis/adae.R"), envir = globalenv())
  adsl <- build_adsl()
  adae <- build_adae(adsl)
  adae <- adae[order(adae$STUDYID, adae$USUBJID, adae$AESEQ), ]
  digest::digest(adae, algo = "sha256")
}
