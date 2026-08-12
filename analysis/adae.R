#!/usr/bin/env Rscript
# ADAE — Adverse Events Analysis Dataset.
#
# Second half of the validation payload. Exercises date imputation and
# treatment-emergent flagging, which are the derivations most sensitive to
# package version changes — and therefore the most useful canaries for
# environment drift.

suppressPackageStartupMessages({
  library(dplyr)
  library(admiral)
  library(pharmaversesdtm)
})

source_adsl <- function(path = "analysis/adsl.R") {
  sys.source(path, envir = globalenv())
}

build_adae <- function(adsl) {
  data("ae", package = "pharmaversesdtm", envir = environment())
  ae <- ae %>% convert_blanks_to_na()

  adsl_vars <- adsl %>%
    select(STUDYID, USUBJID, TRT01A, TRTSDT, TRTEDT, SAFFL, AGEGR1)

  adae <- ae %>%
    select(STUDYID, USUBJID, AESEQ, AETERM, AEDECOD, AEBODSYS,
           AESEV, AESER, AEREL, AEOUT, AESTDTC, AEENDTC) %>%
    left_join(adsl_vars, by = c("STUDYID", "USUBJID")) %>%
    # Impute partial dates to the first of the period; the convention is
    # declared here because it materially affects TRTEMFL.
    derive_vars_dt(dtc = AESTDTC, new_vars_prefix = "AST",
                   highest_imputation = "M", date_imputation = "first") %>%
    derive_vars_dt(dtc = AEENDTC, new_vars_prefix = "AEN",
                   highest_imputation = "M", date_imputation = "last") %>%
    mutate(
      # Treatment-emergent: onset on or after first dose, on or before last dose.
      TRTEMFL = if_else(
        !is.na(ASTDT) & !is.na(TRTSDT) & ASTDT >= TRTSDT &
          (is.na(TRTEDT) | ASTDT <= TRTEDT),
        "Y", "N"
      ),
      AESEVN = case_when(
        AESEV == "MILD"     ~ 1L,
        AESEV == "MODERATE" ~ 2L,
        AESEV == "SEVERE"   ~ 3L,
        TRUE ~ NA_integer_
      ),
      ADURN = as.numeric(AENDT - ASTDT) + 1
    ) %>%
    arrange(STUDYID, USUBJID, AESEQ)

  adae
}

if (sys.nframe() == 0) {
  sys.source("analysis/adsl.R", envir = globalenv())
  adsl <- build_adsl()
  adae <- build_adae(adsl)
  out <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[[1]] else "adae.rds"
  saveRDS(adae, out)
  cat("ADAE rows:", nrow(adae), " cols:", ncol(adae),
      " TE:", sum(adae$TRTEMFL == "Y", na.rm = TRUE), "\n")
}
