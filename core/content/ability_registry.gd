class_name AbilityRegistry
extends RefCounted

## Handler name -> implementation. Handlers are ENGINE code, named not numbered.
## The rules layer never branches on which pack is loaded: it asks the registry
## for a handler name and calls it.

var _handlers: Dictionary = {}

func register(name: StringName, fn: Callable) -> Error:
	if _handlers.has(name):
		push_error("handler %s registered twice" % name)
		return ERR_ALREADY_EXISTS
	_handlers[name] = fn
	return OK

func has(name: StringName) -> bool:
	return _handlers.has(name)

func get_handler(name: StringName) -> Callable:
	return _handlers.get(name, Callable())

func names() -> Array:
	return _handlers.keys()

func call_handler(name: StringName, ctx: Dictionary, value: Variant,
		params: Dictionary) -> Variant:
	return (_handlers[name] as Callable).call(ctx, value, params)
