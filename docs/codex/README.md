# Codex task contracts

This directory contains bounded execution contracts for Codex or another coding
executor.

- `TASK_TEMPLATE.md` defines the required fields.
- `tasks/CX-*.md` contains frozen assignments.
- `../CODEX_WORK_QUEUE.md` is the live state index.
- `../WORK_ALLOCATION.md` defines authority and escalation.

The task contract, not the chat prompt, is the authoritative scope. A prompt may
point Codex to a contract but must not silently broaden it.

## Completion handoff

Every returned task must report:

1. files changed;
2. commands run and their results;
3. acceptance criteria satisfied;
4. assumptions made;
5. ambiguities or requested escalations;
6. whether executable behaviour changed;
7. suggested queue-state update.

A reviewer may accept, request revision, split or reclassify the task.
