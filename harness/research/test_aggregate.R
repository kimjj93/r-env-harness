#!/usr/bin/env Rscript
# harness/research/test_aggregate.R
#
# Regression tests for the weekly aggregator.
#
# These exist because of a specific failure: for the entire life of the research
# loop the aggregator produced `recommendation: NONE` every single week, and
# every layer above it reported success. Nightly runs were green, telemetry grew,
# the weekly workflow succeeded, and the system was structurally incapable of
# ever proposing anything. Nothing failed, so nothing was investigated.
#
# The load-bearing test here is `proposal is reachable`. A green aggregator that
# can never propose is indistinguishable from a healthy one that has nothing to
# propose -- unless something asserts that a well-formed week DOES produce a
# proposal. That assertion is the difference between a flywheel and an ornament.
#
# Run: Rscript harness/research/test_aggregate.R

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite is required")

AGG  <- "harness/research/aggregate.R"
fails <- 0L
ok <- function(what) cat(sprintf("  ok    %s\n", what))
bad <- function(what, why) {
  fails <<- fails + 1L
  cat(sprintf("  FAIL  %s\n        %s\n", what, why))
}

tmp <- file.path(tempdir(), paste0("aggtest-", Sys.getpid()))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)

# A policy identical in shape to a real use case's candidates.yml.
policy <- file.path(tmp, "policy.yml")
writeLines(c(
  "candidates:",
  "  - id: cand-good",
  "    dimension: pinned_snapshot",
  "    value: \"2025-04-01\"",
  "gates:",
  "  checks_failed_max: 0",
  "  observed_risk_max: 0.7"
), policy)

iso_z     <- function(offset_days) format(Sys.time() - offset_days * 86400,
                                          "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
iso_micro <- function(offset_days) paste0(format(Sys.time() - offset_days * 86400,
                                          "%Y-%m-%dT%H:%M:%S", tz = "UTC"),
                                          ".123456+00:00")

row <- function(id, ts, value = "2025-04-01", status = "success",
                verdict = "PASS_WITH_CHANGES", failed = 0, risk = NULL, ...) {
  r <- list(timestamp = ts, candidate_id = id, dimension = "pinned_snapshot",
            candidate_value = value, status = status, verdict = verdict,
            checks_passed = 36, checks_failed = failed,
            change_magnitude = 12, cost_seconds = 100, ...)
  if (!is.null(risk)) r$observed_risk <- risk
  r
}

write_rows <- function(rows, path) {
  writeLines(vapply(rows, function(r) jsonlite::toJSON(r, auto_unbox = TRUE), character(1)), path)
}

# Returns list(exit=, out=, rec=) for one aggregator invocation.
run_agg <- function(rows, pol = policy, label = "case") {
  d <- file.path(tmp, label); dir.create(d, showWarnings = FALSE)
  m <- file.path(d, "metrics.jsonl")
  write_rows(rows, m)
  out <- suppressWarnings(system2("Rscript", c(AGG, m, pol, d),
                                  stdout = TRUE, stderr = TRUE))
  code <- attr(out, "status"); if (is.null(code)) code <- 0L
  recf <- file.path(d, "recommendation.json")
  rec  <- if (file.exists(recf)) jsonlite::fromJSON(recf) else NULL
  list(exit = code, out = paste(out, collapse = "\n"), rec = rec)
}

# Same, but for a metrics file built byte-for-byte by the caller -- used by the
# corruption and round-trip tests, where HOW the file was written is the thing
# under test and must not be normalised by write_rows().
run_agg_file <- function(path, pol = policy, label = NULL) {
  d <- dirname(path)
  out <- suppressWarnings(system2("Rscript", c(AGG, path, pol, d),
                                  stdout = TRUE, stderr = TRUE))
  code <- attr(out, "status"); if (is.null(code)) code <- 0L
  recf <- file.path(d, "recommendation.json")
  rec  <- if (file.exists(recf)) jsonlite::fromJSON(recf) else NULL
  list(exit = code, out = paste(out, collapse = "\n"), rec = rec)
}

cat("aggregate.R regression tests\n")

# ---------------------------------------------------------------------------
# 1. THE LOAD-BEARING TEST. A clean week must yield a proposal.
#    If this ever fails, the research loop cannot deliver its only product.
# ---------------------------------------------------------------------------
r1 <- run_agg(list(row("cand-good", iso_z(1))), label = "reachable")
if (is.null(r1$rec)) {
  bad("proposal is reachable", "no recommendation.json written")
} else if (identical(as.character(r1$rec$recommendation), "PROPOSE")) {
  ok("proposal is reachable (a clean week yields PROPOSE)")
} else {
  bad("proposal is reachable",
      sprintf("recommendation=%s reason=%s", r1$rec$recommendation,
              r1$rec$reason %||% "<none>"))
}

# ---------------------------------------------------------------------------
# 2. Both timestamp formats in use must be understood. The Z form comes from
#    the workflow, the microsecond+offset form from Python isoformat(). Reading
#    only one silently discarded two thirds of the telemetry.
# ---------------------------------------------------------------------------
r2 <- run_agg(list(row("cand-good", iso_micro(1))), label = "isoformat")
if (!is.null(r2$rec) && identical(as.character(r2$rec$recommendation), "PROPOSE")) {
  ok("isoformat timestamps (+00:00 with microseconds) are in the window")
} else {
  bad("isoformat timestamps are in the window",
      "a row with a Python isoformat timestamp was not evaluated")
}

# ---------------------------------------------------------------------------
# 3. An unreadable timestamp must be REPORTED. Under a window filter it is
#    indistinguishable from an old row, so silence loses evidence invisibly.
# ---------------------------------------------------------------------------
r3 <- run_agg(list(row("cand-good", iso_z(1)), row("cand-good", "not-a-timestamp")),
              label = "unreadable")
if (grepl("UNREADABLE TIMESTAMPS", r3$out, fixed = TRUE)) {
  ok("unreadable timestamps are reported, not silently dropped")
} else {
  bad("unreadable timestamps are reported", "no warning was emitted")
}

# ---------------------------------------------------------------------------
# 4. A row with no realised value cannot become an edit to a pin file. This is
#    the defect that made every real candidate ineligible.
# ---------------------------------------------------------------------------
r4 <- run_agg(list(row("cand-good", iso_z(1), value = NULL)), label = "novalue")
if (!is.null(r4$rec) && identical(as.character(r4$rec$recommendation), "NONE")) {
  ok("a row with no candidate_value is refused as unactionable")
} else {
  bad("a row with no candidate_value is refused", "it was proposed anyway")
}

# ---------------------------------------------------------------------------
# 5. Gates must actually reject. A gate that never fires is not protection.
# ---------------------------------------------------------------------------
r5 <- run_agg(list(row("cand-good", iso_z(1), failed = 3)), label = "failing")
if (!is.null(r5$rec) && identical(as.character(r5$rec$recommendation), "NONE")) {
  ok("checks_failed_max rejects a candidate with failures")
} else {
  bad("checks_failed_max rejects failures", "a failing candidate was proposed")
}

r6 <- run_agg(list(row("cand-good", iso_z(1), risk = 0.95)), label = "risky")
if (!is.null(r6$rec) && identical(as.character(r6$rec$recommendation), "NONE")) {
  ok("a use-case-declared threshold (observed_risk_max) rejects")
} else {
  bad("use-case-declared threshold rejects",
      "a row above observed_risk_max was proposed")
}

# ---------------------------------------------------------------------------
# 6. A threshold declared but never measured must be named out loud. This is
#    how `package_risk_max` sat dead in the real policy without anyone noticing.
# ---------------------------------------------------------------------------
if (grepl("DEAD GATE", r1$out, fixed = TRUE) &&
    grepl("observed_risk_max", r1$out, fixed = TRUE)) {
  ok("a declared but unmeasured gate is reported as dead")
} else {
  bad("unmeasured gate is reported as dead",
      "no DEAD GATE report naming observed_risk_max")
}

# ---------------------------------------------------------------------------
# 7. A policy file that cannot be read must be fatal. Skipping it silently
#    removed every declared threshold while still reporting success.
# ---------------------------------------------------------------------------
r7 <- run_agg(list(row("cand-good", iso_z(1))),
              pol = file.path(tmp, "does-not-exist.yml"), label = "nopolicy")
if (r7$exit != 0) {
  ok("a missing policy file is fatal, not silently lenient")
} else {
  bad("missing policy file is fatal",
      "the aggregator ran with no gates and exited 0")
}

# ---------------------------------------------------------------------------
# 8. Corruption must be loud. A JSONL log is one record per line; a producer
#    that omits the trailing newline fuses its record onto the previous one.
#    Both records are then lost, and under a silent filter the loss is
#    indistinguishable from a week in which nothing was tried.
# ---------------------------------------------------------------------------
concat <- file.path(tmp, "concat.jsonl")
good   <- jsonlite::toJSON(row("cand-good", iso_z(1)), auto_unbox = TRUE)
writeLines(paste0(good, good), concat)   # two objects, one line
r8 <- run_agg_file(concat, pol = policy)
if (r8$exit != 0 && grepl("unparseable", r8$out, ignore.case = TRUE)) {
  ok("concatenated JSON objects on one line are fatal, not silently dropped")
} else {
  bad("corrupt telemetry is fatal",
      sprintf("exit=%d; corruption was tolerated: %s", r8$exit, r8$out))
}

# ---------------------------------------------------------------------------
# 9. The missing newline itself must be caught, not just its consequences.
#    This is the condition R's `readLines(warn = FALSE)` was hiding.
# ---------------------------------------------------------------------------
noeol <- file.path(tmp, "noeol.jsonl")
con <- file(noeol, "wb"); writeBin(charToRaw(paste0(good)), con); close(con)
r9 <- run_agg_file(noeol, pol = policy)
if (r9$exit != 0 && grepl("newline", r9$out, ignore.case = TRUE)) {
  ok("an unterminated final line is reported before it can corrupt an append")
} else {
  bad("unterminated final line is detected",
      sprintf("exit=%d; out: %s", r9$exit, r9$out))
}

# ---------------------------------------------------------------------------
# 10. LIVENESS / ROUND-TRIP. The tests above all hand the aggregator a file
#     this script wrote. That proves the reader works; it proves nothing about
#     the producer. Every failure this loop has had lived in the seam between
#     the two -- a field the reader required and no writer ever wrote, then a
#     newline the writer dropped and the reader silently forgave.
#
#     So: emit a row exactly the way the nightly workflow's "Collect the row"
#     step emits it (json.dump + explicit newline), append it exactly the way
#     the telemetry job appends it (cat), and require that a PROPOSE comes out
#     the far end. This is the only test that fails if writer and reader drift
#     apart.
# ---------------------------------------------------------------------------
rt <- file.path(tmp, "roundtrip.jsonl")
unlink(rt)
py <- Sys.which("python3")
if (!nzchar(py)) {
  bad("round-trip", "python3 not available to reproduce the producer")
} else {
  for (i in 1:3) {
    rowfile <- file.path(tmp, sprintf("metrics-row-%d.json", i))
    payload <- jsonlite::toJSON(row("cand-good", iso_z(i)), auto_unbox = TRUE)
    writeLines(as.character(payload), file.path(tmp, "payload.json"))
    # Mirror of the workflow step, including the newline it must write.
    script <- sprintf(paste0(
      "import json\n",
      "row = json.load(open(%s))\n",
      "with open(%s, 'w') as fh:\n",
      "    json.dump(row, fh)\n",
      "    fh.write('\\n')\n"),
      shQuote(file.path(tmp, "payload.json")), shQuote(rowfile))
    system2(py, c("-c", shQuote(script)))
    # Mirror of the telemetry job's append.
    file.append(rt, rowfile)
  }
  n_lines <- length(readLines(rt, warn = FALSE))
  r10 <- run_agg_file(rt, pol = policy)
  rec <- r10$rec
  if (n_lines != 3) {
    bad("round-trip: producer output is one record per line",
        sprintf("appended 3 rows but the log has %d line(s)", n_lines))
  } else if (r10$exit == 0 && !is.null(rec) && identical(rec$recommendation, "PROPOSE")) {
    ok("round-trip: a row written by the producer survives to a PROPOSE")
  } else {
    bad("round-trip: a row written by the producer survives to a PROPOSE",
        sprintf("exit=%d recommendation=%s", r10$exit,
                if (is.null(rec)) "<none>" else rec$recommendation))
  }
}

unlink(tmp, recursive = TRUE)
cat(sprintf("\n%s\n", if (fails == 0L) "All aggregator tests passed."
            else sprintf("%d aggregator test(s) FAILED.", fails)))
quit(status = if (fails == 0L) 0L else 1L)
