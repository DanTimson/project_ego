class_name ContentId
extends RefCounted

## Canonical content identity: `<pack>:<kind>/<source record id>`.
##
##     genesis:unit/5
##     new_horizons:unit/5
##     genesis:upgrade/76
##     genesis:ability/53
##
## The display name is a LOCALIZATION field and is never an identity. It cannot
## be one. Genesis and New Horizons share 69 unit names of which 27 carry
## different stats, and New Horizons alone uses 11 names for more than one
## record — «Паладин» is 22 attack / 55 life at index 57 and 6 attack / 22 life
## at index 265. A name-keyed lookup returns a plausible wrong record instead of
## failing, which is the reference-table trap one layer up.
##
## The numeric part is the SOURCE record id, not a slug of the name, so it
## survives translation, renaming and re-extraction.
##
## Namespaces mirror docs/CONTENT_REFERENCE_MODEL.md, and the difference between
## them is load-bearing:
##
##     unit     -> unit.var      record index
##     upgrade  -> unit_upg.var  record index  (what unit.var Abilityes points at)
##     ability  -> ability_num   `Number`      (what item/spell/medal Effects use)
##     spell    -> spell.var     record index
##     medal    -> medal.var     record index
##     item     -> item.var      record index

## Table name -> id kind. Tables absent here have no canonical identity yet.
const KIND_FOR_TABLE: Dictionary = {
	"unit": "unit",
	"unit_upg": "upgrade",
	"ability_num": "ability",
	"spell": "spell",
	"medal": "medal",
	"item": "item",
}

## ability_num is addressed by its `Number` column; everything else by record
## index. See docs/CONTENT_REFERENCE_MODEL.md.
const KEY_COLUMN_FOR_TABLE: Dictionary = {"ability_num": "Number"}

var pack: String = ""
var kind: String = ""
var number: int = -1


static func make(p_pack: String, p_kind: String, p_number: int) -> String:
	return "%s:%s/%d" % [p_pack, p_kind, p_number]


static func is_canonical(text: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z0-9_]+:[a-z_]+/[0-9]+$")
	return re.search(text) != null


static func parse(text: String) -> ContentId:
	if not is_canonical(text):
		return null
	var colon := text.find(":")
	var slash := text.rfind("/")
	var out := ContentId.new()
	out.pack = text.substr(0, colon)
	out.kind = text.substr(colon + 1, slash - colon - 1)
	out.number = int(text.substr(slash + 1))
	return out


func _to_string() -> String:
	return ContentId.make(pack, kind, number)
