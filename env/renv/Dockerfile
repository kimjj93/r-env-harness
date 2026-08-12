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
# sysreqs.txt lists build-time deps; sysreqs-runtime.txt lists only the shared
# libraries needed at runtime. We install everything, build packages, then swap
# to a minimal runtime set in a single layer to avoid bloat.
COPY env/renv/sysreqs.txt /tmp/sysreqs.txt
COPY env/renv/sysreqs-runtime.txt /tmp/sysreqs-runtime.txt

# renv itself is pinned; installing it unpinned would undermine the whole point.
ARG RENV_VERSION=1.0.11

WORKDIR /project

# Copy ONLY the lockfile before restoring, so that editing an analysis script
# does not invalidate the (expensive) package layer.
COPY env/renv/renv.lock /project/renv.lock

# Single-layer install: system deps → renv → restore → strip build deps.
# Keeping this in one RUN avoids layer bloat from intermediate files.
RUN apt-get update && \
    xargs -a /tmp/sysreqs.txt apt-get install -y --no-install-recommends && \
    R -q -e "install.packages('renv', repos='${PPM_URL}'); \
             if (packageVersion('renv') != '${RENV_VERSION}') \
               renv::install('renv@${RENV_VERSION}', prompt = FALSE)" && \
    R -q -e "renv::restore(lockfile = '/project/renv.lock', clean = TRUE, prompt = FALSE)" && \
    # --- Size reduction: remove build-only dev headers and large tools --- \
    apt-get remove -y --purge \
      libcurl4-openssl-dev libssl-dev libxml2-dev libfontconfig1-dev \
      libharfbuzz-dev libfribidi-dev libfreetype6-dev libpng-dev \
      libtiff5-dev libjpeg-dev libgit2-dev pandoc git && \
    apt-get autoremove -y --purge && \
    # Ensure runtime shared libraries are present \
    xargs -a /tmp/sysreqs-runtime.txt apt-get install -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/* /tmp/sysreqs.txt /tmp/sysreqs-runtime.txt && \
    # --- Size reduction: strip debug symbols from shared libraries --- \
    find /usr/local/lib/R/ -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    # --- Size reduction: remove renv cache (packages already in library) --- \
    rm -rf ${RENV_PATHS_CACHE} && \
    # --- Size reduction: remove package docs, examples, and object files --- \
    find /usr/local/lib/R/site-library/ -type d -name "doc" -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/R/site-library/ -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/R/site-library/ -name "*.o" -delete 2>/dev/null || true && \
    find /usr/local/lib/R/site-library/ -name "*.a" -delete 2>/dev/null || true

# Project source comes after the package layer.
COPY analysis/    /project/analysis/
COPY validation/  /project/validation/
COPY harness/     /project/harness/

# Record what was actually installed, baked into the image itself.
RUN R -q -f /project/harness/image_manifest.R --args /project/manifest.json || true

CMD ["R"]
