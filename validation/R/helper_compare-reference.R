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

#' Describe the numerical backend the current session is using.
#'
#' Floating-point results from `det()`, `eigen()`, `solve()` and friends are
#' produced by BLAS/LAPACK, not by R itself. Two sessions with identical R and
#' package versions will still disagree in the last bits if they are linked
#' against different BLAS builds or run on a different CPU architecture. The
#' strict (exact) path is only defensible if that backend is part of the
#' environment identity, so it is recorded and compared like any other pin.
#'
#' Known limit: an emulated x86_64 container (e.g. an amd64 image running on
#' Apple silicon under Rosetta/QEMU) reports exactly the same platform, arch
#' and BLAS strings as a native x86_64 runner, yet can differ in the last bits
#' because the emulator makes different FMA and rounding choices. No in-process
#' fingerprint can detect this. The defence is provenance, not introspection:
#' fixtures are built by `.github/workflows/build-fixtures.yml` on a CI runner,
#' never on a workstation.
numeric_backend_meta <- function() {
  si <- tryCatch(utils::sessionInfo(), error = function(e) NULL)
  norm <- function(x) {
    if (is.null(x) || length(x) == 0 || is.na(x[1])) return(NA_character_)
    # Keep the library's file name only: the path differs between an image and
    # a Nix store without the implementation actually differing.
    basename(as.character(x[1]))
  }
  list(
    platform = tryCatch(R.version$platform, error = function(e) NA_character_),
    arch     = tryCatch(R.version$arch,     error = function(e) NA_character_),
    blas     = norm(si$BLAS),
    lapack   = norm(si$LAPACK)
  )
}

#' Does the live environment match the one that produced the fixture?
#'
#' Returns TRUE only when the R version, the numerical backend (CPU
#' architecture and BLAS/LAPACK build) AND every declared critical package
#' version are identical. Any difference at all routes the comparison to the
#' tolerant path.
helper_reference_env_matches <- function(meta, critical_packages = character(0)) {
  if (!identical(as.character(getRversion()), as.character(meta$r_version))) {
    return(FALSE)
  }
  # A fixture recorded before the backend was captured cannot support an exact
  # claim: absence of evidence is not evidence of a match.
  if (is.null(meta$backend)) return(FALSE)
  live_backend <- numeric_backend_meta()
  for (k in c("platform", "arch", "blas", "lapack")) {
    if (!identical(as.character(meta$backend[[k]]),
                   as.character(live_backend[[k]]))) {
      return(FALSE)
    }
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
  if (is.null(meta$backend)) {
    reasons <- c(reasons,
                 "numerical backend: not recorded in fixture (predates backend capture)")
  } else {
    live_backend <- numeric_backend_meta()
    labels <- c(platform = "platform", arch = "CPU arch",
                blas = "BLAS", lapack = "LAPACK")
    for (k in names(labels)) {
      fx <- as.character(meta$backend[[k]])
      lv <- as.character(live_backend[[k]])
      if (!identical(fx, lv)) {
        reasons <- c(reasons, sprintf("%s: fixture=%s live=%s",
                                      labels[[k]],
                                      if (length(fx)) fx else "NA",
                                      if (length(lv)) lv else "NA"))
      }
    }
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

# Locate the project root ONCE, absolutely.
#
# This must not be a relative path. testthat changes the working directory to
# the test file's own directory while running, so a relative fixture path
# resolves correctly in a plain Rscript session and then fails inside the test
# suite. That failure surfaces as an ordinary assertion failure, which is
# indistinguishable from genuine numeric drift -- a configuration error wearing
# the costume of a validation finding. In a harness whose entire purpose is
# trustworthy pass/fail signals, that is the most damaging bug available, so
# the root is resolved explicitly and verified.
harness_root <- function() {
  explicit <- Sys.getenv("HARNESS_ROOT", unset = "")
  if (nzchar(explicit)) return(normalizePath(explicit, mustWork = FALSE))

  # Walk upward looking for a directory that is unmistakably the project root.
  d <- normalizePath(getwd(), mustWork = FALSE)
  for (i in 1:6) {
    if (file.exists(file.path(d, "AGENTS.md")) ||
        dir.exists(file.path(d, "validation", "fixtures"))) {
      return(d)
    }
    parent <- dirname(d)
    if (identical(parent, d)) break
    d <- parent
  }
  # Container default. Explicit is better than a silently wrong relative path.
  if (dir.exists("/project")) "/project" else normalizePath(getwd())
}

# Resolve any repository-relative path against the harness root. Every path in
# the test cases goes through this, for the reason above: testthat moves the
# working directory, so a bare relative path is a latent failure.
harness_path <- function(...) file.path(harness_root(), ...)

fixture_dir <- function() {
  base <- Sys.getenv("RVALIDATION_FIXTURE_DIR", unset = "")
  if (!nzchar(base)) {
    base <- file.path(harness_root(), "validation", "fixtures", "references")
  }
  ver <- Sys.getenv("VALIDATION_REF_VERSION", unset = "")
  if (!nzchar(ver)) {
    ver <- paste0("R-", paste(getRversion()[1, 1:2], collapse = "."))
  }
  file.path(base, ver)
}

load_fixture <- function(name) {
  path <- file.path(fixture_dir(), paste0(name, ".rda"))
  if (!file.exists(path)) {
    # Distinguish "the baseline is missing" from "the results changed". They
    # demand opposite responses: one is a setup step, the other is a finding.
    stop("FIXTURE MISSING (this is a setup problem, not a validation finding): ",
         path,
         "\nRun Phase 1 (validation/build-fixtures.R) in a trusted environment",
         "\nand commit the resulting baselines. Resolved harness root: ",
         harness_root())
  }
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  # all.names = TRUE is essential: the environment metadata is stored as
  # `.validation_env_meta`, and as.list() omits dot-prefixed names by default.
  # Without it the metadata silently vanishes, every comparison quietly
  # degrades from strict to tolerant, and the suite reports a clean pass while
  # running the WEAKER check. Failing toward the weaker check is the most
  # dangerous direction available to a validation harness.
  as.list(e, all.names = TRUE)
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
    backend       = numeric_backend_meta(),
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
