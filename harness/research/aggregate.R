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
# Default resolves through the use case, so the harness never names the file.
cand_file    <- if (length(args) >= 2) args[2] else {
  uc <- tryCatch(system2("harness/usecase", "root", stdout = TRUE, stderr = NULL),
                 error = function(e) character(0))
  if (length(uc) && nzchar(uc[[1]])) file.path(uc[[1]], "candidates.yml") else ""
}
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

gate_checks_max <- 0
forbidden       <- c("FAIL_DEVIATION", "FAIL_NONDETERMINISM")

# Gates the use case declares for itself, as `<field>_min:` / `<field>_max:`
# lines. The harness enforces thresholds without knowing what any field means,
# which is what lets a different domain add its own gate without touching this.
extra_gates <- list()
if (file.exists(cand_file)) {
  y <- readLines(cand_file, warn = FALSE)
  m <- grep("^\\s*checks_failed_max:", y, value = TRUE)
  if (length(m)) gate_checks_max <- as.numeric(sub(".*:\\s*", "", m[1]))
  for (line in grep("^\\s{4,}[a-z_]+_(min|max):", y, value = TRUE)) {
    key <- trimws(sub(":.*", "", line))
    val <- suppressWarnings(as.numeric(sub(".*:\\s*", "", line)))
    if (!is.na(val) && !key %in% c("checks_failed_max")) extra_gates[[key]] <- val
  }
}

# The value the candidate actually tested. The research loop records it on every
# row as `candidate_value`; a row without one cannot be turned into an edit.
realised_value <- function(r) {
  v <- r$candidate_value %||% r$value %||% ""
  if (is.null(v) || length(v) == 0 || is.na(v)) "" else as.character(v)
}

passes_gates <- function(r) {
  reasons <- character(0)
  if ((r$status %||% "unknown") != "success")        reasons <- c(reasons, sprintf("status=%s", r$status %||% "unknown"))
  if ((r$verdict %||% "") %in% forbidden)            reasons <- c(reasons, sprintf("verdict=%s", r$verdict))
  failed <- as.numeric(r$checks_failed %||% r$pq_failed %||% 0)
  if (failed > gate_checks_max)                      reasons <- c(reasons, sprintf("checks_failed=%s", failed))
  # Domain-declared thresholds, applied by name. `foo_min: 0.5` fails any row
  # whose `foo` is below 0.5; `foo_max` is the mirror image.
  for (key in names(extra_gates)) {
    field <- sub("_(min|max)$", "", key)
    obs   <- suppressWarnings(as.numeric(r[[field]] %||% NA))
    if (is.na(obs)) next
    lim <- extra_gates[[key]]
    bad <- if (grepl("_min$", key)) obs < lim else obs > lim
    if (bad) reasons <- c(reasons, sprintf("%s=%s (gate %s)", field, format(obs), key))
  }
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

# ---- a declared gate that never evaluates is not a gate --------------------
#
# passes_gates() skips a threshold when the row does not carry the field, which
# is right for one row: a candidate that legitimately has nothing to say about a
# dimension should not be failed for silence.
#
# It is wrong for ALL rows. If a gate is declared and no row in the window ever
# carried its field, the gate has never once been evaluated -- and because
# skipping is silent, it reports the same way as passing. This is not
# hypothetical: a threshold in this repository sat in a use case manifest
# looking like protection for the whole life of the project, while the tool
# meant to produce its input was never installed anywhere, so every row carried
# null and the gate never fired.
#
# This is the fourth time a gate that could not find its input answered weaker
# instead of failing. Report it as loudly as a breach, because a gate believed
# to be active and in fact dead is worse than no gate: it buys confidence that
# was never earned.
dead_gates <- character(0)
for (key in names(extra_gates)) {
  field <- sub("_(min|max)$", "", key)
  observed <- vapply(by_id, function(r) {
    v <- suppressWarnings(as.numeric(r[[field]] %||% NA))
    !is.na(v)
  }, logical(1))
  if (!any(observed)) dead_gates <- c(dead_gates, sprintf("%s (field `%s` never measured)", key, field))
}
if (length(dead_gates)) {
  msg <- paste0(
    "DEAD GATE: declared but never evaluated across ", length(by_id), " candidate row(s):\n  - ",
    paste(dead_gates, collapse = "\n  - "),
    "\nEither start measuring the field, or remove the threshold. A gate that ",
    "cannot be evaluated is not protection, it is the appearance of protection."
  )
  message(msg)
  writeLines(dead_gates, file.path(outdir, "dead-gates.txt"))
}

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
