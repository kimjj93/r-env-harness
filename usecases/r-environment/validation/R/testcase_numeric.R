#' Test case: numerical and RNG stability
#'
#' Environment-level numerical behaviour independent of the clinical payload.
#' Catches changes in BLAS/LAPACK, long-double handling, and RNG implementation
#' that package version diffs cannot see — the class of drift that makes two
#' "identical" libraries produce different numbers.
#'
#' @section Critical Packages:
#' stats.

testcase_generate_rng_kinds <- function() {
  # Every RNG dimension is set explicitly. An unseeded test in this framework
  # would silently invalidate every comparison built on it.
  old <- RNGkind()
  on.exit(do.call(RNGkind, as.list(old)), add = TRUE)

  RNGkind(kind = "Mersenne-Twister",
          normal.kind = "Inversion",
          sample.kind = "Rejection")
  set.seed(20260812)

  list(
    unif   = stats::runif(5),
    norm   = stats::rnorm(5),
    binom  = as.numeric(stats::rbinom(5, 10, 0.4)),
    samp   = as.numeric(sample.int(100, 5))
  )
}

testcase_generate_linalg <- function() {
  set.seed(42)
  m <- matrix(stats::runif(36), nrow = 6)
  sym <- crossprod(m)

  list(
    det      = det(sym),
    eigen1   = eigen(sym, only.values = TRUE)$values[[1]],
    solve_11 = solve(sym)[1, 1],
    chol_11  = chol(sym)[1, 1],
    svd_1    = svd(m)$d[[1]]
  )
}

#' Acceptance criterion for a floating-point linear algebra result.
#'
#' A single absolute tolerance cannot serve quantities that span four orders of
#' magnitude — here `det(sym)` is 5.7e-3 while `solve(sym)[1,1]` is 9.4e1. A flat
#' `1e-12` is 2e-10 relative on the first and 1e-14 relative on the second: far
#' too loose for one and tighter than the arithmetic can deliver for the other.
#' That is not an acceptance criterion, it is a guess that happens to pass.
#'
#' The defensible bound comes from numerical analysis. Solving a system with
#' condition number `k` can amplify representation error by up to `k`, so the
#' error in a computed result `x` is bounded on the order of
#'
#'     eps * |x| * k
#'
#' `safety` covers accumulation across the several operations that produce each
#' quantity and differences in blocking/FMA between BLAS builds.
#'
#' Two guards keep this honest:
#'   * `floor` stops the bound collapsing to ~0 for values near zero.
#'   * `ceiling` is a hard cap. A derived tolerance is still a tolerance, and it
#'     must never silently authorise a deviation large enough to change a
#'     reported result. Exceeding the cap is a fatal error, not a warning.
#'
#' @param ref_value the committed baseline value
#' @param kappa     condition number of the underlying matrix
linalg_tolerance <- function(ref_value, kappa,
                             safety  = 10,
                             floor   = 1e-13,
                             ceiling = 1e-6) {
  tol <- .Machine$double.eps * abs(ref_value) * kappa * safety
  tol <- max(tol, floor)
  if (tol > ceiling) {
    stop(sprintf(
      paste0("Derived linear-algebra tolerance %.3g exceeds the hard cap %.3g ",
             "(value=%.6g, kappa=%.6g). The problem is too ill-conditioned for ",
             "this assertion to mean anything; fix the test matrix rather than ",
             "raising the cap."),
      tol, ceiling, ref_value, kappa))
  }
  tol
}

#' Condition number of the matrix the linear algebra case is built on.
#'
#' Recomputed from the same seed rather than stored, so it cannot drift out of
#' step with the values it is used to judge.
testcase_linalg_kappa <- function() {
  set.seed(42)
  m <- matrix(stats::runif(36), nrow = 6)
  kappa(crossprod(m), exact = TRUE)
}
