"""Profile-qualified Genesis tactical death-replacement resolution (CX-016)."""

from __future__ import annotations

import copy
from dataclasses import dataclass

from modifier import Hook, Modifier

PROFILE_GENESIS = "genesis"
COMPATIBILITY_GENESIS = "genesis"
COMPATIBILITY_NEW_HORIZONS = "new_horizons"
COMPATIBILITY_UNSPECIFIED = "unspecified"
COMPATIBILITIES = {
    COMPATIBILITY_GENESIS,
    COMPATIBILITY_NEW_HORIZONS,
    COMPATIBILITY_UNSPECIFIED,
}
STRICT = "strict"
PERMISSIVE = "permissive"
MODES = {STRICT, PERMISSIVE}
# RECOVERED Genesis-only marker and fixed source-record edge.  This module is
# selected only by the composition root; no NH meaning is asserted.
GENESIS_REPLACEMENT_MARKER = 0x5B
GENESIS_SOURCE_BY_TIER = {1: 21, 2: 37, 3: 56, 4: 65}


class DeathReplacementConfigurationError(ValueError):
    def __init__(self, diagnostics: list[dict]):
        self.diagnostics = copy.deepcopy(diagnostics)
        super().__init__("death replacement composition failed: " + "; ".join(
            str(item.get("message", "configuration error")) for item in diagnostics
            if item.get("severity") == "error"))


def _diagnostic(code: str, message: str, **details) -> dict:
    return {"code": code, "severity": "error", "message": message, **details}


def _runtime_has_genesis_marker(unit) -> bool:
    return any(int(modifier.ability) == GENESIS_REPLACEMENT_MARKER
               for status in unit.statuses for modifier in status.modifiers)


def _build_modifiers(definition: dict) -> dict:
    out = copy.deepcopy(definition)
    built = []
    for raw in out.get("modifiers", ()):
        if isinstance(raw, Modifier):
            built.append(copy.deepcopy(raw))
        else:
            built.append(Modifier(
                ability=int(raw.get("ability", 0)),
                handler=raw["handler"],
                hook=getattr(Hook, raw.get("hook", "STAT_PASSIVE")),
                power=int(raw.get("power", 0)),
                params=copy.deepcopy(raw.get("params", {})),
                source=raw.get("source", raw["handler"])))
    out["modifiers"] = built
    return out


@dataclass(frozen=True)
class NormalizedCompatibility:
    identity: str
    source: str
    override: bool


class GenesisDeathReplacementResolver:
    """Validate and resolve the strict Genesis source-record mapping.

    Generic lifecycle code receives only ``decision_for(unit)`` outcomes.  It
    never sees the recovered marker, source records, profile, pack, or override.
    """

    def __init__(self, profile: str, provider=None, *,
                 compatibility_override: str = "", mode: str = STRICT):
        self.profile = str(profile)
        self.provider = provider
        self.mode = str(mode)
        if self.mode not in MODES:
            raise ValueError("unknown death replacement load mode %r" % self.mode)
        self.diagnostics: list[dict] = []
        self._resolved: dict[int, dict] = {}
        self.compatibility = self._normalize_compatibility(compatibility_override)
        if self.profile == PROFILE_GENESIS:
            self._validate_genesis_configuration()
        if self.mode == STRICT:
            errors = [item for item in self.diagnostics
                      if item.get("severity") == "error"]
            if errors:
                raise DeathReplacementConfigurationError(self.diagnostics)

    @staticmethod
    def source_record_for_tier(tier: int) -> int:
        try:
            return GENESIS_SOURCE_BY_TIER[int(tier)]
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(
                "Genesis death replacement requires original tier 1..4") from exc

    def _normalize_compatibility(self, override: str) -> NormalizedCompatibility:
        override = str(override or "").strip().lower()
        if override:
            if override != COMPATIBILITY_GENESIS:
                raise ValueError("unknown content compatibility override %r" % override)
            self.diagnostics.append({
                "code": "explicit_compatibility_override",
                "severity": "info",
                "message": "content compatibility explicitly overridden to genesis",
                "compatibility": COMPATIBILITY_GENESIS,
                "source": "load_override",
            })
            return NormalizedCompatibility(
                COMPATIBILITY_GENESIS, "load_override", True)
        compatibility_fn = getattr(self.provider, "content_compatibility", None)
        raw = compatibility_fn() if callable(compatibility_fn) else {}
        if not isinstance(raw, dict):
            raw = {}
        identity = str(raw.get("identity", COMPATIBILITY_UNSPECIFIED)).strip().lower()
        source = str(raw.get("source", "unspecified"))
        if identity not in COMPATIBILITIES:
            self.diagnostics.append(_diagnostic(
                "malformed_compatibility_contract",
                "content compatibility identity %r is not supported" % identity,
                compatibility=identity, source=source))
            identity = COMPATIBILITY_UNSPECIFIED
        return NormalizedCompatibility(identity, source, False)

    def normalized_state(self) -> dict:
        return {
            "profile": self.profile,
            "mode": self.mode,
            "content_compatibility": self.compatibility.identity,
            "compatibility_source": self.compatibility.source,
            "compatibility_override": self.compatibility.override,
            "diagnostics": copy.deepcopy(self.diagnostics),
        }

    def _validate_genesis_configuration(self) -> None:
        if self.compatibility.identity != COMPATIBILITY_GENESIS:
            self.diagnostics.append(_diagnostic(
                "genesis_content_compatibility_mismatch",
                "Genesis rules require Genesis-compatible content; got %s"
                % self.compatibility.identity,
                compatibility=self.compatibility.identity,
                compatibility_source=self.compatibility.source))
            return
        resolve_source = getattr(self.provider, "resolve_source_definition", None)
        if not callable(resolve_source):
            self.diagnostics.append(_diagnostic(
                "missing_source_definition_provider",
                "Genesis-compatible content provider cannot resolve qualified source records"))
            return
        for tier, source_record in GENESIS_SOURCE_BY_TIER.items():
            try:
                resolved = resolve_source("unit", source_record)
            except Exception as exc:  # durable provider/load diagnostic
                resolved = None
                detail = str(exc)
            else:
                detail = ""
            if not isinstance(resolved, dict):
                self.diagnostics.append(_diagnostic(
                    "unresolved_genesis_replacement_target",
                    "Genesis replacement source record %d (tier %d) did not resolve"
                    % (source_record, tier), tier=tier,
                    source_record=source_record, detail=detail))
                continue
            canonical_id = resolved.get("content_id")
            definition = resolved.get("definition")
            if not isinstance(canonical_id, str) or not canonical_id or not isinstance(definition, dict):
                self.diagnostics.append(_diagnostic(
                    "malformed_genesis_replacement_target",
                    "Genesis replacement source record %d (tier %d) resolved malformed data"
                    % (source_record, tier), tier=tier, source_record=source_record))
                continue
            if not isinstance(definition.get("name"), str) or not definition["name"]:
                self.diagnostics.append(_diagnostic(
                    "malformed_genesis_replacement_target",
                    "Genesis replacement source record %d (tier %d) has no display name"
                    % (source_record, tier), tier=tier,
                    source_record=source_record))
                continue
            try:
                definition = _build_modifiers(definition)
            except (KeyError, TypeError, ValueError, AttributeError) as exc:
                self.diagnostics.append(_diagnostic(
                    "malformed_genesis_replacement_target",
                    "Genesis replacement source record %d (tier %d) is malformed: %s"
                    % (source_record, tier, exc), tier=tier,
                    source_record=source_record))
                continue
            definition["content_id"] = canonical_id
            definition["definition_id"] = source_record
            self._resolved[tier] = definition

    def decision_for(self, unit) -> dict:
        if self.profile != PROFILE_GENESIS or not _runtime_has_genesis_marker(unit):
            return {"status": "not_applicable"}
        try:
            tier = int(unit.original_definition.get("tier", unit.tier))
            source_record = self.source_record_for_tier(tier)
        except ValueError as exc:
            return {"status": "unresolved", "error": str(exc)}
        definition = self._resolved.get(tier)
        if definition is None:
            return {
                "status": "unresolved",
                "error": "Genesis replacement source record %d for tier %d is unresolved"
                         % (source_record, tier),
                "tier": tier,
                "source_record": source_record,
            }
        return {
            "status": "resolved",
            "definition": copy.deepcopy(definition),
            "definition_id": source_record,
            "tier": tier,
        }
