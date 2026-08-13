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
# Optional: a copy of the library from the image under validation. Without it
# riskmetric assesses whatever happens to be installed on the CI runner, which
# made a package's score depend on whether it was incidentally a dependency of
# the scanner. Measured: dplyr scored 0.418 where installed and 0.95 where not.
# That is a property of the runner, not of the package.
image_lib <- if (length(args) >= 3) args[[3]] else Sys.getenv("IMAGE_LIB", "")
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

# Resolve each package to its directory INSIDE the image's library and assess
# that path directly.
#
# The obvious approach -- prepending the image library to .libPaths() -- was
# tried and is wrong: the image ships base R packages, so prepending it shadows
# the runner's own base library and riskmetric then fails to load at all. The
# scan reported "riskmetric unavailable" for all 78 packages and the check
# still went green.
#
# Using explicit paths keeps the runner's R intact and, more importantly, gives
# every package the SAME kind of reference. Mixing installed refs and remote
# refs in one table produced scores that were not comparable to each other.
image_pkg_dir <- function(p) ""
if (nzchar(image_lib) && dir.exists(image_lib)) {
  libs <- list.dirs(image_lib, recursive = TRUE, full.names = TRUE)
  libs <- libs[vapply(libs, function(d) {
    any(file.exists(file.path(d, new_pkgs, "DESCRIPTION")))
  }, logical(1))]
  if (length(libs)) {
    message("Image libraries found: ", paste(libs, collapse = ", "))
    image_pkg_dir <- function(p) {
      hit <- file.path(libs, p)
      hit <- hit[file.exists(file.path(hit, "DESCRIPTION"))]
      if (length(hit)) hit[[1]] else ""
    }
  } else {
    message("WARNING: image library given but no scanned package found in it: ", image_lib)
  }
}

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

# Packages carrying `Priority: base` or `Priority: recommended` ship WITH R.
# They are not a choice this repository makes, and they systematically look
# risky to riskmetric because they have no GitHub bug tracker, no vignettes and
# no public download counts. Measured on a full run, the nine highest-risk
# packages in the whole environment were mgcv, boot, KernSmooth, spatial, MASS,
# nlme, class, foreign and codetools -- every one of them shipped with R.
#
# They are still scored and still shown. What changes is that they do not feed
# the gate metric, because the gate exists to govern packages that were chosen.
# Hiding them would be an exemption; reporting them separately is a category.
priority_of <- function(p) {
  d <- image_pkg_dir(p)
  if (!nzchar(d)) return(NA_character_)
  pri <- tryCatch(read.dcf(file.path(d, "DESCRIPTION"), fields = "Priority")[[1]],
                  error = function(e) NA_character_)
  if (is.na(pri)) NA_character_ else trimws(pri)
}
ships_with_r <- vapply(new_pkgs, function(p) {
  pri <- priority_of(p)
  !is.na(pri) && pri %in% c("base", "recommended")
}, logical(1))
base_pkgs <- new_pkgs[ships_with_r]
scan_pkgs <- new_pkgs
if (length(base_pkgs)) {
  message("Ships with R (scored, excluded from gate): ", paste(base_pkgs, collapse = ", "))
}

rows <- list()
for (p in scan_pkgs) {
  res <- tryCatch({
    # This runs on the CI runner rather than inside the validated image, so a
    # scanned package is usually NOT installed here. Let riskmetric resolve it
    # locally when it can and fall back to the CRAN remote when it cannot, so
    # the source of the assessment is explicit rather than accidental.
    # Record WHERE the assessment came from. A score whose provenance is
    # invisible cannot be compared across runs: the same package assessed as an
    # installed library and as a remote CRAN entry gets materially different
    # numbers, and without the source recorded the difference looks like drift.
    pdir <- image_pkg_dir(p)
    src  <- if (nzchar(pdir)) "image" else "cran_remote"
    ref  <- if (src == "image") riskmetric::pkg_ref(pdir)
            else riskmetric::pkg_ref(p, source = "pkg_cran_remote")
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
         in_gate = !(p %in% base_pkgs),
         note = if (src == "image") "" else "not in image library; scored from CRAN metadata only")
  }, error = function(e) {
    list(package = p, score = NA_real_, weak = "",
         in_gate = !(p %in% base_pkgs),
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

fmt_rows <- function(rs) vapply(rs, function(r) sprintf("| `%s` | %s | %s | %s | %s |",
  r$package,
  ifelse(is.na(r$score), "n/a", format(round(r$score, 3), nsmall = 3)),
  band(r$score),
  ifelse(nzchar(r$weak), r$weak, "-"),
  ifelse(nzchar(r$note), r$note, "-")), character(1))

hdr <- c("| package | risk score | risk | weakest dimensions | note |", "|---|---|---|---|---|")
chosen  <- Filter(function(r) isTRUE(r$in_gate),  rows)
shipped <- Filter(function(r) !isTRUE(r$in_gate), rows)

md <- c("### Package risk (newly added)", "",
        "#### Chosen packages (these feed the gate)", "")
md <- c(md, if (length(chosen)) c(hdr, fmt_rows(chosen)) else "_None._")
if (length(shipped)) {
  md <- c(md, "",
          "#### Ships with R (scored, excluded from the gate)", "",
          "> These carry `Priority: base` or `Priority: recommended`, so they arrive",
          "> with R rather than being chosen. They score poorly because they have no",
          "> public bug tracker, vignettes or download counts, not because they are",
          "> risky. Shown rather than hidden, so the exclusion is visible.", "",
          hdr, fmt_rows(shipped))
}
md <- c(md, "",
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
