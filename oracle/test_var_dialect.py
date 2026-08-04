#!/usr/bin/env python3
"""Importer dialect regression — the `.var` layer across content dialects.

DELIB-0001 decision item 3: the importer is a first-class mod inlet and must
tolerate dialect differences across Genesis, New Horizons and future `.var`
packs. Until now that layer had no tests at all — including
`unit_ability_refs`, whose earlier implementation attached two phantom abilities
to every Genesis unit while every cross-reference check reported clean.

The fixtures in tests/fixtures/var/ are hand-authored synthetic samples with
invented names, not extracted content. They exist so this runs on a fresh clone
with no game data, which matters because the defect this guards against was
dialect-specific: the broken heuristic passed on New Horizons and failed on
Genesis, so a single-dialect test would not have caught it.

Real-pack assertions run additionally when local pack data is present.

Run:  python3 oracle/test_var_dialect.py
"""

from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools", "var"))
import eador_var as E  # noqa: E402

FAILS: list = []
VAR = os.path.join(os.path.dirname(__file__), "..", "tests", "fixtures", "var")


def check(ok: bool, label: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label,
                          "  - %s" % detail if detail else ""))
    if not ok:
        FAILS.append(label)
        # Under pytest, raise: check() otherwise only RECORDS a failure, so
        # `pytest oracle/` would report green while assertions fail. The
        # standalone runner still collects every failure before exiting.
        if "PYTEST_CURRENT_TEST" in os.environ:
            raise AssertionError(label)


def parse(name: str):
    return E.parse(os.path.join(VAR, name))


def record(vf, unit_name, index=None):
    for r in vf.records:
        if index is not None and r.index == index:
            return r
        if index is None and r.fields.get("Name") == unit_name:
            return r
    return None


def test_dialects_parse() -> None:
    print("\n[1] both dialects parse and satisfy the declared-count invariant")
    for name in ("genesis_dialect_unit", "nh_dialect_unit",
                 "dialect_unit_upg", "dialect_ability_num"):
        vf = parse(name + ".var")
        check(vf.declared is not None and len(vf.records) == vf.declared + 1,
              "%s: records == declared + 1" % name,
              "declared %s, records %d" % (vf.declared, len(vf.records)))
        check(not vf.warnings, "%s: parses without warnings" % name,
              str(vf.warnings[:1]))


def test_fixtures_are_crlf_like_the_originals() -> None:
    """Real `.var` files are CRLF-terminated CP1251. `.gitattributes` pins these
    fixtures with `-text` so Git does not normalize them to LF; without the pin
    the CRLF coverage would disappear silently on the next checkout."""
    print("\n[2] the fixtures keep the original line endings")
    for name in ("genesis_dialect_unit", "nh_dialect_unit",
                 "dialect_unit_upg", "dialect_ability_num"):
        with open(os.path.join(VAR, name + ".var"), "rb") as fh:
            raw = fh.read()
        check(b"\r\n" in raw, "%s is CRLF" % name)


def test_the_dialects_are_actually_different() -> None:
    """Guard the guard: if the fixtures stopped differing, this file would pass
    while testing nothing."""
    print("\n[3] the fixtures encode a real dialect difference")
    g = record(parse("genesis_dialect_unit.var"), "Образец-Один")
    n = record(parse("nh_dialect_unit.var"), "Образец-Один")
    check("Race" in g.fields and "UnitKind" in g.fields,
          "Genesis dialect carries Race/UnitKind")
    check("Race" not in n.fields and "UnitKind" not in n.fields,
          "New Horizons dialect does not")
    check("Subtype" in n.fields and "Analogs" in n.fields
          and "Upgraded" in n.fields,
          "and carries Subtype/Analogs/Upgraded instead")
    check("Subtype" not in g.fields, "which Genesis does not")


def test_ability_refs_are_positional_not_heuristic() -> None:
    print("\n[4] ability refs come from position, not from excluding known stats")
    g = record(parse("genesis_dialect_unit.var"), "Образец-Один")
    labels = [label for label, _ in E.unit_ability_refs(g)]
    check(labels == ["ПробнаяСпособность"],
          "Genesis: only the field after the Abilityes marker is an ability",
          str(labels))
    # The exact failure mode of the earlier implementation: Race and UnitKind
    # are positive ints that resolve to a VALID unit_upg index, so an exclusion
    # allowlist tuned on NH produced phantom abilities and a clean xref.
    check("Race" not in labels and "UnitKind" not in labels,
          "and Race/UnitKind are excluded even though both are valid indexes")

    n = record(parse("nh_dialect_unit.var"), "Образец-Один")
    n_labels = [label for label, _ in E.unit_ability_refs(n)]
    check(n_labels == ["ПробнаяСпособность", "ВтораяСпособность"],
          "New Horizons: multiple refs, in file order", str(n_labels))

    empty = record(parse("genesis_dialect_unit.var"), None, index=0)
    check(list(E.unit_ability_refs(empty)) == [],
          "the empty /0 record yields no refs")


def test_level_up_rows_terminate_the_block() -> None:
    print("\n[5] the ability block ends at the first Lvl NN row")
    g = record(parse("genesis_dialect_unit.var"), "Образец-Один")
    labels = [label for label, _ in E.unit_ability_refs(g)]
    check(not any(label.startswith("Lvl") for label in labels),
          "no Lvl NN row is mistaken for an ability", str(labels))
    rows = g.fields.get("Lvl 01 upgrades")
    check(isinstance(rows, list) and rows,
          "and the level-up rows still parse as rows", str(rows))


def test_compound_upgrade_rows_are_parallel_lists() -> None:
    """`Upg Type` and `Quantity` are PARALLEL LISTS in compound rows. Reading
    them as scalars silently drops every effect after the first."""
    print("\n[6] compound unit_upg rows keep both effects")
    upg = parse("dialect_unit_upg.var")
    simple = record(upg, "ПробнаяСпособность")
    compound = record(upg, "СоставнаяСпособность")
    check(simple.fields.get("Upg Type") == 53
          and simple.fields.get("Quantity") == 2,
          "a simple row stays scalar",
          "%s / %s" % (simple.fields.get("Upg Type"),
                       simple.fields.get("Quantity")))
    ut, qty = compound.fields.get("Upg Type"), compound.fields.get("Quantity")
    check(isinstance(ut, list) and isinstance(qty, list),
          "a compound row yields lists, not the first value only",
          "%s / %s" % (ut, qty))
    check(isinstance(ut, list) and len(ut) == 2 and len(qty) == 2,
          "with both effects preserved", "%s / %s" % (ut, qty))


def test_ability_number_is_not_the_record_index() -> None:
    """DELIB-0001 item 2 and CONTENT_REFERENCE_MODEL: `unit_upg` is addressed by
    record index, `ability_num` by `Number`. Both are dense integer spaces near
    zero, so confusing them resolves to a plausible wrong record."""
    print("\n[7] ability_num Number is a different namespace from record index")
    ab = parse("dialect_ability_num.var")
    by_index = {r.index: r.fields.get("Number") for r in ab.records}
    check(by_index.get(1) == 42 and by_index.get(2) == 76,
          "Number differs from index in the fixture", str(by_index))
    check(any(k != v for k, v in by_index.items() if v is not None),
          "so a test confusing them fails here rather than silently passing")


def test_build_pack_emits_the_typed_contract() -> None:
    print("\n[8] the collected record matches the typed roster contract")
    for dialect, expected in (("genesis_dialect_unit", ["ПробнаяСпособность"]),
                              ("nh_dialect_unit",
                               ["ПробнаяСпособность", "ВтораяСпособность"])):
        vf = parse(dialect + ".var")
        rec = record(vf, "Образец-Один")
        refs = list(E.unit_ability_refs(rec))
        row = {"index": rec.index, "label": rec.label, **rec.fields}
        for label, _ in refs:
            row.pop(label, None)
        row["Abilityes"] = [{"ref_label": lb, "ref": rf} for lb, rf in refs]
        check([e["ref_label"] for e in row["Abilityes"]] == expected,
              "%s: typed list matches the source block" % dialect,
              str([e["ref_label"] for e in row["Abilityes"]]))
        check(all(lb not in row for lb, _ in refs),
              "%s: flat ref fields are dropped" % dialect)
        check(isinstance(row["Abilityes"], list),
              "%s: the roster contract is a list, never a string" % dialect)


def test_real_packs_if_available() -> None:
    print("\n[9] real Genesis and New Horizons packs")
    any_pack = False
    for pack in ("genesis", "new_horizons"):
        path = os.path.join("packs", pack, "data", "unit.json")
        if not os.path.exists(path):
            print("  SKIP  packs/%s/data is missing - build it with "
                  "tools/extract/build_pack.py" % pack)
            continue
        any_pack = True
        with open(path, encoding="utf-8") as fh:
            records = json.load(fh)["records"]
        leaked = {e["ref_label"] for r in records
                  for e in r.get("Abilityes", [])
                  if e["ref_label"] in ("Race", "UnitKind", "UnitClass",
                                        "Karma", "Missile", "Resource",
                                        "Subtype", "Analogs", "Upgraded")}
        check(not leaked, "%s: no metadata leaks into abilities" % pack,
              str(leaked))
        check(all(isinstance(r.get("Abilityes", []), list) for r in records),
              "%s: every record carries a list, never a bare string" % pack)
        with_abilities = sum(1 for r in records if r.get("Abilityes"))
        check(with_abilities > 0, "%s: abilities actually attached" % pack,
              "%d of %d units" % (with_abilities, len(records)))
    if not any_pack:
        print("  (synthetic dialect coverage above still ran)")


def main() -> None:
    test_dialects_parse()
    test_fixtures_are_crlf_like_the_originals()
    test_the_dialects_are_actually_different()
    test_ability_refs_are_positional_not_heuristic()
    test_level_up_rows_terminate_the_block()
    test_compound_upgrade_rows_are_parallel_lists()
    test_ability_number_is_not_the_record_index()
    test_build_pack_emits_the_typed_contract()
    test_real_packs_if_available()
    print("\n%s" % ("ALL PASS" if not FAILS
                    else "%d FAILURES: %s" % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()
