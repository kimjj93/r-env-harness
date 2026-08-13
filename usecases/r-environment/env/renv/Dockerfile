# Track A — renv + dated Posit Package Manager snapshot on a digest-pinned Rocker base.
#
# Four pinning layers (see skills/env-pinning/SKILL.md):
#   1. OS + R          -> base image DIGEST (not a tag; tags are mutable)
#   2. CRAN state      -> dated PPM snapshot URL
#   3. Exact packages  -> renv.lock hashes
#   4. Nothing extra   -> renv::restore(clean = TRUE)

# rocker/r-ver:4.4.2 resolved 2026-08-12. A tag can be re-pushed underneath you;
# a digest cannot. This is what makes "we used rocker 4.4.2" into evidence.
FROM rocker/r-ver:4.4.2@sha256:df26749182af64d5263bf64149d51a427b476ed28c4e046997143be3f97fdd7c

# Ubuntu codename MUST match the base image. rocker/r-ver:4.4.2 is Ubuntu 24.04
# (noble), not jammy. Getting this wrong does not fail loudly -- it silently
# serves binaries built for the wrong OS -- so the build asserts it below.
ARG PPM_SNAPSHOT=2025-01-15
ARG UBUNTU_CODENAME=noble
ARG PPM_URL=https://packagemanager.posit.co/cran/__linux__/${UBUNTU_CODENAME}/${PPM_SNAPSHOT}

LABEL org.opencontainers.image.source="https://github.com/kimjj93/r-env-harness" \
      org.opencontainers.image.description="Track A: renv + PPM snapshot, validated R environment" \
      org.opencontainers.image.licenses="MIT" \
      harness.track="renv" \
      harness.ppm_snapshot="${PPM_SNAPSHOT}" \
      harness.ubuntu_codename="${UBUNTU_CODENAME}"

ENV RENV_CONFIG_REPOS_OVERRIDE=${PPM_URL} \
    RENV_PATHS_CACHE=/renv/cache \
    DEBIAN_FRONTEND=noninteractive

# Pin the BLAS thread count. This is a reproducibility control, not a
# performance setting, and it is as load-bearing as the package pins above.
#
# rocker/r-ver links R against *threaded* OpenBLAS (openblas-pthread). Threaded
# BLAS splits a reduction across threads and sums the partial results, so the
# summation order -- and therefore the last bits of the answer -- depends on how
# many threads it chose. That number is decided at runtime from the host CPU
# count. It is recorded in no lockfile, no image digest and no manifest.
#
# Measured on this exact image digest, varying only the thread count:
#
#   threads=1  solve_11=3.14491662711728885843e-03  svd_1=1.02006622600000116563e+03
#   threads=2  solve_11=3.14491662711728842475e-03  svd_1=1.02006622600000127932e+03
#   threads=4  solve_11=3.14491662711728842475e-03  svd_1=1.02006622600000207512e+03
#   threads=8  solve_11=3.14491662711728842475e-03  svd_1=1.02006622600000184775e+03
#
# Every svd_1 value differs. Same image, same BLAS, same package versions --
# different numbers, purely from the size of the machine it ran on. An
# environment that claims bit-for-bit reproducibility while depending on the
# runner's core count does not have it.
#
# Setting this to 1 costs wall-clock time on large linear algebra. For a
# validation environment that is the correct trade: determinism is the product.
ENV OPENBLAS_NUM_THREADS=1 \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1

# Pin the OpenBLAS kernel as well. Thread count was only half the problem.
#
# OpenBLAS ships several implementations of each routine and selects one at
# *runtime* from the CPU it finds. Different kernels use different vector widths
# and different blocking, so they round differently. GitHub's runner fleet is
# heterogeneous, so two runs of an identical image digest can land on different
# kernels and disagree in the last bits -- which is exactly what happened: after
# pinning threads alone, a fixture set that self-validated at max deviation 0 in
# one run failed at 1.42e-14 in the next.
#
# Measured on one image digest, OPENBLAS_NUM_THREADS=1 throughout, varying only
# the kernel:
#
#   HASWELL      solve_11=3.14491662711728885843e-03
#   SANDYBRIDGE  solve_11=3.14491662711728929211e-03
#   NEHALEM      solve_11=3.14491662711728885843e-03
#
# HASWELL (AVX2, 2013) is the default because it is both broadly available --
# including under x86_64 emulation on Apple Silicon, where this was verified --
# and fast. Override at build time only if you must target older hardware:
#
#   docker build --build-arg OPENBLAS_CORETYPE=NEHALEM ...
#
# WARNING: forcing a kernel the CPU cannot execute does not fail cleanly. On
# hardware without the required instructions the process hangs rather than
# erroring, so this value must be chosen for the *oldest* CPU in your fleet.
ARG OPENBLAS_CORETYPE=HASWELL
ENV OPENBLAS_CORETYPE=${OPENBLAS_CORETYPE}

# Fail loudly if the declared codename does not match the base image. Without
# this the mismatch is invisible: the build still succeeds, but against packages
# compiled for a different OS -- which is precisely the class of silent drift
# this repository exists to prevent.
RUN . /etc/os-release && \
    if [ "${VERSION_CODENAME}" != "${UBUNTU_CODENAME}" ]; then \
      echo "FATAL: base image is '${VERSION_CODENAME}' but UBUNTU_CODENAME='${UBUNTU_CODENAME}'." >&2; \
      echo "The PPM snapshot URL would serve binaries for the wrong OS." >&2; \
      exit 1; \
    fi && \
    echo "OK: base image and PPM codename agree (${VERSION_CODENAME})"

# Set the snapshot explicitly rather than inheriting the base image default.
# An inherited default is not evidence.
# NOTE: no pkgType='binary' -- that value is unsupported on Linux. PPM serves
# Linux binaries through the normal source path via the __linux__/<codename>
# URL, so requesting 'binary' here fails the build outright.
RUN echo "options(repos = c(CRAN = '${PPM_URL}'))" \
      >> "${R_HOME}/etc/Rprofile.site"

# System dependencies required by the pharmaverse stack.
COPY usecases/r-environment/env/renv/sysreqs.txt /tmp/sysreqs.txt
RUN apt-get update && \
    xargs -a /tmp/sysreqs.txt apt-get install -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/* /tmp/sysreqs.txt

# renv itself is pinned; installing it unpinned would undermine the whole point.
ARG RENV_VERSION=1.0.11
RUN R -q -e "install.packages('renv', repos='${PPM_URL}'); \
             if (packageVersion('renv') != '${RENV_VERSION}') \
               renv::install('renv@${RENV_VERSION}', prompt = FALSE)"

WORKDIR /project

# Copy ONLY the lockfile before restoring, so that editing an analysis script
# does not invalidate the (expensive) package layer.
COPY usecases/r-environment/env/renv/renv.lock /project/renv.lock
RUN R -q -e "renv::restore(lockfile = '/project/renv.lock', clean = TRUE, prompt = FALSE)"

# Project source comes after the package layer.
COPY usecases/r-environment/analysis/    /project/usecases/r-environment/analysis/
COPY usecases/r-environment/validation/  /project/usecases/r-environment/validation/
COPY usecases/r-environment/bin/       /project/usecases/r-environment/bin/
COPY harness/         /project/harness/

# Record what was actually installed, baked into the image itself.
RUN R -q -f /project/harness/image_manifest.R --args /project/manifest.json || true

CMD ["R"]
