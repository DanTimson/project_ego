# Documentation working rules

This file applies to `docs/` and its subdirectories.

## Evidence documents

Evidence documents record what a source supports, with confidence,
observation status, binding scope and engine obligation kept separate.

- Preserve addresses, source locators, rejected alternatives and uncertainty.
- Do not turn a recovered implementation detail into a universal engine
  requirement without stating its binding scope.
- `PROVEN` does not imply `VERIFIED`.
- Engine implementation status is maintained separately from binary confidence.

## Deliberations

`docs/deliberations/` is for architectural or workflow questions that benefit
from independent positions.

- `brief.md` is human-owned.
- `position_binary.md` and `position_engine.md` are independent analyses.
- Do not edit the other side's position during independent review.
- `cross_review.md` isolates agreements and genuine disputes.
- `decision.md` is the only binding artifact in a deliberation package.
- Accepted decisions are not rewritten to erase history. Supersede them with a
  new deliberation when the decision materially changes.
- Keep implementation progress in `status.yaml`; do not turn position essays
  into status logs.

Validate deliberation packages with:

```bash
python3 tools/check_deliberations.py
```
