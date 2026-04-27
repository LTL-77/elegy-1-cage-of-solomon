extends Control

signal resume_requested
signal save_requested
signal exit_battle_requested
signal return_title_requested

@onready var _play_time_label: Label = %PlayTimeLabel
@onready var _save_button: Button = %SaveButton
@onready var _exit_battle_button: Button = %ExitBattleButton


func setup(play_time_text: String, allow_save: bool, allow_exit_battle: bool) -> void:
	_play_time_label.text = "游玩时间  %s" % play_time_text
	_save_button.visible = allow_save
	_exit_battle_button.visible = allow_exit_battle
	call_deferred("_focus_default_button")


func _focus_default_button() -> void:
	%ResumeButton.grab_focus()


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_save_button_pressed() -> void:
	save_requested.emit()


func _on_exit_battle_button_pressed() -> void:
	exit_battle_requested.emit()


func _on_return_title_button_pressed() -> void:
	return_title_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		resume_requested.emit()
		get_viewport().set_input_as_handled()
