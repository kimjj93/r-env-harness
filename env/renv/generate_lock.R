#!/usr/bin/env Rscript
# Generate env/renv/renv.lock from the dated PPM snapshot.
#
# This is the GENERATOR. `renv.lock` is a generated artifact — change the
# package set or snapshot date here, re-run, and commit the result. Do not
# hand-edit the lockfile (AGENTS.md §1.4).
#
# Usage:  Rscript env/renv/generate_lock.R [snapshot_date] [output_path]
#
# It resolves the FULL recursive dependency closure at the snapshot date, so the
# lockfile describes every package that will actually be installed rather than
# only the ones we named.

args <- commandArgs(trailingOnly = TRUE)
snapshot <- if (length(args) >= 1) args[[1]] else "2025-01-15"
outfile  <- if (length(args) >= 2) args[[2]] else "env/renv/renv.lock"

codename  <- "noble"   # must match rocker/r-ver:4.4.2 (Ubuntu 24.04)
r_version <- "4.4.2"
repo_url  <- sprintf(
  "https://packagemanager.posit.co/cran/__linux__/%s/%s", codename, snapshot
)

# Direct dependencies: the pharmaverse ADaM payload plus the harness's own
# runtime needs (validation, delta reporting, manifests).
direct <- c(
  "admiral",          # ADaM derivation
  "pharmaversesdtm",  # synthetic SDTM source data
  "dplyr",            # data manipulation
  "tidyr",
  "lubridate",
  "stringr",
  "jsonlite",         # lockfile / delta / manifest I/O
  "sessioninfo",      # environment manifest
  "testthat",         # PQ execution
  "xml2",             # JUnit output
  "digest"            # result checksums
)

message("Snapshot : ", snapshot)
message("Repo     : ", repo_url)

db <- available.packages(repos = repo_url, type = "source")
if (nrow(db) == 0) stop("No packages found at snapshot ", snapshot)
message("Index    : ", nrow(db), " packages")

missing <- setdiff(direct, rownames(db))
if (length(missing)) {
  stop("Not available at this snapshot: ", paste(missing, collapse = ", "))
}

# Recursive closure over hard dependencies. Recommended/base packages ship with
# R itself and are pinned by the base image digest, so they are excluded here.
closure <- tools::package_dependencies(
  packages  = direct,
  db        = db,
  which     = c("Depends", "Imports", "LinkingTo"),
  recursive = TRUE
)
all_pkgs <- sort(unique(c(direct, unlist(closure, use.names = FALSE))))

base_pkgs <- rownames(installed.packages(priority = "base"))
if (length(base_pkgs) == 0) {
  base_pkgs <- c("base", "compiler", "datasets", "grDevices", "graphics",
                 "grid", "methods", "parallel", "splines", "stats", "stats4",
                 "tcltk", "tools", "utils")
}
all_pkgs <- setdiff(all_pkgs, base_pkgs)
all_pkgs <- intersect(all_pkgs, rownames(db))
message("Closure  : ", length(all_pkgs), " packages")

records <- lapply(all_pkgs, function(p) {
  list(
    Package    = p,
    Version    = unname(db[p, "Version"]),
    Source     = "Repository",
    Repository = "CRAN"
  )
})
names(records) <- all_pkgs

lock <- list(
  R = list(
    Version      = r_version,
    Repositories = list(list(Name = "CRAN", URL = repo_url))
  ),
  Packages = records
)

dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)

# Hand-rolled JSON so this script has zero package dependencies and can run in a
# bare R installation before anything is restored.
esc <- function(x) gsub('"', '\\\\"', x, fixed = FALSE)
con <- file(outfile, open = "wt")
on.exit(close(con))
wl <- function(...) writeLines(paste0(...), con)

wl("{")
wl('  "R": {')
wl('    "Version": "', r_version, '",')
wl('    "Repositories": [')
wl('      {')
wl('        "Name": "CRAN",')
wl('        "URL": "', repo_url, '"')
wl('      }')
wl('    ]')
wl('  },')
wl('  "Packages": {')
for (i in seq_along(records)) {
  r <- records[[i]]
  comma <- if (i < length(records)) "," else ""
  wl('    "', esc(r$Package), '": {')
  wl('      "Package": "', esc(r$Package), '",')
  wl('      "Version": "', esc(r$Version), '",')
  wl('      "Source": "', r$Source, '",')
  wl('      "Repository": "', r$Repository, '"')
  wl('    }', comma)
}
wl('  }')
wl("}")

message("Wrote    : ", outfile)
