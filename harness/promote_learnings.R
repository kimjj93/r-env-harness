#!/usr/bin/env Rscript
# harness/promote_learnings.R
#
# Promotes a lesson from the learning log into `AGENTS.md` -- but only once the
# same lesson has been recorded more than once.
#
# Why a threshold
# ---------------
# The obvious design is to append every observation to the agent contract. That
# design fails for a reason that has nothing to do with correctness: a contract
# which absorbs every one-off grows until agents stop reading it carefully, and
# a contract that is skimmed governs nothing. Recording must be cheap; promotion
# must not be.
#
# So the log takes everything and the contract takes only what recurred. One
# occurrence is an anecdote about a particular afternoon. Two occurrences in
# separate places -- the same field-name mismatch in the aggregator and again in
# the scoreboard -- is a property of how this repository is built, and belongs
# where every agent will see it.
#
# What this script will and will not write
# ----------------------------------------
# It writes evidence: which lesson, how many times, where, and a link back to
# the log. It does NOT write policy. Generating rule text from a template would
# produce confident prose that nobody had thought about, which is precisely the
# failure mode the harness exists to prevent. Turning a recurring lesson into a
# hard rule in AGENTS.md section 1 is a human edit; marking the log entries
# `promoted` then retires them from the generated block.
#
# The block is regenerated from the log every run, so this is idempotent: once
# the promotion PR is merged, re-running produces byte-identical output and no
# further PR is opened.
#
# Usage: Rscript harness/promote_learnings.R <learnings.jsonl> <AGENTS.md> [threshold] [proposal.md]

suppressWarnings(suppressMessages(library(jsonlite)))

args      <- commandArgs(trailingOnly = TRUE)
lfile     <- if (length(args) >= 1) args[1] else "evidence/learnings.jsonl"
agentsmd  <- if (length(args) >= 2) args[2] else "AGENTS.md"
threshold <- if (length(args) >= 3) as.integer(args[3]) else 2L
propfile  <- if (length(args) >= 4) args[4] else ""

BEGIN <- "<!-- BEGIN GENERATED: recurring-lessons -->"
END   <- "<!-- END GENERATED: recurring-lessons -->"

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# AGENTS.md is Layer 1: portable, and lifted wholesale by
# tools/extract-template.sh into a repository with a different domain. A
# learning's `target_artifact` points at a real file, which for a use-case
# lesson is a path inside the use case. Writing that path verbatim meant every
# lesson that recurred twice injected a domain path into the portable layer --
# the learning loop slowly dissolving the boundary it is supposed to respect.
# Two lessons had already leaked a concrete use case path into AGENTS.md and
# broken template extraction.
#
# The path still carries useful information, so it is generalised rather than
# dropped: the concrete use case directory becomes `<usecase>/`. The pattern is
# structural (`usecases/<anything>/`), so this stays correct when the use case
# is swapped -- which is the whole point.
neutralise_path <- function(p) sub("^usecases/[^/]+/", "<usecase>/", p)

stopifnot(file.exists(lfile), file.exists(agentsmd))

lines   <- readLines(lfile, warn = FALSE)
lines   <- lines[nzchar(trimws(lines))]
entries <- lapply(lines, fromJSON, simplifyVector = FALSE)

# An entry with a non-null `promoted` has been dealt with -- either written into
# the contract by hand, or deliberately declined. Either way it is no longer a
# candidate, and the reason survives in the log rather than in someone's memory.
open_entries <- Filter(function(e) is.null(e$promoted), entries)

keys   <- vapply(open_entries, function(e) e$recurrence_key %||% "", "")
counts <- table(keys)
qual   <- names(counts)[counts >= threshold]
# Most-repeated first: the ordering is itself information about which mistake
# this repository makes most often.
qual   <- qual[order(-as.integer(counts[qual]), qual)]

body <- c(BEGIN,
  "",
  sprintf("Mistakes this repository has made more than once. Recorded automatically from"),
  sprintf("`%s`; a lesson appears here after it has been observed %d times or more.", lfile, threshold),
  "Read this before you start. These are not hypothetical.",
  "")

if (length(qual) == 0) {
  body <- c(body, "_No lesson has yet recurred. The log is still accumulating._", "")
} else {
  for (k in qual) {
    grp <- Filter(function(e) identical(e$recurrence_key %||% "", k), open_entries)
    body <- c(body,
      sprintf("**%s** — seen %d times, affects `%s`", k, length(grp),
              neutralise_path(grp[[1]]$target_artifact %||% "?")),
      "")
    for (e in grp)
      body <- c(body, sprintf("- %s _(%s, %s)_", e$summary %||% "",
                              e$signal_type %||% "?", e$source %||% "?"))
    body <- c(body, "",
      sprintf("  Common cause: %s", grp[[1]]$root_cause %||% ""), "")
  }
}

body <- c(body,
  "Do not edit this block by hand; it is regenerated from the learning log.",
  "To retire a lesson, write the rule you want into section 1 and set",
  "`promoted` on its log entries.",
  END)

cur <- readLines(agentsmd, warn = FALSE)
b <- which(cur == BEGIN); e <- which(cur == END)

if (length(b) != 1 || length(e) != 1 || e < b)
  stop("AGENTS.md must contain exactly one generated recurring-lessons block", call. = FALSE)

new <- c(cur[seq_len(b - 1)], body,
         if (e < length(cur)) cur[(e + 1):length(cur)] else character(0))
changed <- !identical(new, cur)

if (changed) {
  writeLines(new, agentsmd)
  message(sprintf("Updated %s: %d recurring lesson(s) at threshold %d.",
                  agentsmd, length(qual), threshold))
} else {
  message("No change: the contract already reflects the log.")
}

if (nzchar(propfile)) {
  p <- c("## Recurring lessons promoted to the agent contract", "",
         sprintf("The learning log now holds %d observation(s). %d lesson(s) have been seen",
                 length(entries), length(qual)),
         sprintf("at least %d times and are therefore surfaced in `AGENTS.md`.", threshold), "")
  if (length(qual)) {
    p <- c(p, "| Lesson | Times seen | Target artifact |", "|---|---|---|")
    for (k in qual) {
      grp <- Filter(function(x) identical(x$recurrence_key %||% "", k), open_entries)
      p <- c(p, sprintf("| `%s` | %d | `%s` |", k, length(grp),
                        neutralise_path(grp[[1]]$target_artifact %||% "?")))
    }
  }
  p <- c(p, "",
    "This pull request adds **evidence, not policy**. It states that these mistakes",
    "recurred; it does not attempt to write the rule that would prevent them. If a",
    "lesson here warrants a hard rule, write it into `AGENTS.md` section 1 as part of",
    "reviewing this PR and set `promoted` on the corresponding log entries so the",
    "lesson retires from the generated block.",
    "",
    "Nothing here changes the environment, the validation criteria, or any gate.")
  dir.create(dirname(propfile), recursive = TRUE, showWarnings = FALSE)
  writeLines(p, propfile)
}

cat(if (changed) "changed=true\n" else "changed=false\n")
