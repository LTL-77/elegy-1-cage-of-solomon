extends Control

signal new_game_requested
signal load_game_requested
signal character_menu_requested
signal quit_requested

@onready var _new_game_button: Button = %NewGameButton
@onready var _load_button: Button = %LoadButton
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	_apply_version_label()
	call_deferred("_focus_default_button")


func set_has_save(has_save: bool) -> void:
	_load_button.disabled = not has_save
	call_deferred("_focus_default_button")


func _focus_default_button() -> void:
	if not is_node_ready():
		return

	if _load_button.disabled:
		_new_game_button.grab_focus()
	else:
		_load_button.grab_focus()


func regain_focus() -> void:
	call_deferred("_focus_default_button")


func _apply_version_label() -> void:
	var version_text := str(ProjectSettings.get_setting("application/config/version", "dev"))
	_version_label.text = "demo v%s" % version_text


func _on_new_game_button_pressed() -> void:
	new_game_requested.emit()


func _on_load_button_pressed() -> void:
	load_game_requested.emit()


func _on_character_button_pressed() -> void:
	character_menu_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()
