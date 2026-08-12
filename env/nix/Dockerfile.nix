# Track B — wrap the built Nix closure into an OCI image.
#
# Built in two stages because the Nix closure is the artifact that carries the
# reproducibility guarantee; the image is only a delivery vehicle for it. If the
# closure fails to build, CI records the candidate as `unsupported` on this track
# rather than falling back to something less reproducible.

# nixos/nix pinned by digest for the same reason the Rocker base is (see
# env/renv/Dockerfile): tags are mutable, digests are not.
FROM nixos/nix:2.24.9@sha256:fd7a5c67d396fe6bddeb9c10779d97541ab3a1b2a9d744df3754a99add4046f1 AS builder

RUN mkdir -p /etc/nix && \
    printf 'experimental-features = nix-command flakes\nsubstituters = https://cache.nixos.org https://rstats-on-nix.cachix.org\ntrusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0=\n' \
      >> /etc/nix/nix.conf

WORKDIR /build
COPY env/nix/default.nix /build/default.nix

# Materialise the closure into a result symlink, then copy the full transitive
# closure so the final image contains exactly the pinned store paths.
RUN nix-build default.nix -o /build/result
RUN mkdir -p /build/closure && \
    nix-store -qR /build/result > /build/closure/paths.txt

FROM nixos/nix:2.24.9@sha256:fd7a5c67d396fe6bddeb9c10779d97541ab3a1b2a9d744df3754a99add4046f1

LABEL org.opencontainers.image.source="https://github.com/kimjj93/r-env-harness" \
      org.opencontainers.image.description="Track B: Nix/rix pinned R environment" \
      org.opencontainers.image.licenses="MIT" \
      harness.track="nix" \
      harness.nixpkgs_date="2025-01-15"

COPY --from=builder /nix/store /nix/store
COPY --from=builder /build/result /build/result

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Pin BLAS threading for the same reason as Track A: threaded BLAS makes the
# last bits of a linear-algebra result depend on the host's core count, which no
# pin in default.nix captures. Nix hashes the closure, not the machine.
ENV OPENBLAS_NUM_THREADS=1 \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1

# See env/renv/Dockerfile for the measurements. OpenBLAS picks a kernel from the
# host CPU at runtime, so an identical Nix closure still produces different last
# bits on different hardware. Nix hashes the closure, not the processor.
ARG OPENBLAS_CORETYPE=HASWELL
ENV OPENBLAS_CORETYPE=${OPENBLAS_CORETYPE}

WORKDIR /project
COPY env/nix/.Rprofile /project/.Rprofile
COPY analysis/    /project/analysis/
COPY validation/  /project/validation/
COPY harness/     /project/harness/

# Put the pinned R on PATH so `Rscript ...` resolves to the Nix-built one.
ENV PATH=/build/result/bin:$PATH

RUN Rscript /project/harness/image_manifest.R /project/manifest.json || true

CMD ["R"]
