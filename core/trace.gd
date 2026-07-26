class_name Trace
extends RefCounted

## A value that can explain itself.
##
## Not a debug convenience: the same object is the tooltip system, the combat
## log, and the diff target against the original. Every derived quantity in the
## rules layer produces one.

var label: String
var base: float = 0.0
var result: float = 0.0
var steps: Array[Dictionary] = []

func _init(p_label: String = "") -> void:
	label = p_label

func step(source: String, before: float, after: float, note: String = "") -> void:
	if before != after or note != "":
		steps.append({"source": source, "before": before, "after": after, "note": note})

static func fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.3f" % v

func explain(indent: String = "") -> String:
	var out: PackedStringArray = ["%s%s: base %s" % [indent, label, fmt(base)]]
	for s in steps:
		var tail: String = ("   # " + String(s["note"])) if String(s["note"]) != "" else ""
		out.append("%s  %-26s %s -> %s%s"
			% [indent, s["source"], fmt(s["before"]), fmt(s["after"]), tail])
	out.append("%s  = %s" % [indent, fmt(result)])
	return "\n".join(out)
