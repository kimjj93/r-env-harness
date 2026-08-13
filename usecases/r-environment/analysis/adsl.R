#!/usr/bin/env Rscript
# ADSL — Subject-Level Analysis Dataset.
#
# This is the *validation payload*: the workload whose numeric outputs must stay
# stable when the environment changes. It exists so that "the environment moved"
# can be turned into "here is what it did to the numbers".
#
# Determinism is mandatory (skills/performance-qualification/SKILL.md): no
# unseeded randomness, no timestamps, no locale-dependent sorting.

suppressPackageStartupMessages({
  library(dplyr)
  library(admiral)
  library(pharmaversesdtm)
})

build_adsl <- function() {
  data("dm", package = "pharmaversesdtm", envir = environment())
  data("ex", package = "pharmaversesdtm", envir = environment())

  dm <- dm %>% convert_blanks_to_na()
  ex <- ex %>% convert_blanks_to_na()

  # First and last exposure dates, derived from EX.
  #
  # max(..., na.rm = TRUE) over an all-NA group returns -Inf, not NA, which
  # would silently produce an infinite TRTDURD for any subject with a start
  # date but no recorded end date. Guard explicitly: "unknown" must stay
  # missing rather than becoming a number.
  safe_max_date <- function(x) {
    if (all(is.na(x))) as.Date(NA) else max(x, na.rm = TRUE)
  }

  ex_dates <- ex %>%
    derive_vars_dt(dtc = EXSTDTC, new_vars_prefix = "EXST") %>%
    derive_vars_dt(dtc = EXENDTC, new_vars_prefix = "EXEN") %>%
    filter(!is.na(EXSTDT)) %>%
    group_by(USUBJID) %>%
    summarise(TRTSDT = min(EXSTDT), TRTEDT = safe_max_date(EXENDT),
              .groups = "drop")

  adsl <- dm %>%
    select(STUDYID, USUBJID, SUBJID, SITEID, AGE, AGEU, SEX, RACE, ETHNIC,
           ARM, ACTARM, COUNTRY, RFSTDTC, RFENDTC) %>%
    left_join(ex_dates, by = "USUBJID") %>%
    mutate(
      TRT01P = ARM,
      TRT01A = ACTARM,
      # Safety population: any exposure recorded.
      SAFFL  = if_else(!is.na(TRTSDT), "Y", "N"),
      # Treatment duration in days, inclusive of both endpoints.
      TRTDURD = as.numeric(TRTEDT - TRTSDT) + 1,
      AGEGR1 = case_when(
        AGE <  65 ~ "<65",
        AGE >= 65 & AGE < 75 ~ "65-74",
        AGE >= 75 ~ ">=75",
        TRUE ~ NA_character_
      )
    ) %>%
    # Deterministic ordering: never rely on incoming row order.
    arrange(STUDYID, USUBJID)

  adsl
}

if (sys.nframe() == 0) {
  adsl <- build_adsl()
  out <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[[1]] else "adsl.rds"
  saveRDS(adsl, out)
  cat("ADSL rows:", nrow(adsl), " cols:", ncol(adsl), "\n")
}
