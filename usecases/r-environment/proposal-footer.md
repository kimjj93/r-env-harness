## Package risk

`riskmetric` scores for any newly introduced R package are in `risk-scan.json`
in the run artifacts. A package with no score is not a passing package; it is an
unmeasured one, and the difference matters in a submission.

## Methodology basis

- Three-phase decoupled validation and the strict/tolerant criterion:
  `pfizer-rd/rvalidation-refactored` — **private repository**. The architecture
  was adopted; the comparison semantics were replaced. See
  `skills/performance-qualification/SKILL.md` for the measured reasons.
- Dated snapshot pinning for repeatable deployments: Posit,
  *Containerization in Posit Connect*
- Submissions cite exact R and package versions:
  `philbowsher/Open-Source-in-New-Drug-Applications-NDAs-FDA`
- Package risk scoring: R Validation Hub `{riskmetric}`
- Nix-based full-closure pinning (Track B): `ropensci/rix`

## What a reviewer should check first

1. **Layer 4 of the delta.** If analysis outputs are unchanged, layers 1–3 are
   explanation rather than risk.
2. **Margin utilisation.** A candidate passing at 95% of its declared tolerance
   has consumed nearly all the available headroom and will fail on the next
   upstream nudge. Passing is not the same as safe.
3. **Whether both variants agree.** Divergence between `renv` and `nix` on the
   same calendar advance is a finding, not noise.
