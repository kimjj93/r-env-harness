#!/usr/bin/env Rscript
# riskmetric scan for newly added packages.
#
#   Rscript usecases/r-environment/bin/riskmetric_scan.R <delta.json> [outdir]
#
# Scans ONLY packages that are new in this change. Re-scoring the whole library
# on every PR produces noise that trains reviewers to skip the section.
#
# Scope limit (skills/package-risk/SKILL.md): riskmetric scores development
# practice and community trust, NOT statistical correctness. A good score is
# never evidence that results are right — that is what PQ is for.

suppressPackageStartupMessages(library(jsonlite))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

args <- commandArgs(trailingOnly = TRUE)
delta_f <- if (length(args) >= 1) args[[1]] else "artifacts/delta.json"
outdir  <- if (length(args) >= 2) args[[2]] else "artifacts"
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

emit <- function(rows, md) {
  write(toJSON(rows, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file.path(outdir, "risk.json"))
  writeLines(md, file.path(outdir, "risk.md"))
  message("Wrote ", file.path(outdir, "risk.json"))
}

if (!file.exists(delta_f)) {
  emit(list(), c("### Package risk (newly added)", "",
                 "_No delta report available._"))
  quit(status = 0L, save = "no")
}

delta <- fromJSON(delta_f, simplifyVector = FALSE)
added <- delta$layer3_packages$added
new_pkgs <- vapply(added, function(x) x$package, character(1))

if (!length(new_pkgs)) {
  # Stating this explicitly matters: silence would be indistinguishable from
  # the scan not having run.
  emit(list(), c("### Package risk (newly added)", "",
                 "No newly added packages."))
  quit(status = 0L, save = "no")
}

message("Scanning ", length(new_pkgs), " new package(s): ",
        paste(new_pkgs, collapse = ", "))

if (!requireNamespace("riskmetric", quietly = TRUE)) {
  md <- c("### Package risk (newly added)", "",
          sprintf("New packages: %s", paste(sprintf("`%s`", new_pkgs), collapse = ", ")),
          "",
          "> `{riskmetric}` is not available to the scanner, so scores could not be",
          "> computed. Reporting the gap rather than omitting the section.",
          "",
          "> This is a **tooling** failure, not a finding about these packages.",
          "> The scan runs on the CI runner; check the riskmetric install step.")
  emit(lapply(new_pkgs, function(p) list(package = p, score = NA, note = "riskmetric unavailable")), md)
  quit(status = 0L, save = "no")
}

rows <- list()
for (p in new_pkgs) {
  res <- tryCatch({
    # This runs on the CI runner rather than inside the validated image, so a
    # scanned package is usually NOT installed here. Let riskmetric resolve it
    # locally when it can and fall back to the CRAN remote when it cannot, so
    # the source of the assessment is explicit rather than accidental.
    ref <- tryCatch(riskmetric::pkg_ref(p),
                    error = function(e) riskmetric::pkg_ref(p, source = "pkg_cran_remote"))
    sc  <- riskmetric::pkg_score(riskmetric::pkg_assess(ref))

    # summarize_scores() is the documented way to collapse the assessment
    # tibble. An earlier version read `sc$pkg_score`, a column riskmetric does
    # not produce, so every package errored into "assessment failed".
    score <- suppressWarnings(as.numeric(riskmetric::summarize_scores(sc)))
    if (!length(score)) score <- NA_real_

    # Per-metric scores run the OPPOSITE way to the summary: a metric is 1 when
    # the good practice is present, while the summary is a RISK score where
    # higher is worse. Measured, to make sure this is not a guess:
    #   dplyr (vignettes+news+bug reports) -> 0.418
    #   utils (no news, no bug reports)    -> 0.687
    # So a low metric value is a weakness, and a high summary is risk.
    weak <- character(0)
    for (m in c("covr_coverage", "has_vignettes", "has_news",
                "has_bug_reports_url", "export_help", "downloads_1yr",
                "has_source_control", "has_maintainer")) {
      if (is.null(sc[[m]])) next
      v <- tryCatch(suppressWarnings(as.numeric(sc[[m]][[1]])), error = function(e) NA_real_)
      if (!is.na(v) && v < 0.5) weak <- c(weak, m)
    }
    list(package = p, score = score,
         weak = if (length(weak)) paste(weak, collapse = ", ") else "",
         note = "")
  }, error = function(e) {
    list(package = p, score = NA_real_, weak = "",
         note = paste("assessment failed:", conditionMessage(e)))
  })
  rows[[length(rows) + 1L]] <- res
}

# Higher summarize_scores() means MORE risk, so the bands run the other way
# round from the obvious reading. Getting this backwards would have flagged the
# best-maintained packages as dangerous and waved the worst ones through.
band <- function(s) {
  if (is.na(s)) return("unknown")
  if (s >= 0.8) "**HIGH**" else if (s >= 0.5) "medium" else "low"
}

md <- c("### Package risk (newly added)", "",
        "| package | risk score | risk | weakest dimensions | note |",
        "|---|---|---|---|---|",
        vapply(rows, function(r) sprintf("| `%s` | %s | %s | %s | %s |",
          r$package,
          ifelse(is.na(r$score), "n/a", format(round(r$score, 3), nsmall = 3)),
          band(r$score),
          ifelse(nzchar(r$weak), r$weak, "-"),
          ifelse(nzchar(r$note), r$note, "-")), character(1)),
        "",
        "",
        "> **Higher score = higher risk.** `summarize_scores()` returns a risk score,",
        "> so 0.42 is better than 0.69. Verified against known packages.",
        "",
        "> Scores reflect development practice and community trust, not statistical",
        "> correctness. Correctness is established by Performance Qualification.")

emit(rows, md)

# A green check that meant nothing is what let this capability sit broken for
# the life of the project: the step carried continue-on-error, so "passed" only
# ever meant "did not crash" while every package reported a failed assessment.
#
# Partial failures stay non-fatal -- one unreachable package is data, and the
# table reports it. Every single package failing is not data, it is the scanner
# being broken, and it is reported as a failure.
failed_all <- length(rows) > 0 &&
  all(vapply(rows, function(r) is.na(r$score %||% NA), logical(1)))
if (failed_all) {
  message("ERROR: riskmetric is installed but produced no score for any of the ",
          length(rows), " package(s) scanned. This is a scanner failure, not a ",
          "finding about these packages.")
  quit(status = 1L, save = "no")
}

quit(status = 0L, save = "no")

# Advisory only. A low score prompts scrutiny; it does not auto-block, because
# the decision to accept a package's risk belongs to the human reviewer.
quit(status = 0L, save = "no")
