class_name Battlefield
extends RefCounted

## The hex grid.
##
## ORIENTATION IS A RENDERING CONCERN, NOT A RULES ONE. The field is hexagonal;
## whether the hexes are pointy-top or flat-top changes only how axial
## coordinates project to pixels. Adjacency, distance and range are identical
## either way under axial coordinates, so core/ never needs to know and game/
## decides at draw time. That is why nothing here mentions orientation.
##
## Axial coordinates (q, r), with the implied cube coordinate s = -q - r.
## Hexes are packed into a single int key so they can be Dictionary keys
## cheaply; Vector2i would work too but keys must hash identically in both
## implementations for fixtures to line up.
##
## DIMENSIONS ARE CONFIGURABLE BY DESIGN. The original's field is one size, but
## mods will want another, so width and height are parameters everywhere and
## nothing hardcodes a bound. No variable-size behaviour is implemented — this
## is allowance, not a feature.

## Axial neighbour offsets in a FIXED order. The order is part of the contract:
## anything that iterates neighbours and rolls dice must do so identically in
## both implementations, or replays diverge.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

const IMPASSABLE := 0   ## bf_object MoveCost 0


class Tile extends RefCounted:
	var hex: Vector2i = Vector2i.ZERO
	var bf_object: int = 1     ## index into bf_object.var
	var move_cost: int = 1     ## 0 = impassable
	var stam_cost: int = 0
	var occupant: Variant = null

	func passable() -> bool:
		return move_cost != IMPASSABLE

	func is_free() -> bool:
		return passable() and occupant == null


var width: int = 0
var height: int = 0
var tiles: Dictionary = {}     ## Vector2i -> Tile


func _init(p_width: int = 1, p_height: int = 1) -> void:
	width = maxi(1, p_width)
	height = maxi(1, p_height)
	for row in height:
		for col in width:
			var h := offset_to_axial(col, row)
			var t := Tile.new()
			t.hex = h
			tiles[h] = t


# -- coordinates -------------------------------------------------------------

static func offset_to_axial(col: int, row: int) -> Vector2i:
	## Rectangular storage -> axial. Odd rows shift, which is what makes a
	## rectangular array of hexes tile correctly.
	return Vector2i(col - (row - (row & 1)) / 2, row)


static func axial_to_offset(h: Vector2i) -> Vector2i:
	return Vector2i(h.x + (h.y - (h.y & 1)) / 2, h.y)


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2


static func neighbour_of(h: Vector2i, i: int) -> Vector2i:
	return h + NEIGHBOURS[i]


# -- queries -----------------------------------------------------------------

func contains(h: Vector2i) -> bool:
	return tiles.has(h)


func tile(h: Vector2i) -> Tile:
	return tiles.get(h)


## In-bounds neighbours, in the fixed NEIGHBOURS order.
func neighbours(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in NEIGHBOURS:
		var n: Vector2i = h + d
		if tiles.has(n):
			out.append(n)
	return out


## Backs Круговая атака ("all enemies on adjacent tiles") and the adjacency
## triggers in the morale rules.
func adjacent_occupants(h: Vector2i) -> Array:
	var out: Array = []
	for n in neighbours(h):
		var occ: Variant = (tiles[n] as Tile).occupant
		if occ != null:
			out.append(occ)
	return out


## Every in-bounds hex at distance <= radius. Shooting range and aura radius are
## the same metric, so both use this.
func within(centre: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		var lo: int = maxi(-radius, -dq - radius)
		var hi: int = mini(radius, -dq + radius)
		for dr in range(lo, hi + 1):
			var h := Vector2i(centre.x + dq, centre.y + dr)
			if tiles.has(h):
				out.append(h)
	return out


func ring(centre: Vector2i, radius: int) -> Array[Vector2i]:
	if radius <= 0:
		var single: Array[Vector2i] = []
		if tiles.has(centre):
			single.append(centre)
		return single
	var out: Array[Vector2i] = []
	for h in within(centre, radius):
		if distance(centre, h) == radius:
			out.append(h)
	return out


## Hexes from a to b inclusive. Ties are nudged by a fixed epsilon so the result
## is deterministic — a line that flips between runs would desynchronise
## anything that walks it.
func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n: int = distance(a, b)
	var out: Array[Vector2i] = []
	if n == 0:
		out.append(a)
		return out
	for i in n + 1:
		var t: float = float(i) / float(n)
		var q: float = float(a.x) + float(b.x - a.x) * t + 1e-6
		var r: float = float(a.y) + float(b.y - a.y) * t + 1e-6
		out.append(_round_axial(q, r))
	return out


static func _round_axial(q: float, r: float) -> Vector2i:
	var s: float = -q - r
	var rq: int = int(round(q))
	var rr: int = int(round(r))
	var rs: int = int(round(s))
	var dq: float = absf(float(rq) - q)
	var dr: float = absf(float(rr) - r)
	var ds: float = absf(float(rs) - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(rq, rr)


# -- pathfinding -------------------------------------------------------------

const _BIG := 1 << 30

## Cheapest path by MoveCost, or an empty array when unreachable.
##
## Returns the hexes AFTER `start`, so size() is the number of steps recorded in
## trace-visible `steps_this_round`. Charge and attack stamina use command-entry
## coordinates and live capacity respectively.
##
## Ties break on the fixed NEIGHBOURS order via an insertion counter, not on
## sort accident: equal-cost routes must resolve the same way every run.
func path(start: Vector2i, goal: Vector2i, ignore_occupants: bool = false,
		max_cost: int = -1) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not tiles.has(start) or not tiles.has(goal) or start == goal:
		return empty

	var frontier: Array = [[0, 0, start]]
	var came_from: Dictionary = {start: null}
	var cost_so_far: Dictionary = {start: 0}
	var counter: int = 0
	var found := false

	while not frontier.is_empty():
		frontier.sort_custom(func(a, b):
			return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		var top: Array = frontier.pop_front()
		var cost: int = top[0]
		var current: Vector2i = top[2]
		if current == goal:
			found = true
			break
		if cost > int(cost_so_far.get(current, _BIG)):
			continue
		for nxt in neighbours(current):
			var t: Tile = tiles[nxt]
			if not t.passable():
				continue
			if not ignore_occupants and t.occupant != null and nxt != goal:
				continue
			var new_cost: int = cost + t.move_cost
			if max_cost >= 0 and new_cost > max_cost:
				continue
			if new_cost < int(cost_so_far.get(nxt, _BIG)):
				cost_so_far[nxt] = new_cost
				came_from[nxt] = current
				counter += 1
				frontier.append([new_cost, counter, nxt])

	if not found and not came_from.has(goal):
		return empty
	var out: Array[Vector2i] = []
	var node: Vector2i = goal
	while node != start:
		out.append(node)
		node = came_from[node]
	out.reverse()
	return out


## hex -> cost, for everything reachable within `budget` move points.
func reachable(start: Vector2i, budget: int, ignore_occupants: bool = false) -> Dictionary:
	var frontier: Array = [[0, 0, start]]
	var cost_so_far: Dictionary = {start: 0}
	var counter: int = 0
	while not frontier.is_empty():
		frontier.sort_custom(func(a, b):
			return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		var top: Array = frontier.pop_front()
		var cost: int = top[0]
		var current: Vector2i = top[2]
		if cost > int(cost_so_far.get(current, _BIG)):
			continue
		for nxt in neighbours(current):
			var t: Tile = tiles[nxt]
			if not t.passable():
				continue
			if not ignore_occupants and t.occupant != null:
				continue
			var new_cost: int = cost + t.move_cost
			if new_cost > budget:
				continue
			if new_cost < int(cost_so_far.get(nxt, _BIG)):
				cost_so_far[nxt] = new_cost
				counter += 1
				frontier.append([new_cost, counter, nxt])
	return cost_so_far


# -- occupancy ---------------------------------------------------------------

func place(unit: Variant, h: Vector2i) -> bool:
	var t: Tile = tiles.get(h)
	if t == null or not t.is_free():
		return false
	t.occupant = unit
	return true


func remove_occupant(h: Vector2i) -> void:
	var t: Tile = tiles.get(h)
	if t != null:
		t.occupant = null


func find_unit(unit: Variant) -> Vector2i:
	for h in tiles:
		if (tiles[h] as Tile).occupant == unit:
			return h
	return Vector2i(_BIG, _BIG)


func has_unit(unit: Variant) -> bool:
	return find_unit(unit) != Vector2i(_BIG, _BIG)
