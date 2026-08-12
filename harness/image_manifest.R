#!/usr/bin/env Rscript
# Emit a normalised environment manifest from INSIDE a container image.
#
#   Rscript harness/image_manifest.R [output.json]
#
# This is what the environment actually IS, as opposed to what the lockfile
# requested. The distinction matters: a lockfile is an intention, a manifest is
# an observation, and only the manifest can prove Layer 2 (OS/system libraries)
# did not move.

args <- commandArgs(trailingOnly = TRUE)
outfile <- if (length(args) >= 1) args[[1]] else "manifest.json"

esc <- function(x) {
  x <- as.character(x)
  x <- gsub('\\\\', '\\\\\\\\', x)
  x <- gsub('"', '\\\\"', x)
  gsub('[\r\n]+', ' ', x)
}

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

# --- R-level -----------------------------------------------------------------
r_version <- as.character(getRversion())

ip <- utils::installed.packages()
pkgs <- data.frame(
  Package = rownames(ip),
  Version = unname(ip[, "Version"]),
  stringsAsFactors = FALSE
)
pkgs <- pkgs[order(pkgs$Package), ]   # deterministic ordering

# --- OS level ----------------------------------------------------------------
read_os_release <- function() {
  f <- "/etc/os-release"
  if (!file.exists(f)) return(list(id = NA, version = NA, pretty = NA))
  lines <- readLines(f, warn = FALSE)
  get <- function(key) {
    m <- grep(paste0("^", key, "="), lines, value = TRUE)
    if (!length(m)) return(NA_character_)
    gsub('^[^=]+=|"', "", m[[1]])
  }
  list(id = get("ID"), version = get("VERSION_ID"), pretty = get("PRETTY_NAME"))
}
os <- read_os_release()

glibc <- tryCatch({
  out <- suppressWarnings(system("ldd --version 2>/dev/null | head -1", intern = TRUE))
  if (length(out)) sub(".*\\s([0-9]+\\.[0-9]+).*", "\\1", out[[1]]) else NA_character_
}, error = function(e) NA_character_)

si <- Sys.info()

# BLAS/LAPACK identity: two libraries with identical package versions can still
# produce different numbers if these differ, so they belong in the manifest.
blas <- tryCatch(sessionInfo()$BLAS %||% NA_character_, error = function(e) NA_character_)
lapack <- tryCatch(sessionInfo()$LAPACK %||% NA_character_, error = function(e) NA_character_)

session_txt <- tryCatch({
  if (requireNamespace("sessioninfo", quietly = TRUE)) {
    paste(utils::capture.output(sessioninfo::session_info()), collapse = "\\n")
  } else {
    paste(utils::capture.output(utils::sessionInfo()), collapse = "\\n")
  }
}, error = function(e) "")

track <- Sys.getenv("HARNESS_TRACK", unset = if (nzchar(Sys.getenv("NIX_STORE"))) "nix" else "renv")

con <- file(outfile, open = "wt"); on.exit(close(con))
wl <- function(...) writeLines(paste0(...), con)

wl("{")
wl('  "track": "', esc(track), '",')
wl('  "r_version": "', esc(r_version), '",')
wl('  "os": {')
wl('    "id": "', esc(os$id), '",')
wl('    "version_id": "', esc(os$version), '",')
wl('    "pretty_name": "', esc(os$pretty), '",')
wl('    "glibc": "', esc(glibc), '",')
wl('    "sysname": "', esc(si[["sysname"]]), '",')
wl('    "machine": "', esc(si[["machine"]]), '"')
wl('  },')
wl('  "numeric": {')
wl('    "blas": "', esc(blas), '",')
wl('    "lapack": "', esc(lapack), '"')
wl('  },')
wl('  "locale": "', esc(Sys.getlocale("LC_COLLATE")), '",')
wl('  "ppm_snapshot": "', esc(Sys.getenv("PPM_SNAPSHOT", unset = "")), '",')
wl('  "nixpkgs_date": "', esc(Sys.getenv("NIXPKGS_DATE", unset = "")), '",')
wl('  "package_count": ', nrow(pkgs), ',')
wl('  "packages": {')
for (i in seq_len(nrow(pkgs))) {
  comma <- if (i < nrow(pkgs)) "," else ""
  wl('    "', esc(pkgs$Package[i]), '": "', esc(pkgs$Version[i]), '"', comma)
}
wl('  },')
wl('  "session_info": "', esc(session_txt), '"')
wl("}")

message("Wrote manifest: ", outfile, " (", nrow(pkgs), " packages, track=", track, ")")
