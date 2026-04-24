extends Control

signal new_game_requested
signal load_game_requested
signal quit_requested

@onready var _load_button: Button = %LoadButton


func set_has_save(has_save: bool) -> void:
	_load_button.disabled = not has_save


func _on_new_game_button_pressed() -> void:
	new_game_requested.emit()


func _on_load_button_pressed() -> void:
	load_game_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()
