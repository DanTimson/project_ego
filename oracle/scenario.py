"""
scenario.py — deterministic battles as data.

A scenario is a seed, a battlefield, two sides, and a command list. Running it
produces a LOG: an ordered list of plain strings. That log is the artifact —
committed, diffed, and compared between the Python oracle and the GDScript port.

WHY A LOG AND NOT A FINAL STATE. A final state can match while the route to it
differs: two implementations that disagree about pathfinding tie-breaks, or
about when stamina is charged, can still land the same unit on the same hex with
the same HP. The log catches the divergence at the step where it happens, which
is the difference between a five-minute fix and an afternoon of bisection.

THIS IS THE INTEGRATION POINT. Everything the project has built meets here:
battlefield pathfinding feeds steps_this_round, which sets the stamina charge,
which feeds StaminaMod, which scales the attack, which the RNG rolls, which the
defence reduces. A scenario that reproduces exactly is evidence the whole chain
agrees — far stronger than any subsystem test.

Command set, deliberately small:

    move        <unit> to <col,row>       explicit movement
    attack      <unit> -> <target>        AUTO-PATHS into contact first
    shoot       <unit> -> <target>        range-checked, no movement
    rest        <unit>
    extra_turn  <unit>                    what a spell would grant
    end_phase                             hand control to the other side
"""

from __future__ import annotations

import json

import battlefield as bfmod
import combat
import counterattack as ca
import turn
from battlefield import Battlefield
from combat import AttackKind, Combatant, Rng


class Scenario:
    def __init__(self, spec: dict):
        self.spec = spec
        self.name = spec.get("name", "unnamed")
        self.seed = int(spec.get("seed", 0))
        self.log: list[str] = []
        self.rng = Rng(self.seed)
        self.field = self._build_field(spec.get("battlefield", {}))
        self.units: dict[str, Combatant] = {}
        self.sides = self._build_sides(spec.get("sides", []))
        self.state = turn.BattleState(sides=self.sides)

    # -- construction -------------------------------------------------------

    def _build_field(self, spec: dict) -> Battlefield:
        field = Battlefield(int(spec.get("width", 7)), int(spec.get("height", 7)))
        for t in spec.get("tiles", []):
            h = bfmod.offset_to_axial(int(t["col"]), int(t["row"]))
            tile = field.tile(h)
            if tile is None:
                continue
            if "bf_object" in t:
                tile.bf_object = int(t["bf_object"])
            if "move_cost" in t:
                tile.move_cost = int(t["move_cost"])
            if "stam_cost" in t:
                tile.stam_cost = int(t["stam_cost"])
        return field

    def _build_sides(self, specs: list) -> list:
        sides = []
        for s in specs:
            side = turn.Side(
                id=int(s["id"]), name=s.get("name", str(s["id"])),
                leader_initiative=int(s.get("leader_initiative", 0)),
                is_attacker=bool(s.get("is_attacker", False)),
            )
            for u in s.get("units", []):
                unit = Combatant(name=u["name"])
                for key, value in u.items():
                    if key in ("name", "at", "flags", "subtypes"):
                        continue
                    setattr(unit, key, value)
                unit.flags = set(u.get("flags", []))
                unit.subtypes = set(u.get("subtypes", []))
                unit.life_base = u.get("life_base", unit.life)
                unit.stamina_base = u.get("stamina_base", unit.stamina)
                unit.morale_base = u.get("morale_base", unit.morale)
                col, row = u["at"]
                if not self.field.place(unit, bfmod.offset_to_axial(col, row)):
                    raise ValueError("cannot place %s at %s" % (unit.name, u["at"]))
                if unit.name in self.units:
                    raise ValueError("duplicate unit name %r" % unit.name)
                self.units[unit.name] = unit
                side.units.append(unit)
            sides.append(side)
        return sides

    # -- helpers ------------------------------------------------------------

    def _at(self, unit: Combatant) -> str:
        h = self.field.find(unit)
        if h is None:
            return "-"
        col, row = bfmod.axial_to_offset(h)
        return "%d,%d" % (col, row)

    def emit(self, line: str) -> None:
        self.log.append(line)

    def _side_of(self, unit: Combatant):
        for s in self.sides:
            if unit in s.units:
                return s
        return None

    # -- commands -----------------------------------------------------------

    def cmd_move(self, unit: Combatant, col: int, row: int) -> None:
        start = self.field.find(unit)
        goal = bfmod.offset_to_axial(col, row)
        path = self.field.path(start, goal, max_cost=unit.movement_remaining)
        if not path:
            self.emit("%s cannot reach %d,%d" % (unit.name, col, row))
            return
        cost = sum(self.field.tile(h).move_cost for h in path)
        if cost > unit.movement_remaining:
            self.emit("%s lacks movement for %d,%d" % (unit.name, col, row))
            return
        stam = sum(self.field.tile(h).stam_cost for h in path)
        self.field.remove(start)
        self.field.place(unit, goal)
        turn.spend_move(unit, cost, stamina_cost=stam)
        self.emit("%s moves to %s (%d steps, %d total this round)"
                  % (unit.name, self._at(unit), len(path), unit.steps_this_round))

    def _approach(self, unit: Combatant, target: Combatant) -> bool:
        """Attack commands carry an implicit move: issuing an attack against a
        reachable target auto-paths the unit into contact, drawing from the same
        action-point pool."""
        here = self.field.find(unit)
        there = self.field.find(target)
        if here.distance(there) == 1:
            return True
        best = None
        for h in self.field.neighbours(there):
            if not self.field.tile(h).free:
                continue
            p = self.field.path(here, h, max_cost=unit.movement_remaining)
            if p is None:
                continue
            cost = sum(self.field.tile(x).move_cost for x in p)
            if cost > unit.movement_remaining:
                continue
            if best is None or cost < best[0]:
                best = (cost, h, p)
        if best is None:
            return False
        cost, dest, path = best
        stam = sum(self.field.tile(x).stam_cost for x in path)
        self.field.remove(here)
        self.field.place(unit, dest)
        turn.spend_move(unit, cost, stamina_cost=stam)
        self.emit("%s closes to %s (%d steps)" % (unit.name, self._at(unit), len(path)))
        return True

    def _fell(self, unit: Combatant) -> None:
        h = self.field.find(unit)
        if h is not None:
            self.field.remove(h)
        self.emit("%s falls" % unit.name)

    def _strike(self, unit: Combatant, target: Combatant, kind: AttackKind,
                action=None) -> None:
        """One exchange: the attack and any retaliation, in the right order.

        Melee is answered; a shot is not. `Первый удар` moves the retaliation
        ahead of the blow that caused it, so a defender can kill an attacker
        before the attack lands.
        """
        ex = ca.resolve(unit, target, self.rng, kind, action)
        turn.spend_attack(unit)

        for what, damage in ex.order:
            if what == "attack":
                self.emit("%s hits %s for %d (%s at %d/%d, stamina %d)"
                          % (unit.name, target.name, damage, target.name,
                             max(0, target.life), target.life_base, unit.stamina))
            else:
                self.emit("%s counters%s for %d (%s at %d/%d)"
                          % (target.name,
                             " first" if ex.counter_first else "",
                             damage, unit.name,
                             max(0, unit.life), unit.life_base))
        if ex.defender_died:
            self._fell(target)
        if ex.attacker_died:
            self._fell(unit)
        if not ex.countered and ex.reason not in (ca.NoCounter.RANGED,
                                                  ca.NoCounter.DEAD):
            self.emit("  (%s does not counter: %s)"
                      % (target.name, ex.reason.value))

    def cmd_attack(self, unit: Combatant, target: Combatant) -> None:
        if not target.alive:
            self.emit("%s has no target: %s is down" % (unit.name, target.name))
            return
        if unit.action_spent:
            self.emit("%s has already acted" % unit.name)
            return
        if not self._approach(unit, target):
            self.emit("%s cannot reach %s" % (unit.name, target.name))
            return
        self._strike(unit, target, AttackKind.MELEE)

    def cmd_shoot(self, unit: Combatant, target: Combatant) -> None:
        if not target.alive:
            self.emit("%s has no target: %s is down" % (unit.name, target.name))
            return
        if unit.action_spent:
            self.emit("%s has already acted" % unit.name)
            return
        if unit.ammo <= 0:
            self.emit("%s is out of ammunition" % unit.name)
            return
        dist = self.field.find(unit).distance(self.field.find(target))
        if dist > unit.shooting_range:
            self.emit("%s is out of range of %s (%d > %d)"
                      % (target.name, unit.name, dist, unit.shooting_range))
            return
        unit.ammo -= 1
        self._strike(unit, target, AttackKind.RANGED)

    def cmd_rest(self, unit: Combatant) -> None:
        turn.rest(unit)
        self.emit("%s rests (stamina %d)" % (unit.name, unit.stamina))

    def cmd_extra_turn(self, unit: Combatant, spec: dict) -> None:
        granted, _ = turn.grant_extra_turn(
            unit, source=spec.get("source", ""),
            once_per_round=bool(spec.get("once_per_round", False)),
            fire_round_start=bool(spec.get("fire_round_start", False)),
        )
        self.emit("%s %s an extra turn (movement %d, steps %d)"
                  % (unit.name, "receives" if granted else "is refused",
                     unit.movement_remaining, unit.steps_this_round))

    def cmd_end_phase(self) -> None:
        new_round = turn.end_phase(self.state)
        if new_round:
            self.emit("-- round %d, side %d first --"
                      % (self.state.round_number, self.state.active_side))
        else:
            self.emit("-- side %d --" % self.state.active_side)

    # -- run ----------------------------------------------------------------

    def run(self) -> dict:
        turn.begin_battle(self.state)
        self.emit("== %s (seed %d) ==" % (self.name, self.seed))
        self.emit("-- round %d, side %d first --"
                  % (self.state.round_number, self.state.active_side))

        for c in self.spec.get("commands", []):
            op = c["op"]
            if op == "end_phase":
                self.cmd_end_phase()
                continue
            unit = self.units.get(c.get("unit", ""))
            if unit is None:
                self.emit("unknown unit %r" % c.get("unit"))
                continue
            if not unit.alive:
                self.emit("%s is down and cannot act" % unit.name)
                continue
            side = self._side_of(unit)
            if side is not None and side.id != self.state.active_side:
                self.emit("%s is not in the active side's phase" % unit.name)
                continue
            if op == "move":
                self.cmd_move(unit, int(c["to"][0]), int(c["to"][1]))
            elif op == "attack":
                self.cmd_attack(unit, self.units[c["target"]])
            elif op == "shoot":
                self.cmd_shoot(unit, self.units[c["target"]])
            elif op == "rest":
                self.cmd_rest(unit)
            elif op == "extra_turn":
                self.cmd_extra_turn(unit, c)
            else:
                self.emit("unknown command %r" % op)
            if turn.battle_over(self.state):
                self.emit("== battle over ==")
                break

        return {"name": self.name, "seed": self.seed,
                "log": self.log, "final": self.final_state()}

    def final_state(self) -> dict:
        out = {}
        for name, u in sorted(self.units.items()):
            out[name] = {
                "alive": u.alive, "life": max(0, u.life), "stamina": u.stamina,
                "at": self._at(u), "steps_this_round": u.steps_this_round,
                "action_spent": u.action_spent, "movement_remaining": u.movement_remaining,
            }
        return out


def run_file(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return Scenario(json.load(fh)).run()
