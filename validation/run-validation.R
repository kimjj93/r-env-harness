#!/usr/bin/env Rscript
# PHASE 2 — Execute Performance Qualification.
#
#   Rscript validation/run-validation.R
#
# Contract:
#   * writes test-results.xml (JUnit) for CI and for Phase 3
#   * writes pq-summary.json for the metrics pipeline
#   * exits non-zero on any failure  <- this IS the CI gate
#
# MUST run inside the built container image. Running it beside the image tests a
# different environment than the one that would ship, which makes the evidence
# worthless.

suppressPackageStartupMessages({
  library(testthat)
  library(digest)
})

source("validation/R/helper_compare-reference.R")
source("validation/R/testcase_adsl.R")
source("validation/R/testcase_adae.R")
source("validation/R/testcase_numeric.R")

artifacts <- Sys.getenv("ARTIFACT_DIR", unset = "artifacts")
dir.create(artifacts, recursive = TRUE, showWarnings = FALSE)

xml_out  <- file.path(artifacts, "test-results.xml")
json_out <- file.path(artifacts, "pq-summary.json")

message("=== Performance Qualification ===")
message("R version : ", getRversion())
message("Fixtures  : ", fixture_dir())
message("Artifacts : ", artifacts)
message("")

recorder_start()

reporter <- MultiReporter$new(list(
  JunitReporter$new(file = xml_out),
  SummaryReporter$new()
))

results <- test_dir(
  "validation/tests/testthat",
  reporter  = reporter,
  env       = globalenv(),
  stop_on_failure = FALSE
)

df <- as.data.frame(results)
n_fail  <- sum(df$failed)  + sum(df$error)
n_pass  <- sum(df$passed)
n_skip  <- sum(df$skipped)

rec <- recorder_collect()
n_strict   <- sum(rec$path == "Strict (exact)")
n_tolerant <- sum(rec$path == "Tolerant")
max_dev    <- suppressWarnings(max(rec$max_abs_dev, na.rm = TRUE))
if (!is.finite(max_dev)) max_dev <- 0

# Headroom: how close the worst observed deviation came to its tolerance.
# A run that passes at 99% of tolerance is a warning sign the summary counts hide.
headroom <- NA_real_
tol_rows <- rec[rec$path == "Tolerant" & rec$business_tol > 0, , drop = FALSE]
if (nrow(tol_rows)) {
  ratios <- tol_rows$max_abs_dev / tol_rows$business_tol
  ratios <- ratios[is.finite(ratios)]
  if (length(ratios)) headroom <- max(ratios)
}

checksums <- tryCatch(
  list(adsl = testcase_adsl_checksum(), adae = testcase_adae_checksum()),
  error = function(e) list(adsl = NA_character_, adae = NA_character_)
)

message("")
message("--- Summary ---")
message("passed   : ", n_pass)
message("failed   : ", n_fail)
message("skipped  : ", n_skip)
message("strict   : ", n_strict)
message("tolerant : ", n_tolerant)
message("max abs deviation : ", format(max_dev, digits = 6))
message("worst tolerance utilisation : ",
        if (is.na(headroom)) "n/a" else sprintf("%.2f%%", 100 * headroom))

if (nrow(rec)) {
  message("")
  message("--- Per-assertion ---")
  for (i in seq_len(nrow(rec))) {
    message(sprintf("  %-38s %-14s tol=%-8g dev=%-10s %s",
                    rec$case[i], rec$path[i], rec$business_tol[i],
                    ifelse(is.na(rec$max_abs_dev[i]), "n/a",
                           format(rec$max_abs_dev[i], digits = 3)),
                    ifelse(rec$passed[i], "PASS", "FAIL")))
  }
}

esc <- function(x) gsub('"', '\\\\"', as.character(x))
jrows <- vapply(seq_len(nrow(rec)), function(i) sprintf(
  '    {"case":"%s","path":"%s","business_tol":%g,"applied_tol":%g,"max_abs_dev":%s,"critical":"%s","passed":%s}',
  esc(rec$case[i]), esc(rec$path[i]), rec$business_tol[i], rec$applied_tol[i],
  ifelse(is.na(rec$max_abs_dev[i]), "null", format(rec$max_abs_dev[i], scientific = TRUE)),
  esc(rec$critical[i]), tolower(as.character(rec$passed[i]))
), character(1))

writeLines(c(
  "{",
  sprintf('  "r_version": "%s",', getRversion()),
  sprintf('  "passed": %d, "failed": %d, "skipped": %d,', n_pass, n_fail, n_skip),
  sprintf('  "strict": %d, "tolerant": %d,', n_strict, n_tolerant),
  sprintf('  "max_abs_deviation": %s,', format(max_dev, scientific = TRUE)),
  sprintf('  "tolerance_utilisation": %s,',
          if (is.na(headroom)) "null" else format(headroom, scientific = TRUE)),
  sprintf('  "result_checksums": {"adsl": "%s", "adae": "%s"},',
          checksums$adsl, checksums$adae),
  '  "assertions": [',
  paste(jrows, collapse = ",\n"),
  "  ]",
  "}"
), json_out)

message("")
message("Wrote ", xml_out)
message("Wrote ", json_out)

if (n_fail > 0) {
  message("\nPERFORMANCE QUALIFICATION FAILED (", n_fail, " failure(s)).")
  message("Do not resolve this by widening a tolerance (AGENTS.md §1.6).")
  quit(status = 1L, save = "no")
}

message("\nPerformance Qualification PASSED.")
quit(status = 0L, save = "no")
