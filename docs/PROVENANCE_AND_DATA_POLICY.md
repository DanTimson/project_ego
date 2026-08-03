# Provenance and data policy

Project EGO is a clean-room reimplementation and research project. The
repository distinguishes original project work from evidence obtained from a
local copy of Eador: Genesis.

## May be committed

- Project EGO source code;
- independently written behavioural specifications;
- structure layouts and address maps;
- hashes, file sizes and target metadata;
- test vectors that do not reproduce substantial original data;
- Project EGO schemas, bindings and conversion tools;
- short content examples required to explain a parser or incompatibility;
- citations and source manifests.

## Keep local/private

- original executables and DLLs;
- original `.var` tables in full;
- original graphics, audio and localization corpora;
- Ghidra project databases;
- large raw decompiler/listing dumps;
- extracted proprietary tables or assets.

`docs/EVIDENCE_SOURCES.csv` records local evidence by hash without requiring the
repository to carry the evidence itself.

## Evidence classes

- **binary** — original executable or supporting library;
- **game data** — `.var`, localization or assets from a local installation;
- **observation** — controlled play result;
- **published source** — documentation or external research;
- **derived evidence** — decompilation, structure map or trace;
- **Project EGO implementation** — independently written code and tests.

## Clean-room implementation rule

Recovered behaviour should be restated as algorithms, invariants, test vectors
and new code. Do not paste original executable bytes or bulk decompiler output
into production code.

When a mechanic is intentionally changed, retain a separately named legacy
compatibility path or document that exact compatibility is not claimed.

## Numeric names

Numeric modifier, upgrade and effect IDs remain numeric until data or
localization ties them to a name. Mechanically descriptive names such as
`life_steal_candidate` are working names, not proof of original terminology.

## Review requirements

A pull request based on reverse engineering should state:

- executable SHA-256;
- addresses examined;
- evidence source IDs;
- confidence;
- original-data files consulted;
- tests added;
- remaining alternatives;
- whether any local/private evidence must be retained by the contributor.

## Current local evidence anchor

The initial local archive is identified by:

```text
SHA-256 {archive_sha}
repository commit {repo_commit}
```

It is not repository content.
