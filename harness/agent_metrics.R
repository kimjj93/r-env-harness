#!/usr/bin/env Rscript
# harness/agent_metrics.R
#
# Measures how well the *instructions* are working, as distinct from how well
# the environment is working.
#
# Why this exists
# ---------------
# The harness records 26 telemetry fields per research run -- build time, image
# size, package count, PQ pass/fail, tolerance utilisation, numeric deviation.
# Every one of them describes the environment. Not one of them describes whether
# an agent reading AGENTS.md was able to do the job.
#
# That gap had a visible cost. The first live agent race produced two competing
# pull requests; the scoreboard recorded their image sizes and threw away the
# fact that one racer reached a green gate in two attempts and the other took
# three. That difference is a measurement of the contract, and it was already
# sitting in the run history.
#
# What is deliberately NOT measured
# ---------------------------------
# Not lines produced, not commits, not time-to-first-push. Those reward an agent
# for generating more, and this repository's whole thesis is that volume is not
# the constraint -- review capacity is. The metrics here are about how much
# rework the human absorbs:
#
#   first_pass_acceptance  share of PRs whose FIRST gate run passed
#   iteration_cycles       gate runs needed before the first green
#   never_green            opened, iterated, still failing
#
# Human-authored PRs are measured alongside agent PRs as a control. If agents
# need three attempts where humans need one, the contract is underspecified. If
# both need three, the gate is flaky or the task is genuinely hard, and
# rewriting AGENTS.md would be treating the wrong cause.
#
# Usage: Rscript harness/agent_metrics.R <prs.json> <runs.json> <out-dir>

suppressWarnings(suppressMessages(library(jsonlite)))

args <- commandArgs(trailingOnly = TRUE)
prs_f  <- if (length(args) >= 1) args[1] else "artifacts/prs.json"
runs_f <- if (length(args) >= 2) args[2] else "artifacts/runs.json"
outdir <- if (length(args) >= 3) args[3] else "artifacts"

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a[1]))) b else a
pct <- function(x) if (is.na(x)) "n/a" else sprintf("%.0f%%", 100 * x)

if (!file.exists(prs_f) || !file.exists(runs_f)) {
  message("No PR or run data available; nothing to measure.")
  quit(status = 0)
}

prs  <- fromJSON(prs_f,  simplifyVector = FALSE)
runs <- fromJSON(runs_f, simplifyVector = FALSE)

if (length(prs) == 0) {
  message("No pull requests in window; nothing to measure.")
  quit(status = 0)
}

# An agent PR is identified by *authorship*, which cannot be borrowed. An earlier
# version of this also treated the `environment-proposal` label as an agent
# marker and promptly misclassified a human PR that had been given that label
# while testing the ai-review trigger. A label is a claim about a pull request;
# the author is a fact about it. GitHub reports agent authors as `app/...`.
is_agent <- function(pr) {
  login  <- tolower(pr$author$login %||% "")
  branch <- tolower(pr$headRefName %||% "")
  grepl("^app/|\\[bot\\]|copilot|swe-agent|code-agent", login) ||
    grepl("^(copilot|claude|codex)/", branch)
}

runs_for <- function(branch) {
  r <- Filter(function(x) identical(x$headBranch %||% "", branch), runs)
  # Oldest first: "first attempt" must mean the first one chronologically.
  r[order(vapply(r, function(x) x$createdAt %||% "", ""))]
}

rows <- lapply(prs, function(pr) {
  br <- pr$headRefName %||% ""
  r  <- runs_for(br)
  concl <- vapply(r, function(x) x$conclusion %||% "", "")
  # action_required means a human has not yet released the run. That is not the
  # agent failing; counting it as a failed attempt would blame the agent for a
  # platform control, so those runs are excluded from the attempt count.
  concl <- concl[!concl %in% c("action_required", "cancelled", "skipped", "")]
  first_green <- which(concl == "success")[1]

  list(
    number     = pr$number,
    author     = pr$author$login %||% "unknown",
    agent      = is_agent(pr),
    branch     = br,
    attempts   = length(concl),
    first_pass = if (length(concl) == 0) NA else identical(first_green, 1L),
    cycles     = if (is.na(first_green[1])) NA_integer_ else as.integer(first_green),
    never_green = length(concl) > 0 && is.na(first_green[1])
  )
})

measured <- Filter(function(x) x$attempts > 0, rows)

summarise <- function(rs, label) {
  if (length(rs) == 0)
    return(list(cohort = label, n = 0, first_pass_acceptance = NA,
                median_cycles = NA, never_green = 0))
  fp <- vapply(rs, function(x) isTRUE(x$first_pass), logical(1))
  cy <- vapply(rs, function(x) x$cycles %||% NA_integer_, integer(1))
  list(
    cohort                = label,
    n                     = length(rs),
    first_pass_acceptance = mean(fp),
    median_cycles         = if (all(is.na(cy))) NA else median(cy, na.rm = TRUE),
    never_green           = sum(vapply(rs, function(x) isTRUE(x$never_green), logical(1)))
  )
}

agents <- summarise(Filter(function(x) isTRUE(x$agent),  measured), "agent")
humans <- summarise(Filter(function(x) !isTRUE(x$agent), measured), "human")

dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
stamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

for (s in list(agents, humans)) {
  s$timestamp <- stamp
  cat(toJSON(s, auto_unbox = TRUE, na = "null"), "\n", sep = "",
      file = file.path(outdir, "agent-metrics.jsonl"), append = TRUE)
}

L <- c("### Agent effectiveness", "",
  "How much rework the human absorbed. These measure the *contract*, not the",
  "environment: if agents need repeated attempts where humans do not, the",
  "instructions are underspecified.", "",
  "| Cohort | PRs measured | First-pass acceptance | Median gate runs to green | Never green |",
  "|---|---|---|---|---|")
for (s in list(agents, humans))
  L <- c(L, sprintf("| %s | %d | %s | %s | %d |", s$cohort, s$n,
                    pct(s$first_pass_acceptance),
                    if (is.na(s$median_cycles)) "n/a" else format(s$median_cycles),
                    s$never_green))

if (agents$n > 0 && humans$n > 0 && !is.na(agents$median_cycles) && !is.na(humans$median_cycles) &&
    agents$median_cycles > humans$median_cycles) {
  L <- c(L, "",
    sprintf(paste0("Agents needed %s more gate run(s) than humans to reach green. Before ",
                   "rewriting any rule, check the failure reasons: a gate that is flaky ",
                   "produces the same signal as a contract that is unclear."),
            format(agents$median_cycles - humans$median_cycles)))
}
if (agents$never_green > 0) {
  L <- c(L, "",
    sprintf(paste0("%d agent PR(s) never reached green. Read the failures before drawing a ",
                   "conclusion about the agents: this harness has already produced a run of ",
                   "agent-PR failures whose cause was a defect in the validation harness ",
                   "itself, not in the submitted work."), agents$never_green))
}
L <- c(L, "",
  "_Not measured on purpose: lines changed, commits, time to first push. Volume",
  "is not the constraint here; review capacity is._")

writeLines(L, file.path(outdir, "agent-metrics.md"))
message(sprintf("Measured %d PR(s): %d agent, %d human.",
                length(measured), agents$n, humans$n))
cat(paste(L, collapse = "\n"), "\n")
