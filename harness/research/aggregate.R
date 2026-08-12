#!/usr/bin/env Rscript
# harness/research/aggregate.R
#
# Reads a week of telemetry rows and picks at most ONE candidate worth a human's
# attention.
#
# The bar is deliberately high. A proposal costs a reviewer real time, so a
# candidate must not merely work -- it must beat the incumbent on the ranking
# policy declared in candidates.yml. If nothing clears the bar we return no
# recommendation, and the weekly workflow opens nothing at all. A week with no
# PR is a successful week, not a broken pipeline.
#
# Usage: Rscript aggregate.R <metrics.jsonl> <candidates.yml> <outdir>

args    <- commandArgs(trailingOnly = TRUE)
metrics_file <- if (length(args) >= 1) args[1] else "evidence/metrics/metrics.jsonl"
cand_file    <- if (length(args) >= 2) args[2] else "harness/research/candidates.yml"
outdir       <- if (length(args) >= 3) args[3] else "artifacts"

dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("jsonlite is required")
}

# ---- load telemetry -------------------------------------------------------

if (!file.exists(metrics_file)) {
  message("No telemetry file at ", metrics_file, " -- nothing to aggregate.")
  jsonlite::write_json(list(recommendation = "NONE",
                            reason = "no telemetry recorded"),
                       file.path(outdir, "recommendation.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  quit(status = 0)
}

lines <- readLines(metrics_file, warn = FALSE)
lines <- lines[nzchar(trimws(lines))]
rows  <- lapply(lines, function(l) tryCatch(jsonlite::fromJSON(l), error = function(e) NULL))
rows  <- Filter(Negate(is.null), rows)

if (length(rows) == 0) {
  message("Telemetry file is empty.")
  jsonlite::write_json(list(recommendation = "NONE", reason = "no parseable rows"),
                       file.path(outdir, "recommendation.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  quit(status = 0)
}

# Only consider the last 7 days. Older evidence describes an environment that
# may no longer be the incumbent.
now    <- Sys.time()
in_win <- vapply(rows, function(r) {
  ts <- tryCatch(as.POSIXct(r$timestamp %||% NA, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                 error = function(e) NA)
  !is.na(ts) && difftime(now, ts, units = "days") <= 7
}, logical(1))
week <- rows[in_win]

message("Telemetry rows total: ", length(rows), " | within 7d: ", length(week))

if (length(week) == 0) {
  jsonlite::write_json(list(recommendation = "NONE",
                            reason = "no runs in the last 7 days"),
                       file.path(outdir, "recommendation.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  quit(status = 0)
}

# ---- gates ----------------------------------------------------------------
# Read thresholds from candidates.yml so policy lives in one reviewable place
# rather than being hard-coded here.

gate_pq_max   <- 0
forbidden     <- c("FAIL_DEVIATION", "FAIL_NONDETERMINISM")
risk_min      <- 0.5
if (file.exists(cand_file)) {
  y <- readLines(cand_file, warn = FALSE)
  m <- grep("^\\s*pq_failed_max:", y, value = TRUE)
  if (length(m)) gate_pq_max <- as.numeric(sub(".*:\\s*", "", m[1]))
  m <- grep("^\\s*riskmetric_min:", y, value = TRUE)
  if (length(m)) risk_min <- as.numeric(sub(".*:\\s*", "", m[1]))
}

# The value the candidate actually tested, recovered from the dimension it
# varies. A candidate with no realised value cannot be turned into a pin edit.
realised_value <- function(r) {
  v <- switch(as.character(r$dimension %||% ""),
    "ppm_snapshot" = r$ppm_snapshot %||% "",
    "nixpkgs_date" = r$nixpkgs_date %||% "",
    "base_digest"  = r$base_digest  %||% "",
    "")
  if (is.null(v) || length(v) == 0 || is.na(v)) "" else as.character(v)
}

passes_gates <- function(r) {
  reasons <- character(0)
  if ((r$status %||% "unknown") != "success")        reasons <- c(reasons, sprintf("status=%s", r$status %||% "unknown"))
  if ((r$verdict %||% "") %in% forbidden)            reasons <- c(reasons, sprintf("verdict=%s", r$verdict))
  if (as.numeric(r$pq_failed %||% 0) > gate_pq_max)  reasons <- c(reasons, sprintf("pq_failed=%s", r$pq_failed))
  rm_score <- suppressWarnings(as.numeric(r$riskmetric_min %||% NA))
  if (!is.na(rm_score) && rm_score < risk_min)       reasons <- c(reasons, sprintf("riskmetric_min=%.2f", rm_score))
  # A candidate that cannot be expressed as an edit to a pin file is not a
  # proposal candidate. Leaving such rows eligible let a no-op win the ranking
  # and then abort the week, so a genuinely good candidate was never proposed:
  # the loop looked healthy while silently proposing nothing.
  if (!nzchar(realised_value(r))) {
    reasons <- c(reasons, sprintf("no realised value for dimension '%s' (not actionable)",
                                  r$dimension %||% "none"))
  }
  list(ok = length(reasons) == 0, reasons = reasons)
}

# ---- keep the newest row per candidate ------------------------------------

by_id <- list()
for (r in week) {
  id <- r$candidate_id %||% "unknown"
  if (is.null(by_id[[id]]) || (r$timestamp %||% "") > (by_id[[id]]$timestamp %||% "")) {
    by_id[[id]] <- r
  }
}

summary_rows <- lapply(names(by_id), function(id) {
  r <- by_id[[id]]
  g <- passes_gates(r)
  # The value the candidate actually tested. Without it a proposal has nothing
  # to write into the pin file, so propose.R silently produced an empty edit and
  # every candidate looked like a no-op. metrics.R records the realised value
  # per track in the manifest fields rather than in a generic `value` column,
  # so recover it from the dimension being varied.
  realised <- realised_value(r)
  data.frame(
    candidate_id  = id,
    track         = r$track   %||% NA_character_,
    dimension     = r$dimension %||% NA_character_,
    value         = as.character(realised),
    status        = r$status  %||% NA_character_,
    verdict       = r$verdict %||% NA_character_,
    pq_passed     = as.numeric(r$pq_passed %||% NA),
    pq_failed     = as.numeric(r$pq_failed %||% NA),
    tol_util      = as.numeric(r$tolerance_utilisation %||% NA),
    # metrics.R writes this as `delta_churn`; `package_churn` was a name that
    # never existed, which silently produced NA and let churn drop out of the
    # ranking entirely. Accept both so old telemetry rows still aggregate.
    pkg_churn     = as.numeric(r$delta_churn %||% r$package_churn %||% NA),
    build_seconds = as.numeric(r$build_seconds %||% NA),
    image_size_mb = as.numeric(r$image_size_mb %||% NA),
    eligible      = g$ok,
    blocked_by    = paste(g$reasons, collapse = "; "),
    stringsAsFactors = FALSE
  )
})
summary_df <- do.call(rbind, summary_rows)
summary_df <- summary_df[order(summary_df$candidate_id), , drop = FALSE]

write.csv(summary_df, file.path(outdir, "weekly-summary.csv"), row.names = FALSE)

# ---- rank the eligible ----------------------------------------------------
# Order encodes the policy: results stability first, then how much tolerance
# headroom remains, then how little churn a reviewer must read, then speed.
# Build time is last on purpose -- a faster build never justifies a result change.

eligible <- summary_df[summary_df$eligible, , drop = FALSE]

if (nrow(eligible) == 0) {
  message("No candidate cleared the gates. Opening no proposal.")
  jsonlite::write_json(
    list(recommendation = "NONE",
         reason = "no candidate cleared the quality gates",
         evaluated = nrow(summary_df),
         detail = summary_df),
    file.path(outdir, "recommendation.json"), auto_unbox = TRUE, pretty = TRUE)
  quit(status = 0)
}

stability_rank <- ifelse(eligible$verdict %in% c("IDENTICAL"), 0,
                  ifelse(eligible$verdict %in% c("PASS_WITH_CHANGES"), 1,
                  ifelse(eligible$verdict %in% c("TOLERANT_DRIFT"), 2, 3)))

ord <- order(stability_rank,
             ifelse(is.na(eligible$tol_util), 1, eligible$tol_util),
             ifelse(is.na(eligible$pkg_churn), 9999, eligible$pkg_churn),
             ifelse(is.na(eligible$build_seconds), 9e9, eligible$build_seconds))

winner <- eligible[ord[1], , drop = FALSE]

message("Recommended candidate: ", winner$candidate_id,
        " (verdict=", winner$verdict, ", churn=", winner$pkg_churn, ")")

jsonlite::write_json(
  list(recommendation = "PROPOSE",
       candidate = as.list(winner),
       runner_up = if (nrow(eligible) > 1) as.list(eligible[ord[2], , drop = FALSE]) else NULL,
       evaluated = nrow(summary_df),
       eligible  = nrow(eligible),
       detail    = summary_df,
       raw       = by_id[[winner$candidate_id]]),
  file.path(outdir, "recommendation.json"), auto_unbox = TRUE, pretty = TRUE, na = "null")

message("Wrote ", file.path(outdir, "recommendation.json"))
