#!/usr/bin/env Rscript
# riskmetric scan for newly added packages.
#
#   Rscript harness/riskmetric_scan.R <delta.json> [outdir]
#
# Scans ONLY packages that are new in this change. Re-scoring the whole library
# on every PR produces noise that trains reviewers to skip the section.
#
# Scope limit (skills/package-risk/SKILL.md): riskmetric scores development
# practice and community trust, NOT statistical correctness. A good score is
# never evidence that results are right — that is what PQ is for.

suppressPackageStartupMessages(library(jsonlite))

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
          "> `{riskmetric}` is not installed in this image, so scores could not be",
          "> computed. Reporting the gap rather than omitting the section.")
  emit(lapply(new_pkgs, function(p) list(package = p, score = NA, note = "riskmetric unavailable")), md)
  quit(status = 0L, save = "no")
}

rows <- list()
for (p in new_pkgs) {
  res <- tryCatch({
    ref <- riskmetric::pkg_ref(p)
    as <- riskmetric::pkg_assess(ref)
    sc <- riskmetric::pkg_score(as)
    score <- suppressWarnings(as.numeric(sc$pkg_score[[1]]))

    weak <- character(0)
    for (m in c("has_tests", "covr_coverage", "has_vignettes", "has_news",
                "has_bug_reports_url", "export_help", "downloads_1yr")) {
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

band <- function(s) {
  if (is.na(s)) return("unknown")
  if (s >= 0.8) "low" else if (s >= 0.5) "medium" else "**HIGH**"
}

md <- c("### Package risk (newly added)", "",
        "| package | score | risk | weakest dimensions | note |",
        "|---|---|---|---|---|",
        vapply(rows, function(r) sprintf("| `%s` | %s | %s | %s | %s |",
          r$package,
          ifelse(is.na(r$score), "n/a", format(round(r$score, 3), nsmall = 3)),
          band(r$score),
          ifelse(nzchar(r$weak), r$weak, "-"),
          ifelse(nzchar(r$note), r$note, "-")), character(1)),
        "",
        "> Scores reflect development practice and community trust, not statistical",
        "> correctness. Correctness is established by Performance Qualification.")

emit(rows, md)

# Advisory only. A low score prompts scrutiny; it does not auto-block, because
# the decision to accept a package's risk belongs to the human reviewer.
quit(status = 0L, save = "no")
