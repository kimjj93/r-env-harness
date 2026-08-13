#' Test case: ADSL derivation reproducibility
#'
#' Recomputes the subject-level analysis dataset and compares summary statistics
#' against the committed baseline. These are the numbers that would appear in a
#' demographics table, so drift here is directly submission-relevant.
#'
#' @section Critical Packages:
#' admiral, dplyr, lubridate.

testcase_generate_adsl_summary <- function() {
  sys.source(usecase_path("analysis/adsl.R"), envir = globalenv())
  adsl <- build_adsl()

  list(
    n_subjects   = nrow(adsl),
    n_safety     = sum(adsl$SAFFL == "Y", na.rm = TRUE),
    age_mean     = mean(adsl$AGE, na.rm = TRUE),
    age_sd       = stats::sd(adsl$AGE, na.rm = TRUE),
    age_median   = stats::median(adsl$AGE, na.rm = TRUE),
    trtdur_mean  = mean(adsl$TRTDURD, na.rm = TRUE),
    trtdur_max   = max(adsl$TRTDURD, na.rm = TRUE),
    n_agegr_lt65 = sum(adsl$AGEGR1 == "<65", na.rm = TRUE),
    n_agegr_6574 = sum(adsl$AGEGR1 == "65-74", na.rm = TRUE),
    n_agegr_ge75 = sum(adsl$AGEGR1 == ">=75", na.rm = TRUE)
  )
}

#' Deterministic checksum of the full ADSL, for Layer 4 of the delta report.
testcase_adsl_checksum <- function() {
  sys.source(usecase_path("analysis/adsl.R"), envir = globalenv())
  adsl <- build_adsl()
  adsl <- adsl[order(adsl$STUDYID, adsl$USUBJID), ]
  digest::digest(adsl, algo = "sha256")
}
