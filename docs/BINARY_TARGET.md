# Binary target — Eador: Genesis 1.05.2 RU

This file anchors the reverse-engineering evidence to one executable and one
repository state.

## Repository anchor

```text
commit: 5721c79d59ad370ae6f7ae8a6b4e5a3c48760ca2
git status --short: no output reported by the user
```

## Game target

| field | value |
|---|---|
| executable | `Eador_debug.exe` |
| distribution | GOG |
| game version shown | 1.05.2 |
| language | Russian |
| modification state | vanilla |
| operating system used by owner | Windows 10 |
| file size | 1,170,432 bytes |
| SHA-256 | `443329dde09a80be9a71f86cd193c9b2c156cb203ae26a2cf6bea5fface5a1c0` |
| MD5 | `13fe642f4456d1969714bd475f457a45` |
| PE format | PE32, Intel i386, Windows GUI |
| image base | `0x00400000` |
| entry point | `0x00405D7D` |
| PE timestamp | 2012-11-20 10:47:41 UTC |
| linker version field | 9.0 |
| relocations | stripped |
| number of sections | 4 |

### Sections

| section | virtual address | size | role |
|---|---:|---:|---|
| `.text` | `0x00401000` | `0x0010D6ED` | code |
| `.rdata` | `0x0050F000` | `0x0000D3A8` | read-only data/imports |
| `.data` | `0x0051D000` | `0x00002000` | writable data |
| `.rsrc` | `0x005AA000` | `0x00000B1C` | resources |

Imported DLLs observed in the PE import table:

```text
alogg.dll
alleg43.dll
KERNEL32.dll
SHELL32.dll
```

The executable hash in `metadata/hashes.txt` matches the uploaded file. The
Ghidra database records the same MD5 and SHA-256.

## Ghidra analysis target

| field | value |
|---|---|
| Ghidra version | 12.1.2 |
| language ID | `x86:LE:32:default` |
| compiler specification | `windows` |
| program name | `Eador_debug.exe` |
| project database | `Eador Ghidra.rep/` |
| project tree SHA-256 | `df400b9d65aaf2f129fd767d393c15fe9fcb4ee49eb897b39c0718c2f4488f07` |
| current runtime schema | 14 |

The archive contains the full `.rep` directory and a zero-byte
`ghidra_project.txt`. That zero-byte file is consistent with the renamed Ghidra
project marker supplied by the user. For restoration it should be paired with
the repository directory under the matching name:

```text
Eador Ghidra.gpr
Eador Ghidra.rep/
```

A reconstructed project package was generated separately, but it has not been
opened in Ghidra in this environment.

## Evidence archive

| field | value |
|---|---|
| archive | `Eador_archive.zip` |
| size | 13,194,902 bytes |
| SHA-256 | `2dcfe4acd86697f3f5b7d363a9916d13d44f19b48fe178368937794fe7b111b0` |
| exports tree SHA-256 | `bced37fc1b9393fe28435bf1e241bf0ca8c4ead4b945ba7326b2bd2bb939adc1` |
| `.var` data tree SHA-256 | `31e4ba687a17cc86b070b974102f70375ebf5808b153c532dd3b72c15af56593` |

The archive is local evidence and should not be committed to the public
repository.

## Included evidence

- original executable;
- Ghidra project database;
- `closer_inspection_1.txt` through `closer_inspection_11.txt`;
- 14 Russian CP1251 `.var` files, including unit, upgrade, spell, skill, item,
  item-set, terrain and battlefield-object data;
- initial target metadata and executable hash.

## Not included or incomplete

- separate localization/description files, if the installation contains them;
- older exports such as `unit_calls_*`, `unit_func.txt`, `start_func.txt` and
  `massive_unit_func.txt`;
- a project marker retaining its original `.gpr` filename;
- explicit notes on non-default Ghidra analysis options;
- installation date and patch history;
- supporting DLL binaries, which may later help resolve Allegro ordinal imports.

These omissions do not block the current evidence-ledger, dictionary and test
planning work. Separate localization would be the most useful addition for
confirming game-facing terminology.
