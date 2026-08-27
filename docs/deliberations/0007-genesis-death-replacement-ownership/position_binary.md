# Binary/governance position — DELIB-0007

## Proven scope

The accepted evidence proves the Genesis rules mapping:

- tier 1 -> source record 21
- tier 2 -> source record 37
- tier 3 -> source record 56
- tier 4 -> source record 65

These are Genesis source-record identities. They are not canonical cross-pack IDs,
and the evidence does not establish an NH equivalent.

The project owner confirms that edited `.var`/`.dat` content is a legitimate
modding method. Therefore "Genesis-compatible" cannot require byte-identical stock
content.

## Governance requirements

1. Qualify the mapping by a Genesis-compatible rules/profile contract.
2. Never apply it merely because an arbitrary pack contains records 21/37/56/65.
3. Let a Genesis-compatible mod resolve those source bindings to its own selected
   content definitions.
4. Convert the qualified source binding to a canonical resolved definition before
   generic death-lifecycle code consumes it.
5. Validate required mappings at load time by default.
6. Provide an explicit permissive/unsafe loading mode that preserves diagnostics
   but allows unrelated runtime paths to continue.
7. In permissive mode, reaching an unresolved replacement path must fail explicitly
   at that point; it must not substitute an equal-number record from another
   profile or silently disable the rule.
8. A non-Genesis-compatible profile has no Genesis replacement rule merely because
   numeric IDs collide.

## Preferred architectural shape

The content/profile composition layer owns the raw Genesis source mapping.
Generic death lifecycle consumes either:
- a resolved canonical replacement target;
- an explicit "rule not applicable for this profile";
- or, in permissive mode, a diagnostic unresolved-binding result that becomes a
  runtime error only if invoked.

This decision may reuse a generic content-resolution abstraction from AD-3 if the
engine side finds that appropriate, but it must not depend on action semantics.

## Failure semantics

Strict/default:
- validate on load;
- reject Genesis-compatible configuration with unresolved required mappings.

Explicit permissive/unsafe override:
- load with durable diagnostics;
- unrelated systems continue;
- the first attempted use of the unresolved mapping fails explicitly.

Non-Genesis-compatible profile:
- rule absent/inapplicable, not an error.

## Evidence request

Do not request NH modifier-0x5B evidence here. RS-1 remains deferred until NH
compatibility is actually scheduled.
