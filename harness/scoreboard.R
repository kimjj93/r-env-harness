#!/usr/bin/env Rscript
# harness/scoreboard.R
#
# Ranks competing agent pull requests on evidence rather than on how confident
# their descriptions sound.
#
# This exists because the failure mode of a multi-agent race is rhetorical: each
# agent writes a persuasive PR description, and the human is left arbitrating
# prose. The scoreboard reads only artifacts the CI produced, so an agent cannot
# win by claiming a build time it never measured.
#
# The ranking is deliberately the SAME policy as the weekly research loop
# (result stability > tolerance headroom > churn > speed). A repository that
# ranked agents by one standard and research candidates by another would be
# telling its contributors two different things about what "better" means.
#
# Usage: Rscript scoreboard.R <racers-dir> <out.md>

args   <- commandArgs(trailingOnly = TRUE)
rdir   <- if (length(args) >= 1) args[1] else "racers"
outmd  <- if (length(args) >= 2) args[2] else "racers/scoreboard.md"

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a
fmt    <- function(x, d = 2) if (is.null(x) || length(x) == 0 || is.na(x)) "n/a" else format(round(as.numeric(x), d), scientific = FALSE)

prs_file <- file.path(rdir, "prs.json")
if (!file.exists(prs_file)) {
  writeLines(c("## Agent race scoreboard", "", "No racer pull requests found."), outmd)
  quit(status = 0)
}

prs <- jsonlite::fromJSON(prs_file, simplifyVector = FALSE)
if (length(prs) == 0) {
  writeLines(c("## Agent race scoreboard", "",
               "No open pull requests carry the `agent-racer` label yet.",
               "Racers may still be working."), outmd)
  quit(status = 0)
}

# ---- gather evidence per racer -------------------------------------------

collect <- function(pr) {
  num  <- pr$number
  dir  <- file.path(rdir, paste0("pr-", num))
  find1 <- function(pat) {
    hits <- list.files(dir, pattern = pat, recursive = TRUE, full.names = TRUE)
    if (length(hits)) hits[1] else NA_character_
  }
  rd <- function(p) if (!is.na(p) && file.exists(p))
    tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL

  delta   <- rd(find1("^delta\\.json$"))
  pq      <- rd(find1("^pq-summary\\.json$"))
  metrics <- rd(find1("^metrics-row\\.json$"))

  # An agent that produced no CI evidence is not scored as merely worse -- it is
  # marked NO_EVIDENCE. Ranking it against measured rivals would imply a
  # comparison that was never made.
  has_ev <- !is.null(delta) || !is.null(pq)

  list(
    number     = num,
    title      = pr$title %||% "",
    author     = (pr$author$login %||% "unknown"),
    branch     = pr$headRefName %||% "",
    strategy   = {
      key <- sub(".*\\[race:([^]]+)\\].*", "\\1", pr$title %||% "", perl = TRUE)
      # Show the brief, not the vendor key: the reviewer needs to know what the
      # agent was optimising for to interpret why it lost.
      switch(key,
        "copilot"   = "minimise churn",
        "anthropic" = "prefer newest",
        "openai"    = "optimise build",
        key)
    },
    evidence   = has_ev,
    verdict    = delta$verdict %||% (if (has_ev) "UNKNOWN" else "NO_EVIDENCE"),
    pq_passed  = as.numeric(pq$passed %||% metrics$pq_passed %||% NA),
    pq_failed  = as.numeric(pq$failed %||% metrics$pq_failed %||% NA),
    tol_util   = as.numeric(pq$tolerance_utilisation %||% metrics$tolerance_utilisation %||% NA),
    # Read the field where it actually lives. Both earlier spellings here were
    # wrong -- delta.json nests churn under layer3_packages, and the metrics row
    # calls it delta_churn -- so this criterion silently evaluated to NA on
    # every racer and the ranking quietly ran on three criteria instead of four.
    churn      = as.numeric(delta$layer3_packages$churn %||% metrics$delta_churn %||% NA),
    build_s    = as.numeric(metrics$build_seconds %||% NA),
    size_mb    = as.numeric(metrics$image_size_mb %||% NA)
  )
}

rows <- lapply(prs, collect)

stability <- function(v) switch(v,
  "IDENTICAL" = 0, "PASS_WITH_CHANGES" = 1, "TOLERANT_DRIFT" = 2,
  "BASELINE_ESTABLISHED" = 3, "FAIL_DEVIATION" = 8, "FAIL_NONDETERMINISM" = 8,
  "NO_EVIDENCE" = 9, 7)

# Disqualify before ranking: a PR that fails PQ is not a slightly worse option,
# it is not an option.
dq <- vapply(rows, function(r)
  !isTRUE(r$evidence) ||
  (!is.na(r$pq_failed) && r$pq_failed > 0) ||
  r$verdict %in% c("FAIL_DEVIATION", "FAIL_NONDETERMINISM"), logical(1))

ranked   <- rows[!dq]
excluded <- rows[dq]

if (length(ranked)) {
  ord <- order(
    vapply(ranked, function(r) stability(r$verdict), numeric(1)),
    vapply(ranked, function(r) if (is.na(r$tol_util)) 1 else r$tol_util, numeric(1)),
    vapply(ranked, function(r) if (is.na(r$churn)) 9999 else r$churn, numeric(1)),
    vapply(ranked, function(r) if (is.na(r$build_s)) 9e9 else r$build_s, numeric(1))
  )
  ranked <- ranked[ord]
}

# ---- render ---------------------------------------------------------------

L <- c(
  "## Agent race scoreboard",
  "",
  "Ranked on artifacts the CI produced, not on what the pull request descriptions",
  "claim. Policy, in order: **result stability -> tolerance headroom -> package",
  "churn -> build time**. Build time ranks last on purpose: a faster build never",
  "justifies a change in the numbers.",
  "",
  "| # | PR | Agent | Strategy | Verdict | PQ | Tol. util | Churn | Build | Size |",
  "|---|---|---|---|---|---|---|---|---|---|"
)

if (length(ranked) == 0) {
  L <- c(L, "| - | _no racer produced complete evidence yet_ | | | | | | | | |")
} else {
  for (i in seq_along(ranked)) {
    r <- ranked[[i]]
    mark <- if (i == 1) "**1**" else as.character(i)
    L <- c(L, sprintf("| %s | #%s | `%s` | %s | %s | %s/%s | %s | %s | %s s | %s MB |",
      mark, r$number, r$author, r$strategy, r$verdict,
      fmt(r$pq_passed, 0),
      fmt(sum(c(r$pq_passed, r$pq_failed), na.rm = TRUE), 0),
      fmt(r$tol_util), fmt(r$churn, 0), fmt(r$build_s, 0), fmt(r$size_mb, 0)))
  }
}

if (length(excluded)) {
  L <- c(L, "", "### Not ranked", "",
         "| PR | Agent | Reason |", "|---|---|---|")
  for (r in excluded) {
    why <- if (!isTRUE(r$evidence)) "no CI evidence available yet"
           else if (!is.na(r$pq_failed) && r$pq_failed > 0) sprintf("%s PQ assertion(s) failed", fmt(r$pq_failed, 0))
           else sprintf("delta verdict %s", r$verdict)
    L <- c(L, sprintf("| #%s | `%s` | %s |", r$number, r$author, why))
  }
  L <- c(L, "",
    "A racer excluded for failing PQ is not ranked lower -- it is out. Validation",
    "failure is disqualifying, not a scoring penalty.")
}

if (length(ranked) >= 2) {
  w <- ranked[[1]]; s <- ranked[[2]]
  L <- c(L, "", "### Reading the result", "",
    sprintf("The leader is **#%s** (`%s`, strategy: %s) on verdict `%s`.",
            w$number, w$author, w$strategy, w$verdict),
    "")
  if (!is.na(w$churn) && !is.na(s$churn) && !is.na(w$build_s) && !is.na(s$build_s) &&
      w$build_s > s$build_s) {
    L <- c(L, sprintf(
      "Note the trade-off the race exposed: #%s wins on stability and churn but is %s s slower to build than #%s. If build time matters more to you than review surface, the ranking policy -- not the evidence -- is what you disagree with, and that policy is editable in `harness/research/candidates.yml`.",
      w$number, fmt(w$build_s - s$build_s, 0), s$number), "")
  }
}

L <- c(L, "",
  "---",
  "",
  "**This scoreboard does not merge anything and does not approve anything.**",
  "It ranks. A human reads the trade-offs and decides which pull request, if any,",
  "is merged (`GOVERNANCE.md`). Close the rest with a rationale comment so the",
  "reasoning survives in the repository history.",
  "",
  sprintf("_Generated %s_", format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC", tz = "UTC")))

dir.create(dirname(outmd), recursive = TRUE, showWarnings = FALSE)
writeLines(L, outmd)
message("Wrote ", outmd, " (", length(ranked), " ranked, ", length(excluded), " excluded)")
