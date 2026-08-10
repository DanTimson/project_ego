class_name ActionRecipeResolver
extends RefCounted

## Canonical Action identity -> fresh immutable typed execution plan.


class Resolution extends RefCounted:
	var supported: bool
	var plan: ActionExecutionPlan
	var reason: String

	func _init(p_supported: bool, p_plan: ActionExecutionPlan = null,
			p_reason: String = "") -> void:
		supported = p_supported
		plan = p_plan
		reason = p_reason


static func resolve(action: Action) -> Resolution:
	match String(action.id):
		"crushing_blow":
			return Resolution.new(true, ActionExecutionPlan.new([
				ActionExecutionPlan.AttackOp.new(
					ActionExecutionPlan.AttackMode.MELEE, 3, 2),
			]))
		"shield_bash":
			return Resolution.new(true, ActionExecutionPlan.new([
				ActionExecutionPlan.ResourceDeltaOp.new(
					ActionExecutionPlan.OperationTarget.SELECTED_ENEMY,
					ActionExecutionPlan.ResourceKind.STAMINA,
					-action.magnitude),
			]))
	return Resolution.new(false, null, "known action has no frozen recipe")

