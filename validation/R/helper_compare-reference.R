# Reference comparison engine for Performance Qualification.
#
# Adapted from the design in pfizer-rd/rvalidation-refactored.
#
# The central rule: demand bit-for-bit equality ONLY when the environment is
# provably identical to the one that produced the baseline. When the environment
# has changed, bounded numeric drift is expected — but it must be quantified,
# declared in advance, and recorded.
#
# Demanding strictness unconditionally would make every legitimate upgrade look
# like a failure. Never demanding it would let real defects through unnoticed.

# ---------------------------------------------------------------------------
# Recorder — a side channel capturing per-assertion facts for the Phase 3 report.
# ---------------------------------------------------------------------------

.recorder <- new.env(parent = emptyenv())

recorder_start <- function() {
  .recorder$rows <- list()
  invisible(TRUE)
}

recorder_record <- function(case, path, business_tol, applied_tol,
                            max_abs_dev, critical, passed) {
  .recorder$rows[[length(.recorder$rows) + 1L]] <- list(
    case         = case,
    path         = path,
    business_tol = business_tol,
    applied_tol  = applied_tol,
    max_abs_dev  = max_abs_dev,
    critical     = paste(critical, collapse = ", "),
    passed       = passed
  )
  invisible(TRUE)
}

recorder_collect <- function() {
  rows <- .recorder$rows
  if (is.null(rows) || !length(rows)) {
    return(data.frame(
      case = character(0), path = character(0),
      business_tol = numeric(0), applied_tol = numeric(0),
      max_abs_dev = numeric(0), critical = character(0),
      passed = logical(0), stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, lapply(rows, function(r) {
    data.frame(r, stringsAsFactors = FALSE)
  }))
}

# ---------------------------------------------------------------------------
# Environment matching — decides strict vs. tolerant.
# ---------------------------------------------------------------------------

#' Does the live environment match the one that produced the fixture?
#'
#' Returns TRUE only when the R version AND every declared critical package
#' version are identical. Any difference at all routes the comparison to the
#' tolerant path.
helper_reference_env_matches <- function(meta, critical_packages = character(0)) {
  if (!identical(as.character(getRversion()), as.character(meta$r_version))) {
    return(FALSE)
  }
  for (pkg in critical_packages) {
    recorded <- meta$critical_pkgs[[pkg]]
    if (is.null(recorded)) return(FALSE)
    live <- tryCatch(as.character(utils::packageVersion(pkg)),
                     error = function(e) NA_character_)
    if (is.na(live) || !identical(as.character(recorded), live)) return(FALSE)
  }
  TRUE
}

#' Explain WHY the environment did not match.
#'
#' A bare TRUE/FALSE is not actionable in a regulatory report; the reviewer needs
#' to see which dimension moved.
helper_env_mismatch_reasons <- function(meta, critical_packages = character(0)) {
  reasons <- character(0)
  live_r <- as.character(getRversion())
  if (!identical(live_r, as.character(meta$r_version))) {
    reasons <- c(reasons, sprintf("R version: fixture=%s live=%s",
                                  meta$r_version, live_r))
  }
  for (pkg in critical_packages) {
    recorded <- meta$critical_pkgs[[pkg]]
    live <- tryCatch(as.character(utils::packageVersion(pkg)),
                     error = function(e) NA_character_)
    if (is.null(recorded)) {
      reasons <- c(reasons, sprintf("%s: absent from fixture metadata", pkg))
    } else if (is.na(live)) {
      reasons <- c(reasons, sprintf("%s: not installed", pkg))
    } else if (!identical(as.character(recorded), live)) {
      reasons <- c(reasons, sprintf("%s: fixture=%s live=%s", pkg, recorded, live))
    }
  }
  reasons
}

# ---------------------------------------------------------------------------
# The assertion.
# ---------------------------------------------------------------------------

#' Compare an object against a stored reference, strictly or tolerantly.
#'
#' @param object          value computed in the live environment
#' @param reference       value loaded from the committed fixture
#' @param meta            .validation_env_meta from the fixture
#' @param case            label for the report
#' @param critical_packages packages gating the strict path
#' @param tolerance       declared business tolerance for the tolerant path
helper_expect_reference_match <- function(object, reference, meta, case,
                                          critical_packages = character(0),
                                          tolerance = 1e-8) {
  strict <- helper_reference_env_matches(meta, critical_packages)

  num_obj <- suppressWarnings(as.numeric(unlist(object)))
  num_ref <- suppressWarnings(as.numeric(unlist(reference)))

  max_dev <- if (length(num_obj) == length(num_ref) &&
                 length(num_obj) > 0 &&
                 !all(is.na(num_obj)) && !all(is.na(num_ref))) {
    suppressWarnings(max(abs(num_obj - num_ref), na.rm = TRUE))
  } else {
    NA_real_
  }
  if (!is.finite(max_dev)) max_dev <- NA_real_

  if (strict) {
    applied <- 0
    path    <- "Strict (exact)"
    passed  <- isTRUE(all.equal(object, reference, tolerance = 0))
  } else {
    applied <- tolerance
    path    <- "Tolerant"
    passed  <- !is.na(max_dev) && max_dev <= tolerance
    if (is.na(max_dev)) {
      # Non-numeric content cannot be compared tolerantly; fall back to
      # structural equality rather than silently passing.
      passed <- isTRUE(all.equal(object, reference))
    }
  }

  recorder_record(
    case = case, path = path,
    business_tol = tolerance, applied_tol = applied,
    max_abs_dev = max_dev, critical = critical_packages, passed = passed
  )

  if (!passed && !strict) {
    reasons <- helper_env_mismatch_reasons(meta, critical_packages)
    message(sprintf("[%s] tolerant comparison FAILED. Environment differences:\n  %s",
                    case, paste(reasons, collapse = "\n  ")))
  }

  testthat::expect_true(
    passed,
    label = sprintf("%s [%s, tol=%g, max_abs_dev=%s]",
                    case, path, applied,
                    ifelse(is.na(max_dev), "n/a", format(max_dev, digits = 3)))
  )
}

# ---------------------------------------------------------------------------
# Fixture I/O.
# ---------------------------------------------------------------------------

fixture_dir <- function() {
  base <- Sys.getenv("RVALIDATION_FIXTURE_DIR",
                     unset = "validation/fixtures/references")
  ver <- Sys.getenv("VALIDATION_REF_VERSION", unset = "")
  if (!nzchar(ver)) {
    ver <- paste0("R-", paste(getRversion()[1, 1:2], collapse = "."))
  }
  file.path(base, ver)
}

load_fixture <- function(name) {
  path <- file.path(fixture_dir(), paste0(name, ".rda"))
  if (!file.exists(path)) {
    stop("Fixture not found: ", path,
         "\nRun Phase 1 (validation/build-fixtures.R) in a trusted environment.")
  }
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  as.list(e)
}

#' Capture the environment metadata stored alongside every fixture.
#'
#' Without this record a baseline is an unattributable number.
capture_env_meta <- function(critical_packages = character(0)) {
  vers <- list()
  for (pkg in critical_packages) {
    vers[[pkg]] <- tryCatch(as.character(utils::packageVersion(pkg)),
                            error = function(e) NA_character_)
  }
  list(
    r_version     = as.character(getRversion()),
    critical_pkgs = vers,
    session_info  = tryCatch(
      paste(utils::capture.output(sessioninfo::session_info()), collapse = "\n"),
      error = function(e) paste(utils::capture.output(utils::sessionInfo()),
                                collapse = "\n")
    ),
    captured_at   = "fixture-build"   # never a timestamp: it would break determinism
  )
}

#' Read the `@section Critical Packages:` roxygen block from a test case file.
#'
#' Declaring critical packages in documentation means adding or removing one is a
#' single-line docs change, with no build system edits.
read_critical_packages <- function(file) {
  if (!file.exists(file)) return(character(0))
  lines <- readLines(file, warn = FALSE)
  start <- grep("^#'\\s*@section Critical Packages:", lines)
  if (!length(start)) return(character(0))
  out <- character(0)
  i <- start[[1]] + 1L
  while (i <= length(lines) && grepl("^#'", lines[[i]])) {
    txt <- sub("^#'\\s*", "", lines[[i]])
    if (grepl("^@", txt) || !nzchar(trimws(txt))) break
    out <- c(out, txt)
    i <- i + 1L
  }
  pkgs <- unlist(strsplit(paste(out, collapse = " "), "[,.]"))
  pkgs <- trimws(pkgs)
  pkgs[nzchar(pkgs)]
}
