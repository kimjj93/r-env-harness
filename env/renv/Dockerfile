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

# Ubuntu codename must match the base image (4.4.x -> jammy). A mismatch here
# silently falls back to slow source builds instead of binaries.
ARG PPM_SNAPSHOT=2025-01-15
ARG UBUNTU_CODENAME=jammy
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

# Set the snapshot explicitly rather than inheriting the base image default.
# An inherited default is not evidence.
RUN echo "options(repos = c(CRAN = '${PPM_URL}'), pkgType = 'binary')" \
      >> "${R_HOME}/etc/Rprofile.site"

# System dependencies required by the pharmaverse stack.
COPY env/renv/sysreqs.txt /tmp/sysreqs.txt
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
COPY env/renv/renv.lock /project/renv.lock
RUN R -q -e "renv::restore(lockfile = '/project/renv.lock', clean = TRUE, prompt = FALSE)"

# Project source comes after the package layer.
COPY analysis/    /project/analysis/
COPY validation/  /project/validation/
COPY harness/     /project/harness/

# Record what was actually installed, baked into the image itself.
RUN R -q -f /project/harness/image_manifest.R --args /project/manifest.json || true

CMD ["R"]
