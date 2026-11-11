extends Node

signal tick(seconds: float)

func _physics_process(delta: float) -> void:
	tick.emit(delta)
