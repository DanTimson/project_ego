class_name CombatContext
extends RefCounted

## Services owned by one battle, passed explicitly through rules and exchanges.
## Environment lookup stays live; no ambient current battle or provider cache.
var pipeline: Pipeline
var environment: Callable
var fatal_resolver: Callable


func _init(p_pipeline: Pipeline = null, p_environment: Callable = Callable(),
		p_fatal_resolver: Callable = Callable()) -> void:
	pipeline = p_pipeline
	environment = p_environment
	fatal_resolver = p_fatal_resolver
