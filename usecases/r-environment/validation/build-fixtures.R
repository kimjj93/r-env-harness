#!/usr/bin/env Rscript
# PHASE 1 — Build reference fixtures.
#
# Run ONCE in a trusted, known-good environment. The output is committed
# qualification evidence: every later run compares against it.
#
#   Rscript validation/build-fixtures.R
#
# Fixtures are never hand-edited (AGENTS.md §1.5). Regenerating them is a
# deliberate, reviewed act — it redefines what "correct" means for this
# repository, so the PR must explain why.

suppressPackageStartupMessages({
  library(digest)
})

# Bootstrap: the helper defines harness_path(), so this one path is resolved
# relative to this script's own location rather than the working directory.
local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  root <- if (length(f)) dirname(dirname(normalizePath(f[1]))) else getwd()
  source(file.path(root, "validation", "R", "helper_compare-reference.R"))
})
source(usecase_path("validation/R/testcase_adsl.R"))
source(usecase_path("validation/R/testcase_adae.R"))
source(usecase_path("validation/R/testcase_numeric.R"))

out_dir <- fixture_dir()
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
message("Fixture directory: ", out_dir)
message("R version        : ", getRversion())

build_one <- function(name, generator, source_file) {
  # Critical packages are read from the test case's roxygen block, so that
  # changing them is a one-line documentation edit.
  critical <- read_critical_packages(source_file)
  message("\n[", name, "] critical packages: ",
          if (length(critical)) paste(critical, collapse = ", ") else "(none)")

  value <- generator()
  meta  <- capture_env_meta(critical)

  path <- file.path(out_dir, paste0(name, ".rda"))
  assign(paste0(name, "_reference"), value)
  assign(".validation_env_meta", meta)
  save(list = c(paste0(name, "_reference"), ".validation_env_meta"),
       file = path, compress = "xz")

  message("  wrote ", path)
  invisible(path)
}

build_one("adsl_summary", testcase_generate_adsl_summary,
          usecase_path("validation/R/testcase_adsl.R"))
build_one("adae_summary", testcase_generate_adae_summary,
          usecase_path("validation/R/testcase_adae.R"))
build_one("rng_kinds", testcase_generate_rng_kinds,
          usecase_path("validation/R/testcase_numeric.R"))
build_one("linalg", testcase_generate_linalg,
          usecase_path("validation/R/testcase_numeric.R"))

# Result checksums feed Layer 4 of the delta report.
checksums <- list(
  adsl = testcase_adsl_checksum(),
  adae = testcase_adae_checksum()
)
saveRDS(checksums, file.path(out_dir, "result-checksums.rds"))
message("\nResult checksums:")
for (n in names(checksums)) message("  ", n, ": ", substr(checksums[[n]], 1, 16), "...")

message("\nPhase 1 complete. Commit the fixtures together with the test cases.")
