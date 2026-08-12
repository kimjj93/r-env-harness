#!/usr/bin/env Rscript
# Track B generator — Nix environment via {rix}.
#
# THIS is the source of truth. `default.nix` and `.Rprofile` are GENERATED.
# Never hand-edit them (AGENTS.md §1.4); change this file and regenerate:
#
#   Rscript env/nix/generate_env.R [date]
#
# `date =` pins nixpkgs (and therefore CRAN state, R itself, the OS, and all
# system libraries) to a specific day. It is preferred over `r_ver =`, which
# trails CRAN by up to two months. `r_ver = "bleeding-edge"` is forbidden here
# because it is not reproducible by construction.

args <- commandArgs(trailingOnly = TRUE)
nixpkgs_date <- if (length(args) >= 1) args[[1]] else "2025-01-15"

if (!requireNamespace("rix", quietly = TRUE)) {
  install.packages("rix", repos = "https://cloud.r-project.org")
}

# Mirrors the Track A direct set so the two tracks are genuinely comparable.
# If these drift apart, the cross-track comparison becomes meaningless.
r_pkgs <- c(
  "admiral",
  "pharmaversesdtm",
  "dplyr",
  "tidyr",
  "lubridate",
  "stringr",
  "jsonlite",
  "sessioninfo",
  "testthat",
  "xml2",
  "digest"
)

system_pkgs <- c(
  "git",
  "jq",
  "pandoc",
  "glibcLocalesUtf8"
)

message("Generating Nix environment pinned to nixpkgs date: ", nixpkgs_date)

rix::rix(
  date         = nixpkgs_date,
  r_pkgs       = r_pkgs,
  system_pkgs  = system_pkgs,
  git_pkgs     = NULL,
  ide          = "none",
  project_path = "env/nix",
  overwrite    = TRUE,
  print        = FALSE
)

message("Wrote env/nix/default.nix and env/nix/.Rprofile")
message("")
message("Reminder: configure the rstats-on-nix Cachix cache before building.")
message("Without it, packages compile from source and builds take hours.")
message("  cachix use rstats-on-nix")
