"""
battlefield.py — the hex grid.

ORIENTATION IS A RENDERING CONCERN, NOT A RULES ONE. The field is hexagonal;
whether the hexes are pointy-top or flat-top changes only how axial coordinates
project to pixels. Adjacency, distance and range are identical either way under
axial coordinates, so `core/` never needs to know and `game/` decides at draw
time. That is why nothing below mentions orientation.

Axial coordinates (q, r), with the implied cube coordinate s = -q - r:

    neighbours   (+1,0) (+1,-1) (0,-1) (-1,0) (-1,+1) (0,+1)
    distance     (|dq| + |dq+dr| + |dr|) / 2

DIMENSIONS ARE CONFIGURABLE BY DESIGN. The original's field size is fixed, but
mods will want to change it, so width and height are parameters everywhere and
nothing hardcodes a bound. No variable-size behaviour is implemented — this is
allowance, not a feature.

Tiles carry a bf_object index. That table supplies MoveCost (0 = impassable),
StamCost, and modifiers to CounterAttack / Defence / RangedDefence /
ShootingRange, so terrain effects are data and this module only needs the index.
"""

from __future__ import annotations

import heapq
from dataclasses import dataclass, field

# Axial neighbour offsets, in a fixed order. The ORDER is part of the contract:
# anything that iterates neighbours and rolls dice must do so identically in
# both implementations, or replays diverge.
NEIGHBOURS = ((+1, 0), (+1, -1), (0, -1), (-1, 0), (-1, +1), (0, +1))

IMPASSABLE = 0  # bf_object MoveCost 0


@dataclass(frozen=True)
class Hex:
    q: int
    r: int

    @property
    def s(self) -> int:
        return -self.q - self.r

    def neighbour(self, i: int) -> "Hex":
        dq, dr = NEIGHBOURS[i]
        return Hex(self.q + dq, self.r + dr)

    def neighbours(self):
        return [self.neighbour(i) for i in range(6)]

    def distance(self, other: "Hex") -> int:
        dq = self.q - other.q
        dr = self.r - other.r
        return (abs(dq) + abs(dq + dr) + abs(dr)) // 2

    def __repr__(self) -> str:
        return f"Hex({self.q},{self.r})"


def offset_to_axial(col: int, row: int) -> Hex:
    """Rectangular storage -> axial. Odd rows shift, which is what makes a
    rectangular array of hexes tile correctly."""
    return Hex(col - (row - (row & 1)) // 2, row)


def axial_to_offset(h: Hex) -> tuple[int, int]:
    return h.q + (h.r - (h.r & 1)) // 2, h.r


@dataclass
class Tile:
    hex: Hex
    bf_object: int = 1        # index into bf_object.var
    move_cost: int = 1        # 0 = impassable
    stam_cost: int = 0
    occupant: object = None

    @property
    def passable(self) -> bool:
        return self.move_cost != IMPASSABLE

    @property
    def free(self) -> bool:
        return self.passable and self.occupant is None


class Battlefield:
    """A rectangular arrangement of hexes.

    Width and height are parameters, not constants: the original's field is one
    size, but the grid must not assume it. Nothing here indexes past the bounds
    it was given.
    """

    def __init__(self, width: int, height: int):
        if width < 1 or height < 1:
            raise ValueError("battlefield must be at least 1x1")
        self.width = width
        self.height = height
        self.tiles: dict = {}
        for row in range(height):
            for col in range(width):
                h = offset_to_axial(col, row)
                self.tiles[h] = Tile(hex=h)

    # -- queries ------------------------------------------------------------

    def contains(self, h: Hex) -> bool:
        return h in self.tiles

    def tile(self, h: Hex) -> Tile | None:
        return self.tiles.get(h)

    def neighbours(self, h: Hex) -> list:
        """In-bounds neighbours, in the fixed NEIGHBOURS order."""
        return [n for n in h.neighbours() if n in self.tiles]

    def adjacent_occupants(self, h: Hex) -> list:
        """Backs Круговая атака ("all enemies on adjacent tiles") and the
        adjacency triggers in the morale rules."""
        out = []
        for n in self.neighbours(h):
            occ = self.tiles[n].occupant
            if occ is not None:
                out.append(occ)
        return out

    def within(self, centre: Hex, radius: int) -> list:
        """Every in-bounds hex at distance <= radius. Backs shooting range and
        aura radius; both are grid distance, so both use this."""
        out = []
        for dq in range(-radius, radius + 1):
            lo = max(-radius, -dq - radius)
            hi = min(radius, -dq + radius)
            for dr in range(lo, hi + 1):
                h = Hex(centre.q + dq, centre.r + dr)
                if h in self.tiles:
                    out.append(h)
        return out

    def ring(self, centre: Hex, radius: int) -> list:
        if radius <= 0:
            return [centre] if centre in self.tiles else []
        return [h for h in self.within(centre, radius)
                if centre.distance(h) == radius]

    def line(self, a: Hex, b: Hex) -> list:
        """Hexes from a to b inclusive. Ties are broken by a fixed epsilon nudge
        so the result is deterministic — a line that flips between runs would
        desynchronise anything that walks it."""
        n = a.distance(b)
        if n == 0:
            return [a]
        out = []
        for i in range(n + 1):
            t = i / n
            q = a.q + (b.q - a.q) * t + 1e-6
            r = a.r + (b.r - a.r) * t + 1e-6
            out.append(_round_axial(q, r))
        return out

    # -- pathfinding --------------------------------------------------------

    def path(self, start: Hex, goal: Hex, *, ignore_occupants: bool = False,
             max_cost: int | None = None):
        """Cheapest path by MoveCost, or None.

        Returns the hexes AFTER `start`, so len(path) is the number of steps —
        which is what feeds steps_this_round, and therefore Атака с разгона and
        the stamina -2/-1 discriminator.

        Ties are broken by the fixed NEIGHBOURS order, not by heap accident:
        the frontier is keyed on (cost, insertion) so equal-cost paths resolve
        the same way every run.
        """
        if start not in self.tiles or goal not in self.tiles:
            return None
        if start == goal:
            return []

        counter = 0
        frontier = [(0, 0, start)]
        came_from = {start: None}
        cost_so_far = {start: 0}

        while frontier:
            cost, _, current = heapq.heappop(frontier)
            if current == goal:
                break
            if cost > cost_so_far.get(current, 1 << 30):
                continue
            for nxt in self.neighbours(current):
                tile = self.tiles[nxt]
                if not tile.passable:
                    continue
                if not ignore_occupants and tile.occupant is not None and nxt != goal:
                    continue
                new_cost = cost + tile.move_cost
                if max_cost is not None and new_cost > max_cost:
                    continue
                if new_cost < cost_so_far.get(nxt, 1 << 30):
                    cost_so_far[nxt] = new_cost
                    came_from[nxt] = current
                    counter += 1
                    heapq.heappush(frontier, (new_cost, counter, nxt))

        if goal not in came_from:
            return None
        out = []
        node = goal
        while node != start:
            out.append(node)
            node = came_from[node]
        out.reverse()
        return out

    def reachable(self, start: Hex, budget: int, *, ignore_occupants: bool = False) -> dict:
        """hex -> cost, for everything reachable within `budget` move points."""
        counter = 0
        frontier = [(0, 0, start)]
        cost_so_far = {start: 0}
        while frontier:
            cost, _, current = heapq.heappop(frontier)
            if cost > cost_so_far.get(current, 1 << 30):
                continue
            for nxt in self.neighbours(current):
                tile = self.tiles[nxt]
                if not tile.passable:
                    continue
                if not ignore_occupants and tile.occupant is not None:
                    continue
                new_cost = cost + tile.move_cost
                if new_cost > budget:
                    continue
                if new_cost < cost_so_far.get(nxt, 1 << 30):
                    cost_so_far[nxt] = new_cost
                    counter += 1
                    heapq.heappush(frontier, (new_cost, counter, nxt))
        return cost_so_far

    # -- occupancy ----------------------------------------------------------

    def place(self, unit, h: Hex) -> bool:
        tile = self.tiles.get(h)
        if tile is None or not tile.free:
            return False
        tile.occupant = unit
        return True

    def remove(self, h: Hex) -> None:
        tile = self.tiles.get(h)
        if tile is not None:
            tile.occupant = None

    def find(self, unit) -> Hex | None:
        for h, tile in self.tiles.items():
            if tile.occupant is unit:
                return h
        return None


def _round_axial(q: float, r: float) -> Hex:
    s = -q - r
    rq, rr, rs = round(q), round(r), round(s)
    dq, dr, ds = abs(rq - q), abs(rr - r), abs(rs - s)
    if dq > dr and dq > ds:
        rq = -rr - rs
    elif dr > ds:
        rr = -rq - rs
    return Hex(int(rq), int(rr))
