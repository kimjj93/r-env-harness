#!/usr/bin/env Rscript
# Emit one metrics row per harness run.
#
#   Rscript usecases/r-environment/bin/metrics.R <outdir>
#
# Reads whatever artifacts exist and produces a single append-only JSON line.
# This file is the evidence base for every claim the weekly proposal makes —
# AGENTS.md §4 forbids asserting an improvement that is not backed by a row here.

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
outdir <- if (length(args) >= 1) args[[1]] else "artifacts"
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

rj <- function(f) if (file.exists(f)) tryCatch(fromJSON(f, simplifyVector = FALSE),
                                              error = function(e) NULL) else NULL

manifest <- rj(file.path(outdir, "manifest.json"))
pq       <- rj(file.path(outdir, "pq-summary.json"))
delta    <- rj(file.path(outdir, "delta.json"))
risk     <- rj(file.path(outdir, "risk.json"))

env_or <- function(k, d = "") { v <- Sys.getenv(k, unset = ""); if (nzchar(v)) v else d }

num <- function(x, d = NA) {
  if (is.null(x)) return(d)
  v <- suppressWarnings(as.numeric(x)); if (is.na(v)) d else v
}

# riskmetric's summarize_scores() is a RISK score: higher is worse. The worst
# package in the set is therefore the MAXIMUM, not the minimum. This was
# recorded as `riskmetric_min` taking min() -- which reported the safest package
# in the change as if it characterised the change.
#
# The field is `package_risk` because the harness resolves a gate named
# `<field>_max` to the field `<field>`. Writing `riskmetric_min` here meant the
# gate `riskmetric_min` looked for a field called `riskmetric`, which nothing
# ever wrote. Gate and metric must be named as that convention requires or they
# never meet.
risk_max <- NA_real_
if (!is.null(risk) && length(risk)) {
  # Only packages the repository actually chose feed the gate. Packages that
  # ship with R are scored and reported, but gating on them would block every
  # candidate on properties of R itself.
  gated <- Filter(function(r) is.null(r$in_gate) || isTRUE(r$in_gate), risk)
  vals <- suppressWarnings(as.numeric(vapply(gated, function(r) {
    if (is.null(r$score)) NA_real_ else as.numeric(r$score)
  }, numeric(1))))
  vals <- vals[is.finite(vals)]
  if (length(vals)) risk_max <- max(vals)
}

row <- list(
  timestamp    = env_or("HARNESS_TIMESTAMP", "unset"),
  candidate_id = env_or("CANDIDATE_ID", "adhoc"),
  track        = env_or("HARNESS_TRACK", if (!is.null(manifest)) manifest$track else "unknown"),
  dimension    = env_or("CANDIDATE_DIMENSION", "none"),
  commit       = env_or("GITHUB_SHA", "local"),
  run_id       = env_or("GITHUB_RUN_ID", ""),
  image_digest = env_or("CANDIDATE_IMAGE_DIGEST", ""),
  base_digest  = env_or("BASE_IMAGE_DIGEST", ""),
  build_seconds = num(env_or("BUILD_SECONDS", ""), NA),
  image_size_mb = num(env_or("IMAGE_SIZE_MB", ""), NA),
  r_version     = if (!is.null(manifest)) manifest$r_version else NA,
  package_count = if (!is.null(manifest)) num(manifest$package_count) else NA,
  ppm_snapshot  = if (!is.null(manifest)) manifest$ppm_snapshot else "",
  nixpkgs_date  = if (!is.null(manifest)) manifest$nixpkgs_date else "",
  pq_passed  = if (!is.null(pq)) num(pq$passed, 0) else NA,
  pq_failed  = if (!is.null(pq)) num(pq$failed, 0) else NA,
  pq_skipped = if (!is.null(pq)) num(pq$skipped, 0) else NA,
  pq_strict   = if (!is.null(pq)) num(pq$strict, 0) else NA,
  pq_tolerant = if (!is.null(pq)) num(pq$tolerant, 0) else NA,
  max_abs_deviation = if (!is.null(pq)) num(pq$max_abs_deviation, NA) else NA,
  # How close the worst assertion came to its declared tolerance. A run passing
  # at 99% of tolerance is a warning the pass/fail counts cannot show.
  tolerance_utilisation = if (!is.null(pq)) num(pq$tolerance_utilisation, NA) else NA,
  result_checksums = if (!is.null(pq)) pq$result_checksums else NULL,
  delta_churn = if (!is.null(delta)) num(delta$layer3_packages$churn, 0) else NA,
  verdict     = if (!is.null(delta)) delta$verdict else "UNKNOWN",
  package_risk = risk_max,
  status = env_or("HARNESS_STATUS", "success")
)

line <- toJSON(row, auto_unbox = TRUE, null = "null", na = "null")
writeLines(line, file.path(outdir, "metrics-row.json"))
message("Metrics row:")
message(line)
