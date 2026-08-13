#!/usr/bin/env Rscript
# harness/learnings.R
#
# Reads, validates and appends to `evidence/learnings.jsonl` -- the record of
# what working on this repository actually taught us.
#
# Why this file exists
# --------------------
# The harness already learns about the *environment*: nightly telemetry measures
# package pins, image sizes and numeric deviation, and the weekly proposal turns
# those measurements into a reviewable change. Nothing learned about the
# *instructions*. When an agent misread AGENTS.md, or a gate silently degraded,
# or a platform constraint cost half a day, that knowledge landed in a commit
# message and stayed there. The next agent started from zero.
#
# `skills-drift.yml` does not close this gap. It detects mechanical drift --
# a SKILL.md referencing a path that no longer exists, a workflow nobody
# documented. It cannot detect that a rule is present, accurate, and still
# routinely misunderstood.
#
# So: one line per observation, in the four categories from Fowler's feedback
# flywheel (context, instruction, workflow, failure). JSONL because it is
# append-only by construction, diffs one line per lesson, and never produces a
# merge conflict between two agents recording different things.
#
# A learning is NOT a rule. Recording is cheap and deliberately unfiltered;
# promotion into AGENTS.md is gated on recurrence (see promote_learnings.R).
# That asymmetry is the point. A contract that absorbs every one-off stops
# being read, and an unread contract governs nothing.
#
# Usage:
#   Rscript harness/learnings.R validate [file]
#   Rscript harness/learnings.R summary  [file] [out.md]
#   Rscript harness/learnings.R add      [file] key=value ...

suppressWarnings(suppressMessages(library(jsonlite)))

args <- commandArgs(trailingOnly = TRUE)
cmd  <- if (length(args) >= 1) args[1] else "validate"
file <- if (length(args) >= 2 && !grepl("=", args[2], fixed = TRUE)) args[2] else "evidence/learnings.jsonl"

SIGNAL_TYPES <- c("context", "instruction", "workflow", "failure")
REQUIRED <- c("id", "timestamp", "signal_type", "summary", "detail",
              "root_cause", "target_artifact", "recurrence_key", "source")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

read_learnings <- function(path) {
  if (!file.exists(path)) return(list())
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  lapply(seq_along(lines), function(i) {
    parsed <- tryCatch(fromJSON(lines[i], simplifyVector = FALSE),
                       error = function(e) {
                         stop(sprintf("line %d is not valid JSON: %s", i, conditionMessage(e)),
                              call. = FALSE)
                       })
    parsed$`.line` <- i
    parsed
  })
}

# ---- validate --------------------------------------------------------------

do_validate <- function(path) {
  entries <- read_learnings(path)
  problems <- character(0)
  seen_ids <- character(0)

  for (e in entries) {
    ln <- e$`.line`
    missing <- REQUIRED[!REQUIRED %in% names(e)]
    if (length(missing))
      problems <- c(problems, sprintf("line %d: missing field(s): %s", ln, paste(missing, collapse = ", ")))

    for (f in intersect(REQUIRED, names(e)))
      if (!nzchar(trimws(as.character(e[[f]] %||% ""))))
        problems <- c(problems, sprintf("line %d: field `%s` is empty", ln, f))

    st <- e$signal_type %||% ""
    if (nzchar(st) && !st %in% SIGNAL_TYPES)
      problems <- c(problems, sprintf("line %d: signal_type `%s` is not one of: %s",
                                      ln, st, paste(SIGNAL_TYPES, collapse = ", ")))

    id <- e$id %||% ""
    if (id %in% seen_ids)
      problems <- c(problems, sprintf("line %d: duplicate id `%s`", ln, id))
    seen_ids <- c(seen_ids, id)

    key <- e$recurrence_key %||% ""
    if (nzchar(key) && !grepl("^[a-z0-9]+(-[a-z0-9]+)*$", key))
      problems <- c(problems, sprintf("line %d: recurrence_key `%s` must be lowercase-hyphenated", ln, key))

    # A learning that points at a file which does not exist cannot ever be
    # acted on. This is the same referential check skills-drift applies to
    # SKILL.md, for the same reason: a dangling pointer is worse than silence.
    tgt <- e$target_artifact %||% ""
    if (nzchar(tgt) && !file.exists(tgt))
      problems <- c(problems, sprintf("line %d: target_artifact `%s` does not exist", ln, tgt))
  }

  if (length(problems)) {
    message("Learning log validation FAILED:\n")
    for (p in problems) message("  - ", p)
    quit(status = 1)
  }
  message(sprintf("Learning log OK: %d entr%s, %d distinct recurrence key(s).",
                  length(entries), if (length(entries) == 1) "y" else "ies",
                  length(unique(vapply(entries, function(e) e$recurrence_key %||% "", "")))))
}

# ---- summary ---------------------------------------------------------------

do_summary <- function(path, out) {
  entries <- read_learnings(path)
  keys <- vapply(entries, function(e) e$recurrence_key %||% "", "")
  tab  <- sort(table(keys), decreasing = TRUE)

  L <- c("## Learning log", "",
         sprintf("%d recorded observation(s) across %d distinct lesson(s).",
                 length(entries), length(tab)), "",
         "| Lesson (recurrence key) | Seen | Type | Target artifact |",
         "|---|---|---|---|")
  for (k in names(tab)) {
    grp <- Filter(function(e) identical(e$recurrence_key %||% "", k), entries)
    L <- c(L, sprintf("| `%s` | %d | %s | `%s` |", k, length(grp),
                      grp[[1]]$signal_type %||% "?",
                      grp[[1]]$target_artifact %||% "?"))
  }
  L <- c(L, "",
         "A lesson seen once is an anecdote and stays here. A lesson seen twice",
         "is a pattern and is proposed for the contract by `learning-promote.yml`.")

  if (nzchar(out)) {
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
    writeLines(L, out)
    message("Wrote ", out)
  } else {
    cat(paste(L, collapse = "\n"), "\n")
  }
}

# ---- add -------------------------------------------------------------------

do_add <- function(path, kv) {
  pairs <- kv[grepl("=", kv, fixed = TRUE)]
  rec <- list()
  for (p in pairs) {
    k <- sub("=.*$", "", p)
    v <- sub("^[^=]*=", "", p)
    rec[[k]] <- v
  }
  rec$timestamp <- rec$timestamp %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.null(rec$id)) {
    # Allocate from the highest id present, not from the row count. Counting
    # rows produces a colliding id the moment the log has any gap in it, which
    # is exactly what a renumber after a merge conflict leaves behind.
    #
    # This does not make ids unique across concurrent branches -- nothing that
    # reads only the current branch can. The validator rejects duplicates, so a
    # collision is a rebase to resolve rather than a corrupted log, and
    # `recurrence_key` is what the harness actually groups on.
    existing <- vapply(read_learnings(path), function(e) e$id %||% "", "")
    nums <- suppressWarnings(as.integer(sub("^L-", "", existing)))
    nums <- nums[!is.na(nums)]
    rec$id <- sprintf("L-%04d", if (length(nums)) max(nums) + 1L else 1L)
  }
  if (!"promoted" %in% names(rec)) rec$promoted <- NULL

  missing <- REQUIRED[!REQUIRED %in% names(rec)]
  if (length(missing))
    stop("refusing to append an incomplete learning; missing: ",
         paste(missing, collapse = ", "), call. = FALSE)

  # Ordered so the file stays readable as plain text, not just as JSON.
  ordered <- rec[c(REQUIRED, setdiff(names(rec), REQUIRED))]
  ordered <- ordered[!vapply(ordered, is.null, logical(1))]
  line <- toJSON(ordered, auto_unbox = TRUE, null = "null")

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  cat(line, "\n", sep = "", file = path, append = TRUE)
  message("Appended ", rec$id, " (", rec$recurrence_key, ") to ", path)
}

switch(cmd,
  "validate" = do_validate(file),
  "summary"  = do_summary(file, if (length(args) >= 3) args[3] else ""),
  "add"      = do_add(file, args[-1]),
  stop("unknown command: ", cmd, " (expected validate | summary | add)", call. = FALSE)
)
