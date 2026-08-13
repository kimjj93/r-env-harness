---
name: env-pinning
description: Define and modify reproducible R environments using either renv + a dated Posit Package Manager snapshot on a digest-pinned Rocker base (Track A), or Nix via {rix} pinning a dated rstats-on-nix revision (Track B). Use when changing R version, package versions, snapshot dates, base images, or system dependencies.
---

# Skill: Environment Pinning

## Purpose

Produce an R environment that resolves to **exactly the same bits** every time it
is built, today or in five years, and that can be described in a submission.

## The pinning hierarchy

Reproducibility fails at the weakest link. Four layers must all be pinned:

| Layer | Track A | Track B |
|---|---|---|
| OS + system libraries | base image digest | nixpkgs revision |
| R itself | base image digest | nixpkgs revision |
| CRAN state | dated PPM snapshot | dated nixpkgs revision |
| Exact packages | `renv.lock` hashes | Nix derivation hashes |

A `renv.lock` alone does **not** pin the OS or system libraries. That is why the
lockfile always travels inside a container here.

## Track A — renv + PPM + Rocker

Snapshot URL format (Linux binary packages):

```
https://packagemanager.posit.co/cran/__linux__/<codename>/<YYYY-MM-DD>
```

Use the Ubuntu codename matching the base image (`jammy` for Ubuntu 22.04, which
`rocker/r-ver:4.4.x` uses). Getting this wrong silently falls back to slow source
builds.

Rules:

- Pin the base by digest, never by tag: `FROM rocker/r-ver:4.4.2@sha256:...`.
  Tags are mutable and can be re-pushed underneath you; a digest cannot.
- Record the snapshot date in `env/renv/ppm-snapshot.txt` so it is greppable and
  diffable independently of the Dockerfile.
- Copy `renv.lock` and restore **before** copying project source, so that editing
  an analysis script does not invalidate the package layer cache.
- Use `renv::restore(clean = TRUE)` so the library cannot contain anything the
  lockfile does not describe.
- Non-`latest` `rocker/r-ver` images already default `options(repos)` to a PPM
  snapshot near the R release date. Set it explicitly anyway — inherited defaults
  are not evidence.

Key commands: `renv::init()`, `renv::snapshot()`, `renv::restore()`,
`renv::status()` (use in CI to detect drift between library and lockfile).

## Track B — Nix via {rix}

Never hand-write `default.nix`. Edit `env/nix/generate_env.R`, which calls:

```r
rix(
  date        = "YYYY-MM-DD",   # dated nixpkgs snapshot; preferred for new work
  r_pkgs      = c(...),
  system_pkgs = c(...),
  git_pkgs    = NULL,
  ide         = "other",
  project_path = ".",
  overwrite   = TRUE
)
```

`date =` pins CRAN state exactly as of that date and is preferred over
`r_ver =` (which trails CRAN by up to ~2 months). Never use
`r_ver = "bleeding-edge"` — it is not reproducible by construction.

`rix()` also writes `.Rprofile` (via `rix_init()`) to isolate the project from
system R library paths. Commit both generated files, and commit the generator.

Always configure the `rstats-on-nix` Cachix binary cache. Without it, builds
compile from source and can take hours.

Known limitation: roughly 5% of CRAN is unavailable in nixpkgs. If a required
package falls in that gap, record the candidate as `unsupported` on Track B
rather than forcing a workaround — the gap itself is a finding.

## Changing a pin

1. Change exactly **one** dimension at a time (snapshot date, R version, base
   digest, or a package set). Multi-dimensional changes make deltas
   uninterpretable and are the main cause of unattributable numeric drift.
2. Rebuild the image.
3. Run Performance Qualification inside it.
4. Generate the four-layer delta.
5. Report both tracks: agree, diverge, or unsupported.

## Anti-patterns

- `FROM rocker/r-ver:latest` or any floating tag
- `install.packages()` against undated CRAN
- editing `default.nix` directly
- bumping several pins at once "to save time"
- installing a package inside CI that is absent from the lockfile

## References

- Rocker versioned images — <https://github.com/rocker-org/rocker-versioned2>
- Posit Package Manager snapshots — <https://packagemanager.posit.co>
- `{rix}` — <https://github.com/ropensci/rix>
- `{renv}` — <https://rstudio.github.io/renv/>
