#!/usr/bin/env Rscript
# Four-layer environment delta.
#
#   Rscript harness/image_delta.R <baseline_manifest.json> <candidate_manifest.json> \
#                                 [output_dir] [baseline_pq.json] [candidate_pq.json]
#
# Layer 1  image digest   -> did anything change at all?
# Layer 2  base / OS      -> did the ground shift under the packages?
# Layer 3  R packages     -> what moved in the library?
# Layer 4  results        -> did any of it actually matter?
#
# See skills/env-delta/SKILL.md. Always emit all four layers, including when
# empty: a reviewer must see that the check ran, not infer it.

suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("usage: image_delta.R <baseline.json> <candidate.json> [outdir] [base_pq.json] [cand_pq.json]")
}
baseline_f <- args[[1]]
candidate_f <- args[[2]]
outdir      <- if (length(args) >= 3) args[[3]] else "artifacts"
base_pq_f   <- if (length(args) >= 4) args[[4]] else NA_character_
cand_pq_f   <- if (length(args) >= 5) args[[5]] else NA_character_

dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

read_json_safe <- function(f) {
  if (is.na(f) || !nzchar(f) || !file.exists(f)) return(NULL)
  tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

base <- read_json_safe(baseline_f)
cand <- read_json_safe(candidate_f)
if (is.null(cand)) stop("Cannot read candidate manifest: ", candidate_f)

# A missing baseline is normal on a first run. Report it explicitly rather than
# pretending the delta is empty.
first_run <- is.null(base)

# --- Layer 1: image digest ---------------------------------------------------
base_digest <- Sys.getenv("BASELINE_IMAGE_DIGEST", unset = "")
cand_digest <- Sys.getenv("CANDIDATE_IMAGE_DIGEST", unset = "")
l1_changed <- !nzchar(base_digest) || !identical(base_digest, cand_digest)

# --- Layer 2: base / OS ------------------------------------------------------
l2_fields <- list()
if (!first_run) {
  cmp <- function(label, a, b) {
    a <- if (is.null(a)) NA_character_ else as.character(a)
    b <- if (is.null(b)) NA_character_ else as.character(b)
    if (!identical(a, b)) {
      l2_fields[[length(l2_fields) + 1L]] <<- list(field = label, baseline = a, candidate = b)
    }
  }
  cmp("os.pretty_name", base$os$pretty_name, cand$os$pretty_name)
  cmp("os.version_id",  base$os$version_id,  cand$os$version_id)
  cmp("os.glibc",       base$os$glibc,       cand$os$glibc)
  cmp("r_version",      base$r_version,      cand$r_version)
  cmp("locale",         base$locale,         cand$locale)
  cmp("blas",           base$numeric$blas,   cand$numeric$blas)
  cmp("lapack",         base$numeric$lapack, cand$numeric$lapack)
  cmp("ppm_snapshot",   base$ppm_snapshot,   cand$ppm_snapshot)
  cmp("nixpkgs_date",   base$nixpkgs_date,   cand$nixpkgs_date)
}
l2_changed <- length(l2_fields) > 0

# --- Layer 3: R packages -----------------------------------------------------
as_named <- function(x) {
  if (is.null(x)) return(character(0))
  v <- unlist(x)
  stats::setNames(as.character(v), names(v))
}
bp <- as_named(base$packages)
cp <- as_named(cand$packages)

added   <- sort(setdiff(names(cp), names(bp)))
removed <- sort(setdiff(names(bp), names(cp)))
common  <- intersect(names(bp), names(cp))
changed <- sort(common[bp[common] != cp[common]])

l3_changed <- length(added) + length(removed) + length(changed) > 0
churn <- length(added) + length(removed) + length(changed)

# --- Layer 4: results --------------------------------------------------------
base_pq <- read_json_safe(base_pq_f)
cand_pq <- read_json_safe(cand_pq_f)

l4_changed <- FALSE
checksum_rows <- list()
max_dev <- if (!is.null(cand_pq) && !is.null(cand_pq$max_abs_deviation)) {
  as.numeric(cand_pq$max_abs_deviation)
} else NA_real_

if (!is.null(base_pq) && !is.null(cand_pq)) {
  for (nm in names(cand_pq$result_checksums)) {
    b <- base_pq$result_checksums[[nm]]
    c_ <- cand_pq$result_checksums[[nm]]
    ch <- !identical(b, c_)
    if (ch) l4_changed <- TRUE
    checksum_rows[[length(checksum_rows) + 1L]] <-
      list(dataset = nm, baseline = b %||% NA, candidate = c_ %||% NA, changed = ch)
  }
}

pq_failed <- !is.null(cand_pq) && !is.null(cand_pq$failed) && cand_pq$failed > 0

# --- Verdict -----------------------------------------------------------------
# The interesting case is the last one: an unchanged environment producing
# changed results means something is unpinned, which is a defect in the
# pipeline rather than an environment change.
verdict <- if (first_run) {
  "BASELINE_ESTABLISHED"
} else if (pq_failed) {
  "FAIL_DEVIATION"
} else if (!l1_changed && !l2_changed && !l3_changed && !l4_changed) {
  "IDENTICAL"
} else if (!l2_changed && !l3_changed && l4_changed) {
  "FAIL_NONDETERMINISM"
} else if (l4_changed) {
  "TOLERANT_DRIFT"
} else {
  "PASS_WITH_CHANGES"
}

# --- Emit delta.json ---------------------------------------------------------
delta <- list(
  first_run = first_run,
  layer1_digest = list(changed = l1_changed,
                       baseline = base_digest, candidate = cand_digest),
  layer2_base = list(changed = l2_changed, fields = l2_fields),
  layer3_packages = list(
    changed = l3_changed,
    churn = churn,
    added = lapply(added, function(p) list(package = p, version = unname(cp[p]))),
    removed = lapply(removed, function(p) list(package = p, version = unname(bp[p]))),
    changed_versions = lapply(changed, function(p) {
      list(package = p, old = unname(bp[p]), new = unname(cp[p]))
    })
  ),
  layer4_results = list(changed = l4_changed,
                        checksums = checksum_rows,
                        max_abs_deviation = max_dev),
  verdict = verdict
)

write(toJSON(delta, auto_unbox = TRUE, pretty = TRUE, null = "null"),
      file.path(outdir, "delta.json"))

# --- Emit the markdown a human actually reads --------------------------------
md <- c(
  "## Environment Delta Report",
  "",
  sprintf("**Verdict: `%s`**", verdict),
  ""
)

verdict_note <- switch(verdict,
  IDENTICAL = "Environments are bit-identical. Layers 2-4 are provably empty.",
  PASS_WITH_CHANGES = "The environment changed but every analysis result is unchanged. This is the ideal upgrade outcome.",
  TOLERANT_DRIFT = "The environment changed and results moved within declared tolerance. Document this drift before accepting.",
  FAIL_DEVIATION = "Performance Qualification failed. Do not resolve by widening a tolerance (AGENTS.md 1.6).",
  FAIL_NONDETERMINISM = "Results changed while the environment did not. Something in the pipeline is unpinned - investigate before merging.",
  BASELINE_ESTABLISHED = "No baseline manifest was available; this run establishes one.",
  ""
)
md <- c(md, verdict_note, "")

md <- c(md, "### Layer 1 - Image digest", "",
        if (first_run) "_No baseline to compare._" else
        sprintf("| | digest |\n|---|---|\n| baseline | `%s` |\n| candidate | `%s` |\n| **changed** | **%s** |",
                ifelse(nzchar(base_digest), base_digest, "n/a"),
                ifelse(nzchar(cand_digest), cand_digest, "n/a"),
                l1_changed),
        "")

md <- c(md, "### Layer 2 - Base / OS", "")
if (!l2_changed) {
  md <- c(md, "No change to OS, glibc, R version, locale, BLAS/LAPACK, or snapshot pins.", "")
} else {
  md <- c(md, "| field | baseline | candidate |", "|---|---|---|",
          vapply(l2_fields, function(f)
            sprintf("| `%s` | %s | %s |", f$field, f$baseline, f$candidate),
            character(1)), "")
}

md <- c(md, "### Layer 3 - R packages", "")
if (!l3_changed) {
  md <- c(md, "No packages added, removed, or changed.", "")
} else {
  md <- c(md, sprintf("Churn: **%d** (%d added, %d removed, %d changed)",
                      churn, length(added), length(removed), length(changed)), "")
  if (length(changed)) {
    md <- c(md, "| package | old | new |", "|---|---|---|",
            vapply(changed, function(p)
              sprintf("| `%s` | %s | %s |", p, bp[[p]], cp[[p]]), character(1)), "")
  }
  if (length(added)) {
    md <- c(md, "**Added:** " ,
            paste(sprintf("`%s` %s", added, cp[added]), collapse = ", "), "")
  }
  if (length(removed)) {
    md <- c(md, "**Removed:** ",
            paste(sprintf("`%s` %s", removed, bp[removed]), collapse = ", "), "")
  }
}

md <- c(md, "### Layer 4 - Analysis results", "")
if (!length(checksum_rows)) {
  md <- c(md, "_No comparable PQ results available._", "")
} else {
  md <- c(md, "| dataset | changed | baseline | candidate |", "|---|---|---|---|",
          vapply(checksum_rows, function(r)
            sprintf("| %s | %s | `%s` | `%s` |", r$dataset,
                    ifelse(isTRUE(r$changed), "**YES**", "no"),
                    substr(as.character(r$baseline), 1, 16),
                    substr(as.character(r$candidate), 1, 16)),
            character(1)), "")
  if (!is.na(max_dev)) {
    md <- c(md, sprintf("Maximum absolute numeric deviation observed: `%s`",
                        format(max_dev, scientific = TRUE)), "")
  }
}

writeLines(md, file.path(outdir, "delta.md"))

message("Verdict: ", verdict)
message("Wrote ", file.path(outdir, "delta.json"))
message("Wrote ", file.path(outdir, "delta.md"))

# Only genuine problems fail the gate. A changed-but-qualified environment must
# not block the PR, or every legitimate upgrade would require overriding CI.
if (verdict %in% c("FAIL_DEVIATION", "FAIL_NONDETERMINISM")) quit(status = 1L, save = "no")
quit(status = 0L, save = "no")
