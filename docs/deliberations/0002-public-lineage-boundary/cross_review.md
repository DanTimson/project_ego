# Cross-review

| topic | binary position | engine position | status | required evidence or resolution |
|---|---|---|---|---|
| necessity and transfer taxonomy | Use independent `N*` necessity and `T*` transfer classes. | Accepts the taxonomy and requests basis-surface and public-sufficiency fields. | `resolved_after_review` | Registry now records `binary_basis_surface` and `public_basis_sufficient`; no further evidence required. |
| future binary-request gate | Public/black-box sources first; proceed only for observable, material, unresolved and reducible ambiguity. | Accepts prospectively; “unresolved” must mean unresolved at the precision required by the engine, and closed work must not be invalidated retroactively. | `resolved_after_review` | Gate is prospective and precision-sensitive. |
| current implementation contamination | Suspected a mixture of comment and structural transfer risk. | Measured 37 address citations across eight implementation files; all are comments, while only a few narrow rules affect structure. | `resolved_after_review` | Most implementation rows remain or become `T1_SANITIZE`; narrow binary-only behavioural structures remain `T2_REIMPLEMENT`. |
| fresh public lineage versus in-place sanitation | Recommend preserving the mixed lineage and creating a fresh public implementation line at the community-release gate. | Agrees; migration cost is acceptable if tests transfer first. | `agreed` | Adopt Option C subject to human acceptance. |
| test and fixture migration order | Transfer neutral specifications and tests into the future lineage. | Requires classification and transfer of the test corpus, synthetic fixtures and golden vectors before implementation rewrites. | `resolved_after_review` | Tests and fixtures transfer first. |
| timing of `T2` rewrites | Immediate for correctness defects or spreading binary-shaped dependencies; otherwise defer until specifications and profiles stabilize. | Agrees and adds oracle/port or maintained-implementation disagreement as an immediate trigger. | `resolved_after_review` | Rewrite trigger list amended. |
| modifier `0x12` correctness issue | Identified separate stat-penalty immunity as wrong. | Confirmed, found two dead duplicate helpers, and landed the correction plus oracle test update. | `resolved_after_review` | Mark registry rows corrected and `T1_SANITIZE`; no further implementation action in this deliberation. |
| evidence-document classification | Principal binary evidence belongs only in the research lineage. | Requests explicit rows so a future migration cannot copy all of `docs/` indiscriminately. | `agreed` | Explicit `T3_RESEARCH_ONLY` rows added for requests, ledgers, function map, reverse-engineering notes and private exports. |
| generated `bindings.json` | General parser/data policy covered generated content but did not classify populated bindings. | Identifies populated opcode-to-name mappings as a distinct redistribution edge. | `resolved_after_review` | Added `T4_DELIBERATE` row; keep populated generated outputs uncommitted until policy is decided. |
| remaining binary queue | Pause broad R16, reframe R17, and gate R10/R12/R13. | No disagreement. | `agreed` | Reissue the queue after the decision is accepted. |
| relationship to DELIB-0001 | Do not rewrite the accepted decision; open a separate profile deliberation. | Agrees and adds the canonical scenario-definition question. | `resolved_after_review` | A follow-up deliberation will decide charge, restored-capacity attack cost, legacy/native RNG, canonical scenario definitions and the scope of exact fidelity. |

## Remaining human decisions

1. Accept, amend or reject **Option C**: preserve the current mixed
   research/prototype lineage and create a fresh public implementation lineage
   only when the community-release gate is reached.
2. Confirm that the converged amendments above become binding governance for
   future binary requests and eventual transfer work.

The detailed Genesis/NH/native ruleset choices are deliberately deferred to a
separate follow-up deliberation and do not block DELIB-0002.

## Resolved during review

- The stamina/stat-penalty defect was corrected on the engine side.
- The necessity gate is prospective and precision-sensitive.
- Tests and neutral fixtures transfer before implementation rewrites.
- Most existing implementation provenance is comment-only and belongs under
  `T1_SANITIZE`, not broad mandatory rewrite.
- Evidence documents are explicitly `T3_RESEARCH_ONLY`.
- Populated generated bindings require a separate redistribution decision.
- No additional binary extraction is required for this deliberation.
