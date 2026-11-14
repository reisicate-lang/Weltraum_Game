## Game time: pause, ×1 (real time), ×2, ×4, ×8, ×16.
## Every frame the elapsed game time is split into steps of at most
## one game second so the simulation stays stable.
extends Node

const MAX_STEP := 1.0 / 60.0  ## one game second in minutes

var speed_index: int = 1
var _last_speed: int = 1

func _process(delta: float) -> void:
	var total := minf(delta, 0.1) * Config.SPEEDS[speed_index] * Config.MINUTES_PER_SECOND
	if total <= 0.0:
		return
	var n := int(ceil(total / MAX_STEP))
	for i in n:
		GameState.step(total / n)

func set_speed(i: int) -> void:
	speed_index = clampi(i, 0, Config.SPEEDS.size() - 1)
	if speed_index > 0:
		_last_speed = speed_index
	EventBus.speed_changed.emit(speed_index)

func toggle_pause() -> void:
	set_speed(_last_speed if speed_index == 0 else 0)
