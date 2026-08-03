# Local evidence

This directory intentionally contains no original game binary or data.

The canonical manifest is `docs/EVIDENCE_SOURCES.csv`. Contributors keep local
evidence under any convenient path and identify it by SHA-256.

Recommended local layout:

```text
.local/evidence/eador-1.05.2-ru-gog/
├── Eador_debug.exe
├── Eador Ghidra.gpr
├── Eador Ghidra.rep/
├── exports/
└── data/
```

Add `.local/` to local Git excludes or the repository `.gitignore` before
placing original material there.

When sharing a new reverse-engineering claim, provide the source ID and address,
not a public link to the original binary.
