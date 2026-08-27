# Provenance and data policy

Project EGO is an independent reimplementation and research project. The
repository distinguishes original project work from evidence obtained from a
local copy of Eador: Genesis.

The project does **not** claim a clean-room (Chinese-wall) process. Clean-room
has a specific meaning — one party inspects the original and writes a functional
specification, and a separate party implements from that specification without
access to the original. Project EGO is developed by contributors who both
inspect the executable and write the implementation, so the term does not apply
and is not used.

What the project does claim is stated in *Legal basis* below.

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

## Legal basis

The project relies on the principle that a program's *functionality*, its
programming language and its *data file formats* are not themselves protected by
copyright — the position taken by the Court of Justice of the European Union in
*SAS Institute Inc. v World Programming Ltd* (C-406/10, 2 May 2012). Behavioural
rules, numeric tables, `.var` grammar and file-format descriptions fall on that
side of the line. Original expression — code, assets, text, bulk decompiler
output — does not, and is never committed.

Note explicitly what the project does *not* rely on: Article 6 of Directive
2009/24/EC permits decompilation only for achieving interoperability with an
independently created program, and is not a general permission to reimplement.
Where inspection of the executable is used, it is used to determine the ideas
and principles underlying a rule, and the resulting rule is then restated and
implemented in new code.

Eador: Genesis is a commercially available product. Nothing here treats it as
abandonware.

This section records the project's reasoning, not legal advice. Contributors
distributing builds in their own jurisdiction should get their own.

## Independent implementation rule

Recovered behaviour should be restated as algorithms, invariants, test vectors
and new code. Do not paste original executable bytes or bulk decompiler output
into production code.

When a mechanic is intentionally changed, retain a separately named legacy
compatibility path or document that exact compatibility is not claimed.

## Numeric names

Numeric modifier, upgrade and effect IDs remain numeric until data or
localization ties them to a name. Mechanically descriptive names such as
`life_steal_candidate` are working names, not proof of original terminology.

## Tracked provenance hold: `tools/reference/abil_doc.json`

PV-1 reviewed the tracked blob and its tracked history without modifying it. The
file first appears in commit
`39652abdae0c1c162ae9296be3d61b0f4a781ba2` (2026-07-26), whose subject is
“populated with placeholders”; no earlier tracked version or tracked generator
is present. The current blob is 239,237 bytes with SHA-256
`aaa7a9b97369331d42470ab41b0328e9c9d6a9e5bcdff0653801744060c88be4` and has
not changed since introduction. A later historical tree caption called it
“extracted ability documentation”, but supplies no source linkage or method and
is not sufficient provenance.

Tracked evidence does **not** establish the source publication/build/file,
whether the content was extracted, copied, transcribed, generated, transformed
or authored, a source version/date/hash/path, or its redistribution/licensing
basis. Commit authorship, Russian text, the filename and downstream tool use are
not substitutes for those facts. The artifact therefore remains HELD and its
lineage registry row remains explicitly `unclassified`; no transfer class has
been inferred.

**Bounded owner question:** can the artifact owner provide a tracked source
record that identifies the exact source/publication/build/file and
version/date/hash/path, documents the acquisition and transformation method, and
states the redistribution/licensing basis for the blob introduced by
`39652ab`? If not, governance must decide whether it remains private or is
removed/replaced; this audit does not make that decision.

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
archive              Eador_archive.zip
SHA-256              2dcfe4acd86697f3f5b7d363a9916d13d44f19b48fe178368937794fe7b111b0
size                 13,194,902 bytes
repository anchor    5721c79d59ad370ae6f7ae8a6b4e5a3c48760ca2
manifest             docs/EVIDENCE_SOURCES.csv (source ID ARCHIVE-20260803)
```

It is not repository content. The per-file breakdown, including the executable
and Ghidra project hashes, is in `docs/EVIDENCE_SOURCES.csv` and
`docs/BINARY_TARGET.md`.
