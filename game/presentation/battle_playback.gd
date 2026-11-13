class_name BattlePlayback
extends Node

signal beat(observation: BattleObservation)
signal finished
var speed := "Normal"
var reduced_motion := false
var timings := {BattleObservation.Kind.MOVE: 0.32, BattleObservation.Kind.STRIKE: 0.24,
	BattleObservation.Kind.IMPACT: 0.15, BattleObservation.Kind.RESOURCE: 0.24,
	BattleObservation.Kind.EFFECT: 0.35, BattleObservation.Kind.DEFEAT: 0.35,
	BattleObservation.Kind.PHASE: 0.28}
var queue: Array[BattleObservation] = []
var busy := false
var skipping := false
var remaining := 0.0
var history: Array = []

func start(observations: Array[BattleObservation]) -> void:
	cancel()
	queue.assign(observations)
	busy = not queue.is_empty()
	if speed == "Instant":
		skip()

func cancel() -> void:
	queue.clear()
	busy = false
	remaining = 0

func skip() -> void:
	# Skipping only presents detached observations; never reissues a command.
	skipping = true
	while not queue.is_empty():
		show_next()
	skipping = false
	if busy:
		busy = false
		finished.emit()

func show_next() -> void:
	var observation: BattleObservation = queue.pop_front()
	history.append([observation.kind, observation.source, observation.target, observation.amount])
	beat.emit(observation)
	remaining = float(timings.get(observation.kind, 0.2)) / (3 if speed == "Fast" else 1)

func _process(delta: float) -> void:
	if not busy:
		return
	remaining -= delta
	if remaining > 0:
		return
	if queue.is_empty():
		busy = false
		finished.emit()
	else:
		show_next()
