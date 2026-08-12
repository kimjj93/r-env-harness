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
