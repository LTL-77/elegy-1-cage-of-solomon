extends Node

const TITLE_SCENE := preload("res://scenes/title/title_screen.tscn")
const NARRATIVE_SCENE := preload("res://scenes/narrative/narrative_screen.tscn")
const INTERACTION_SCENE := preload("res://scenes/narrative/interaction_screen.tscn")
const BATTLE_SCENE := preload("res://scenes/battle/battle_screen.tscn")

const FLOW_DATA_PATH := "res://data/demo_flow.json"
const BATTLE_DATA_PATH := "res://data/battles.json"
const SAVE_PATH := "user://savegame.json"

var _flow_steps: Array = []
var _battle_data: Dictionary = {}
var _current_screen: Node
var _current_step_index := 0
var _game_state := {}
var _pre_battle_player_state := {}

func _ready() -> void:
	_load_content()
	_reset_game_state()
	_show_title()


func _load_content() -> void:
	_flow_steps = _load_json_file(FLOW_DATA_PATH).get("steps", [])
	_battle_data = _load_json_file(BATTLE_DATA_PATH)


func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing content file: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open content file: %s" % path)
		return {}

	var parsed := JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON dictionary in: %s" % path)
		return {}

	return parsed


func _reset_game_state() -> void:
	_game_state = {
		"completed_steps": [],
		"player": _battle_data.get("player_template", {}).duplicate(true)
	}
	_current_step_index = 0


func _show_title() -> void:
	_swap_screen(TITLE_SCENE.instantiate())
	_current_screen.new_game_requested.connect(_on_new_game_requested)
	_current_screen.load_game_requested.connect(_on_load_game_requested)
	_current_screen.quit_requested.connect(_on_quit_requested)
	_current_screen.set_has_save(_has_save())


func _on_new_game_requested() -> void:
	_reset_game_state()
	_save_game()
	_run_current_step()


func _on_load_game_requested() -> void:
	if not _load_game():
		_show_title()
		return

	_run_current_step()


func _on_quit_requested() -> void:
	get_tree().quit()


func _run_current_step() -> void:
	if _current_step_index >= _flow_steps.size():
		_show_title()
		return

	var step: Dictionary = _flow_steps[_current_step_index]
	var step_type := step.get("type", "")

	match step_type:
		"narrative":
			_show_narrative(step)
		"interaction":
			_show_interaction(step)
		"battle":
			_show_battle(step)
		_:
			push_error("Unknown step type: %s" % step_type)
			_complete_step()


func _show_narrative(step: Dictionary) -> void:
	_swap_screen(NARRATIVE_SCENE.instantiate())
	_current_screen.setup(step.get("title", ""), step.get("lines", []))
	_current_screen.completed.connect(_complete_step)


func _show_interaction(step: Dictionary) -> void:
	_swap_screen(INTERACTION_SCENE.instantiate())
	_current_screen.setup(step)
	_current_screen.completed.connect(_complete_step)


func _show_battle(step: Dictionary) -> void:
	var battle_id := step.get("battle_id", "")
	var encounter: Dictionary = _battle_data.get("battles", {}).get(battle_id, {})
	_pre_battle_player_state = _game_state.get("player", {}).duplicate(true)
	_swap_screen(BATTLE_SCENE.instantiate())
	_current_screen.setup(encounter, _game_state.get("player", {}).duplicate(true))
	_current_screen.battle_finished.connect(_on_battle_finished)


func _on_battle_finished(victory: bool, updated_player: Dictionary) -> void:
	if victory:
		_game_state["player"] = updated_player.duplicate(true)
		_complete_step()
		return

	_game_state["player"] = _pre_battle_player_state.duplicate(true)
	_run_current_step()


func _complete_step() -> void:
	var step: Dictionary = _flow_steps[_current_step_index]
	var completed_steps: Array = _game_state.get("completed_steps", [])
	completed_steps.append(step.get("id", "step_%d" % _current_step_index))
	_game_state["completed_steps"] = completed_steps
	_current_step_index += 1
	_save_game()
	_run_current_step()


func _swap_screen(screen: Node) -> void:
	if is_instance_valid(_current_screen):
		_current_screen.queue_free()

	add_child(screen)
	_current_screen = screen


func _has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func _save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to save game.")
		return

	var payload := {
		"current_step_index": _current_step_index,
		"game_state": _game_state
	}
	file.store_string(JSON.stringify(payload, "\t"))


func _load_game() -> bool:
	if not _has_save():
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false

	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	_current_step_index = int(parsed.get("current_step_index", 0))
	_game_state = parsed.get("game_state", {})

	if _game_state.is_empty():
		_reset_game_state()

	return true
