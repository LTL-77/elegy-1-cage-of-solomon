extends CharacterBody2D

@export var move_speed: float = 260.0
@export var sprint_multiplier: float = 1.75

var input_enabled := true


func _physics_process(_delta: float) -> void:
	if not input_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var current_speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed *= sprint_multiplier
	velocity = direction * current_speed
	move_and_slide()
