# Tests of the comparison engine itself.
#
# Everything else in this suite tests the *environment*. This file tests the
# thing that decides whether the environment passed, because a comparison engine
# that is too permissive does not fail loudly -- it reports success. Each case
# below is a comparison that once passed and should not have.

test_that("tolerance never excuses a change in shape", {
  # Force the tolerant path: metadata that cannot match any live environment.
  meta <- list(r_version = "0.0.0", critical_pkgs = list(), backend = list())

  # `passed` is not returned, so observe the decision through the recorder.
  captured <- new.env(parent = emptyenv())
  captured$passed <- NA
  local_mocked <- function(...) {
    args <- list(...)
    captured$passed <- args$passed
    invisible(TRUE)
  }

  decide <- function(object, reference, tolerance = 1e-8) {
    old <- if (exists("recorder_record", envir = globalenv())) {
      get("recorder_record", envir = globalenv())
    } else NULL
    assign("recorder_record", local_mocked, envir = globalenv())
    on.exit({
      if (is.null(old)) rm("recorder_record", envir = globalenv())
      else assign("recorder_record", old, envir = globalenv())
    }, add = TRUE)
    try(suppressMessages(
      helper_expect_reference_match(object, reference, meta,
                                    case = "engine check", tolerance = tolerance)
    ), silent = TRUE)
    captured$passed
  }

  # Same six numbers, different shape. Flattened deviation is exactly zero, so
  # a values-only comparison reports a perfect match.
  expect_false(decide(matrix(1:6, 2, 3), matrix(1:6, 3, 2)))
  expect_false(decide(matrix(1:6, 2, 3), 1:6))

  # Same values, different labels. A renamed column is a different result.
  expect_false(decide(c(a = 1, b = 2), c(zz = 1, qq = 2)))

  # Length mismatch on an exact multiple recycles silently in R and yields a
  # deviation of zero without any warning.
  expect_false(decide(rep(1:5, 2), 1:5))

  # Genuine floating-point drift within tolerance must still pass, or the
  # tolerant path would be pointless.
  expect_true(decide(matrix(c(1, 2, 3, 4, 5, 6) + 1e-12, 2, 3),
                     matrix(c(1, 2, 3, 4, 5, 6), 2, 3)))
  expect_true(decide(c(a = 1, b = 2), c(a = 1, b = 2)))

  # Same shape, drift above tolerance: still a failure.
  expect_false(decide(matrix(c(1, 2, 3, 4, 5, 6) + 1e-6, 2, 3),
                      matrix(c(1, 2, 3, 4, 5, 6), 2, 3)))
})

test_that("the strict path is genuinely exact", {
  # testthat::expect_equal() carries a default tolerance of ~1.49e-8, so a
  # strict path built on it would accept the 1.42e-14 BLAS drift this harness
  # was created to detect. all.equal(tolerance = 0) is the only honest basis
  # for a report that claims an applied tolerance of 0.
  expect_false(isTRUE(all.equal(1.0, 1.0 + 1.42e-14, tolerance = 0)))
  expect_true(isTRUE(all.equal(1.0, 1.0 + 1.42e-14)))  # the trap, documented
})

test_that("structural mismatch names the attribute that differs", {
  expect_identical(helper_structural_mismatch(matrix(1:6, 2, 3), matrix(1:6, 3, 2)), "dim")
  expect_identical(helper_structural_mismatch(c(a = 1), c(b = 1)), "names")
  expect_identical(helper_structural_mismatch(1:5, 1:10), "length")
  expect_true(is.na(helper_structural_mismatch(matrix(1:6, 2, 3), matrix(1:6, 2, 3))))
})
