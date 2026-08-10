class_name ActionExecutionPlan
extends RefCounted

## Immutable ordered engine operations resolved for one action command.
## This is deliberately not a legacy opcode stream or a user-authored DSL.

enum AttackMode { MELEE }
enum ResourceKind { STAMINA }
enum OperationTarget { SELECTED_ENEMY }


class AttackOp extends RefCounted:
	var kind: StringName:
		get:
			return &"AttackOp"
	var mode: int:
		get:
			return _mode
	var initiating_attack_scale_numerator: int:
		get:
			return _scale_numerator
	var initiating_attack_scale_denominator: int:
		get:
			return _scale_denominator
	var _mode: int
	var _scale_numerator: int
	var _scale_denominator: int

	func _init(p_mode: int, scale_numerator: int = 1,
			scale_denominator: int = 1) -> void:
		assert(scale_denominator > 0,
			"initiating attack scale denominator must be positive")
		_mode = p_mode
		_scale_numerator = scale_numerator
		_scale_denominator = scale_denominator


class ResourceDeltaOp extends RefCounted:
	var kind: StringName:
		get:
			return &"ResourceDeltaOp"
	var target: int:
		get:
			return _target
	var resource: int:
		get:
			return _resource
	var amount: int:
		get:
			return _amount

	var _target: int
	var _resource: int
	var _amount: int

	func _init(p_target: int, p_resource: int, p_amount: int) -> void:
		assert(p_amount <= 0,
			"CX-013 ResourceDeltaOp supports drains only")
		_target = p_target
		_resource = p_resource
		_amount = p_amount


class Executor extends RefCounted:
	## Iterate a validated plan through battle-owned tactical primitives.
	static func execute(plan: ActionExecutionPlan, attack_primitive: Callable,
			resource_delta_primitive: Callable) -> Array:
		var results: Array = []
		for operation in plan.operations():
			if operation is AttackOp:
				results.append(attack_primitive.call(operation))
			elif operation is ResourceDeltaOp:
				results.append(resource_delta_primitive.call(operation))
			else:
				var message := "unsupported internal action operation %s" % [
					type_string(typeof(operation))]
				push_error(message)
				assert(false, message)
		return results


var _operations: Array


func _init(p_operations: Array) -> void:
	_operations = p_operations.duplicate()


func operations() -> Array:
	## Callers cannot reorder or append to the stored sequence.
	return _operations.duplicate()
