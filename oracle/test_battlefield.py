"""
test_battlefield.py — hex grid, adjacency, range, pathfinding.

Two properties matter more than the rest:

  * DETERMINISM. Pathfinding ties are broken by insertion order, not by heap
    accident, so equal-cost routes resolve identically every run. A path that
    flips between runs desynchronises path traces, remaining capacity and the
    command-entry tile used by later attacks.
  * BOUNDS. Width and height are parameters. Nothing may assume the original's
    field size, because mods will change it.

Run: python3 test_battlefield.py
"""

from __future__ import annotations

import os

import sys

from battlefield import (
    Battlefield, Hex, NEIGHBOURS, axial_to_offset, offset_to_axial,
)

FAILS: list[str] = []


def check(ok: bool, what: str, detail: str = "") -> None:
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", what,
                          ("  — " + detail) if detail else ""))
    if not ok:
        FAILS.append(what)
        # Under pytest, raise: check() otherwise only RECORDS a failure, so
        # `pytest oracle/` would report green while assertions fail. The
        # standalone runner still collects every failure before exiting.
        if "PYTEST_CURRENT_TEST" in os.environ:
            raise AssertionError(what)


def test_coordinates() -> None:
    print("\n[1] axial coordinates")
    h = Hex(0, 0)
    check(len(h.neighbours()) == 6, "six neighbours")
    check(all(h.distance(n) == 1 for n in h.neighbours()), "all at distance 1")
    check(h.distance(Hex(3, 0)) == 3 and h.distance(Hex(0, 3)) == 3
          and h.distance(Hex(3, -3)) == 3, "distance along all three axes")
    check(Hex(2, -1).s == -1, "cube s is derived, not stored")
    ok = all(axial_to_offset(offset_to_axial(c, r)) == (c, r)
             for c in range(8) for r in range(8))
    check(ok, "offset <-> axial round-trips")


def test_dimensions() -> None:
    print("\n[2] dimensions are parameters, not constants")
    for w, h in ((1, 1), (7, 7), (3, 11), (20, 4)):
        bf = Battlefield(w, h)
        check(len(bf.tiles) == w * h, "%dx%d holds %d tiles" % (w, h, w * h),
              "got %d" % len(bf.tiles))
    try:
        Battlefield(0, 5)
        check(False, "a zero dimension is rejected")
    except ValueError:
        check(True, "a zero dimension is rejected")
    bf = Battlefield(3, 3)
    check(not bf.contains(Hex(99, 99)), "out-of-bounds hexes are simply absent")
    check(bf.tile(Hex(99, 99)) is None, "and tile() returns None rather than raising")


def test_adjacency() -> None:
    print("\n[3] adjacency")
    bf = Battlefield(7, 7)
    centre = offset_to_axial(3, 3)
    check(len(bf.neighbours(centre)) == 6, "an interior hex has six neighbours")
    corner = offset_to_axial(0, 0)
    n = len(bf.neighbours(corner))
    check(n < 6, "a corner has fewer — out-of-bounds are filtered, not wrapped",
          "%d" % n)
    order = [(x.q - centre.q, x.r - centre.r) for x in centre.neighbours()]
    check(tuple(order) == NEIGHBOURS,
          "neighbour ORDER is fixed — anything that iterates and rolls must match")


def test_range() -> None:
    print("\n[4] range queries — shooting range and aura radius are the same metric")
    bf = Battlefield(11, 11)
    c = offset_to_axial(5, 5)
    check(len(bf.within(c, 0)) == 1, "radius 0 is the hex itself")
    check(len(bf.within(c, 1)) == 7, "radius 1 is 7 hexes", "%d" % len(bf.within(c, 1)))
    check(len(bf.within(c, 2)) == 19, "radius 2 is 19 hexes", "%d" % len(bf.within(c, 2)))
    check(len(bf.ring(c, 2)) == 12, "ring 2 is 12 hexes", "%d" % len(bf.ring(c, 2)))
    check(all(c.distance(h) <= 3 for h in bf.within(c, 3)), "within() respects the radius")
    small = Battlefield(3, 3)
    e = offset_to_axial(0, 0)
    check(len(small.within(e, 5)) == 9, "a radius larger than the field clips to it",
          "%d" % len(small.within(e, 5)))


def test_line() -> None:
    print("\n[5] lines")
    bf = Battlefield(9, 9)
    a, b = Hex(0, 0), Hex(4, 0)
    ln = bf.line(a, b)
    check(ln[0] == a and ln[-1] == b, "endpoints included")
    check(len(ln) == a.distance(b) + 1, "length is distance + 1", "%d" % len(ln))
    check(bf.line(a, a) == [a], "a zero-length line is the hex itself")
    check(bf.line(a, b) == bf.line(a, b), "and it is stable across calls")


def test_pathfinding() -> None:
    print("\n[6] pathfinding")
    bf = Battlefield(7, 7)
    start = offset_to_axial(0, 0)
    goal = offset_to_axial(4, 0)
    p = bf.path(start, goal)
    check(p is not None and len(p) == start.distance(goal),
          "an open path costs one step per hex of distance",
          "%d steps" % (len(p) if p else -1))
    check(p[-1] == goal, "and ends on the goal")
    check(bf.path(start, start) == [], "a path to self is zero steps")

    # impassable terrain: bf_object MoveCost 0
    for row in range(7):
        if row != 6:
            h = offset_to_axial(2, row)
            bf.tile(h).move_cost = 0
    p = bf.path(offset_to_axial(0, 0), offset_to_axial(4, 0))
    check(p is not None and len(p) > start.distance(goal),
          "a wall forces a detour rather than a straight line",
          "%d steps" % (len(p) if p else -1))

    wall = Battlefield(5, 5)
    for row in range(5):
        wall.tile(offset_to_axial(2, row)).move_cost = 0
    check(wall.path(offset_to_axial(0, 0), offset_to_axial(4, 4)) is None,
          "a full wall makes the goal unreachable, returning None not an exception")


def test_path_determinism() -> None:
    print("\n[7] determinism — the property replays depend on")
    bf = Battlefield(9, 9)
    a, b = offset_to_axial(0, 0), offset_to_axial(6, 4)
    first = bf.path(a, b)
    check(all(bf.path(a, b) == first for _ in range(20)),
          "20 identical calls give an identical path")
    fresh = Battlefield(9, 9)
    check(fresh.path(a, b) == first,
          "and a freshly built field agrees — no dependence on insertion history")


def test_occupancy() -> None:
    print("\n[8] occupancy")
    bf = Battlefield(5, 5)
    a, b = object(), object()
    h = offset_to_axial(2, 2)
    check(bf.place(a, h), "placing on a free hex succeeds")
    check(not bf.place(b, h), "placing on an occupied hex fails")
    check(bf.find(a) == h, "find() locates the unit")
    check(bf.adjacent_occupants(bf.neighbours(h)[0]) == [a],
          "adjacent_occupants backs Круговая атака and the morale triggers")
    bf.remove(h)
    check(bf.find(a) is None and bf.place(b, h), "removal frees the hex")

    blocked = Battlefield(5, 1)
    blocked.place(object(), offset_to_axial(2, 0))
    p = blocked.path(offset_to_axial(0, 0), offset_to_axial(4, 0))
    check(p is None, "a unit blocks the only corridor")
    p = blocked.path(offset_to_axial(0, 0), offset_to_axial(4, 0), ignore_occupants=True)
    check(p is not None, "ignore_occupants lets the AI reason about a clear field")


def test_reachable() -> None:
    print("\n[9] reachable — what a movement budget actually buys")
    bf = Battlefield(9, 9)
    c = offset_to_axial(4, 4)
    r = bf.reachable(c, 2)
    check(r[c] == 0, "the origin costs nothing")
    check(len(r) == 19, "budget 2 over flat ground reaches 19 hexes", "%d" % len(r))
    for h in bf.neighbours(c):
        bf.tile(h).move_cost = 2
    r = bf.reachable(c, 2)
    check(len(r) == 7, "rough terrain shrinks it to the first ring", "%d" % len(r))


if __name__ == "__main__":
    test_coordinates()
    test_dimensions()
    test_adjacency()
    test_range()
    test_line()
    test_pathfinding()
    test_path_determinism()
    test_occupancy()
    test_reachable()
    print("\n%s" % ("ALL PASS" if not FAILS else "%d FAILURES: %s"
                    % (len(FAILS), ", ".join(FAILS))))
    sys.exit(1 if FAILS else 0)
