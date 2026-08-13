<!--
Agents: fill this in from artifacts CI produced. Do not state a number you did
not measure. An unsupported claim in a PR description is worse than no claim,
because it costs the reviewer the time to discover it was unsupported.
-->

## What changed and why

<!-- One paragraph. What problem does this solve? -->

## Environment impact

- [ ] No environment change (no edit to `env/**`)
- [ ] Environment changed — delta verdict: `<VERDICT>`

If the environment changed, paste the four-layer delta summary from the CI
comment, or state `BASELINE_ESTABLISHED` if no baseline existed yet.

| Layer | Change |
|---|---|
| 1. Image digest | |
| 2. Base / OS | |
| 3. R packages | |
| 4. Results | |

## Validation evidence

| | |
|---|---|
| PQ assertions passed / failed | |
| Strict vs tolerant split | |
| Max absolute deviation | |
| Tolerance utilisation | |

Tolerance utilisation above ~0.8 means little headroom remains and deserves a
sentence explaining why it is acceptable.

## Trade-offs

<!--
Required. State where this approach is WORSE than the alternative you rejected.
If you cannot name a downside, you have probably not compared it to anything.
-->

## Checklist

- [ ] I did not commit to `main`
- [ ] I did not hand-edit a generated file (`renv.lock`, `default.nix`)
- [ ] I did not hand-edit a committed fixture
- [ ] I did not weaken or bypass a gate
- [ ] Every number above comes from a CI artifact, not an estimate
- [ ] `env-validate` and `lint` pass

---

**Reviewer:** the gates can tell you this builds and the numbers stayed within
tolerance. They cannot tell you whether the packages that changed matter for
your therapeutic area, or whether this is the right point in your release cycle
to move the environment. That judgement is yours.
