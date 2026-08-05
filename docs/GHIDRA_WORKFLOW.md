# Ghidra workflow

## Target

All addresses in current reverse-engineering documents refer to:

```text
Eador_debug.exe
SHA-256 443329dde09a80be9a71f86cd193c9b2c156cb203ae26a2cf6bea5fface5a1c0
image base 0x00400000
Ghidra language x86:LE:32:default
compiler specification windows
```

See `BINARY_TARGET.md` before opening a new function.

## Naming rule

The address is authoritative. A renamed symbol is a navigation aid only.

When documenting a function, record:

```text
address
original/current Ghidra symbol
proposed working name
confidence
return storage
argument storage
stack cleanup
hidden register inputs
global context inputs
callers examined
data tables and strides
strings or .var records used for semantics
```

Do not impose an ordinary C prototype merely to make the decompiler output look
cleaner. Several important functions receive arguments in `EAX`, `EBX`, `EDI`
or `ESI` while also using stack parameters.

## Standard export packet

Each packet should answer one named question. Include:

1. complete decompilation;
2. complete listing from entry through `RET`;
3. function signature/custom storage window;
4. all instructions that establish hidden registers;
5. direct callers needed to determine argument meaning;
6. directly relevant callees only;
7. XREFs to global arrays, strings and content tables;
8. source binary hash and Ghidra version;
9. current header schema version.

Suggested filename:

```text
inspection_<sequence>_<address>_<question>.txt
```

## Request template

```text
Question:
Primary function address:
Why this function is needed:
Required callers:
Required callees:
Required data references:
Required strings/content records:
Current hypothesis:
Alternative hypothesis:
What would falsify the hypothesis:
```

## Confidence update

Labels are defined in `AGENTS.md`; this section only gives the binary-side
criteria. Record two independent things.

### Axis 1 — how well the rule is established

A result may be marked **PROVEN** when at least one of these holds:

- direct assembly establishes the value flow;
- multiple concrete callers establish the ABI;
- a structure offset is used consistently and passes size/layout checks;
- a numeric ID is tied to a `.var` record and its runtime consumer.

Use **STRONG INFERENCE** when the control flow is clear but one semantic link is
indirect. Use **CANDIDATE** for names selected only for navigation.

### Axis 2 — whether observed behaviour confirms it

Set `confirmed_by_observation` in `docs/EVIDENCE_LEDGER.csv` to **yes** only when
a controlled original-game vector, a published table, or an executed fixture
matches the recovered rule. Otherwise **no**, or **n-a** for claims that are pure
layout and have no observable behaviour of their own.

A controlled vector is deliberately *not* one of the PROVEN criteria above. It
answers the second question, not the first, and collapsing the two hides which
claims have ever been checked against the running game. Static reading has
already produced rules on this project that were internally consistent, resolved
against real tables, and still wrong — a heuristic that mapped unit metadata to
valid upgrade indices passed every cross-reference check until real Genesis data
contradicted it.

When two independent sources agree exactly — for example the binary's low-morale
rule and the published morale table — record both source IDs. Cross-source
agreement is the strongest evidence available short of an executed vector.

## Packet completion checklist

- [ ] source address checked against `FUNCTION_MAP.csv`
- [ ] current claim/open-question ID identified
- [ ] full function included
- [ ] stack cleanup and hidden registers included
- [ ] callers included when semantics depend on them
- [ ] relevant `.var` records included in CP1251-decoded form
- [ ] new claim added to `EVIDENCE_LEDGER.csv`
- [ ] numeric ID dictionary updated
- [ ] compatibility-test row added or updated
- [ ] runtime header updated only when layout evidence changed
- [ ] unresolved alternatives preserved

## Current preferred targets

`BINARY_REQUESTS.md` is the authoritative queue. Do not duplicate closed targets
or reopen a settled item because this workflow file is stale.

Current near-term order:

1. R10 — conditional attack-bonus placement in the multiplier pipeline;
2. R12 and R13 — return-anchor and start-effect lifecycle boundaries;
3. R16 — tactical action-dispatch table;
4. R17 — melee-hit secondary-effect classification;
5. startup-loader schemas and strategic-economy normalization after the current
   tactical queue.

R8, R9 and R11 are closed. Do not request broad re-exports of their primary
functions unless a contradictory fixture identifies a specific missing path.
