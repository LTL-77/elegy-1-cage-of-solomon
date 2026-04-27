extends Node

const TITLE_SCENE := preload("res://scenes/title/title_screen.tscn")
const NARRATIVE_SCENE := preload("res://scenes/narrative/narrative_screen.tscn")
const INTERACTION_SCENE := preload("res://scenes/narrative/interaction_screen.tscn")
const BATTLE_SCENE := preload("res://scenes/battle/battle_screen.tscn")
const MAP_SCENE := preload("res://scenes/map/beiyao_gate_map.tscn")
const CHARACTER_SCENE := preload("res://scenes/character/character_screen.tscn")

const FLOW_DATA_PATH := "res://data/demo_flow.json"
const BATTLE_DATA_PATH := "res://data/battles.json"
const CHARACTER_DATA_PATH := "res://data/characters.json"
const SAVE_PATH := "user://savegame.json"

var _flow_steps: Array = []
var _battle_data: Dictionary = {}
var _character_data: Dictionary = {}
var _current_screen: Node
var _overlay_screen: Control
var _current_step_index := 0
var _game_state := {}
var _pre_battle_player_state := {}
var _pending_unlock_steps: Array[Dictionary] = []


func _ready() -> void:
	_apply_window_mode()
	_load_content()
	_reset_game_state()
	_show_title()


func _apply_window_mode() -> void:
	if not _can_use_fullscreen():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _input(event: InputEvent) -> void:
	if is_instance_valid(_overlay_screen):
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		if not _can_use_fullscreen():
			return
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("character_menu") and not event.is_echo():
		_open_character_menu(_selected_character_id())
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("clean_view") and not event.is_echo():
		if is_instance_valid(_current_screen) and _current_screen.has_method("_toggle_clean_view"):
			_current_screen.call("_toggle_clean_view")
			get_viewport().set_input_as_handled()


func _can_use_fullscreen() -> bool:
	return not OS.has_feature("editor")


func _toggle_fullscreen() -> void:
	var current_mode: int = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _load_content() -> void:
	_flow_steps = _load_json_file(FLOW_DATA_PATH).get("steps", [])
	_battle_data = _load_json_file(BATTLE_DATA_PATH)
	_character_data = _load_json_file(CHARACTER_DATA_PATH)


func _load_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing content file: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open content file: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON dictionary in: %s" % path)
		return {}

	return parsed


func _reset_game_state() -> void:
	_game_state = {
		"completed_steps": [],
		"player": _battle_data.get("player_template", {}).duplicate(true),
		"character_progress": _build_initial_character_progress()
	}
	_current_step_index = 0


func _show_title() -> void:
	_swap_screen(TITLE_SCENE.instantiate())
	_current_screen.new_game_requested.connect(_on_new_game_requested)
	_current_screen.load_game_requested.connect(_on_load_game_requested)
	_current_screen.character_menu_requested.connect(_on_character_menu_requested)
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


func _on_character_menu_requested() -> void:
	_open_character_menu(_selected_character_id())


func _on_quit_requested() -> void:
	get_tree().quit()


func _run_current_step() -> void:
	if not _pending_unlock_steps.is_empty():
		_show_unlock_narrative(_pending_unlock_steps.pop_front())
		return

	if _current_step_index >= _flow_steps.size():
		_show_title()
		return

	var step: Dictionary = _flow_steps[_current_step_index]
	var step_type: String = str(step.get("type", ""))

	match step_type:
		"narrative":
			_show_narrative(step)
		"interaction":
			_show_interaction(step)
		"map":
			_show_map(step)
		"battle":
			_show_battle(step)
		_:
			push_error("Unknown step type: %s" % step_type)
			_complete_step()


func _show_narrative(step: Dictionary) -> void:
	_swap_screen(NARRATIVE_SCENE.instantiate())
	_current_screen.setup(step.get("title", ""), step.get("lines", []), _resolve_step_background(_current_step_index))
	_current_screen.completed.connect(_complete_step)


func _show_unlock_narrative(step: Dictionary) -> void:
	_swap_screen(NARRATIVE_SCENE.instantiate())
	_current_screen.setup(step.get("title", ""), step.get("lines", []), _resolve_step_background(_current_step_index))
	_current_screen.completed.connect(_run_current_step)


func _show_interaction(step: Dictionary) -> void:
	_swap_screen(INTERACTION_SCENE.instantiate())
	_current_screen.setup(step, _resolve_step_background(_current_step_index))
	_current_screen.completed.connect(_complete_step)


func _show_map(step: Dictionary) -> void:
	_swap_screen(MAP_SCENE.instantiate())
	_current_screen.setup(step)
	_current_screen.completed.connect(_complete_step)


func _show_battle(step: Dictionary) -> void:
	var battle_id: String = str(step.get("battle_id", ""))
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
	_apply_step_rewards(step)
	_current_step_index += 1
	_save_game()
	_run_current_step()


func _swap_screen(screen: Node) -> void:
	if is_instance_valid(_current_screen):
		_current_screen.queue_free()

	add_child(screen)
	_current_screen = screen


func _open_character_menu(selected_character_id: String) -> void:
	if is_instance_valid(_overlay_screen):
		return

	_overlay_screen = CHARACTER_SCENE.instantiate()
	add_child(_overlay_screen)
	_overlay_screen.setup(_build_character_roster(), selected_character_id)
	_overlay_screen.close_requested.connect(_close_overlay)


func _close_overlay() -> void:
	if not is_instance_valid(_overlay_screen):
		return

	_overlay_screen.queue_free()
	_overlay_screen = null
	get_viewport().gui_release_focus()
	if is_instance_valid(_current_screen) and _current_screen.has_method("regain_focus"):
		_current_screen.call_deferred("regain_focus")


func _selected_character_id() -> String:
	var player: Dictionary = _game_state.get("player", {})
	var player_name := str(player.get("name", ""))
	var characters: Array = _character_data.get("characters", [])

	for character in characters:
		if str(character.get("name", "")) == player_name:
			return str(character.get("id", ""))

	if characters.is_empty():
		return ""

	return str(characters[0].get("id", ""))


func _build_initial_character_progress() -> Dictionary:
	var progress := {}
	for character in _character_data.get("characters", []):
		var character_dict: Dictionary = character
		var understanding: Dictionary = character_dict.get("understanding", {})
		progress[character_dict.get("id", "")] = {
			"understanding_value": int(understanding.get("initial_value", 0)),
			"is_inverted": false
		}
	return progress


func _build_character_roster() -> Array:
	var roster: Array = []
	var progress_map: Dictionary = _game_state.get("character_progress", {})

	for character in _character_data.get("characters", []):
		var character_dict: Dictionary = (character as Dictionary).duplicate(true)
		var character_id := str(character_dict.get("id", ""))
		var progress: Dictionary = progress_map.get(character_id, {})
		var understanding: Dictionary = character_dict.get("understanding", {})
		understanding["current_value"] = int(progress.get("understanding_value", int(understanding.get("initial_value", 0))))
		understanding["is_inverted"] = bool(progress.get("is_inverted", false))
		character_dict["understanding"] = understanding
		roster.append(character_dict)

	return roster


func add_character_understanding(character_id: String, amount: int) -> Array:
	var progress_map: Dictionary = _game_state.get("character_progress", {})
	if not progress_map.has(character_id):
		return []

	var progress: Dictionary = progress_map.get(character_id, {})
	if bool(progress.get("is_inverted", false)):
		return []

	var current_value := int(progress.get("understanding_value", 0))
	var updated_value := clampi(current_value + amount, 0, 100)
	progress["understanding_value"] = updated_value
	progress_map[character_id] = progress
	_game_state["character_progress"] = progress_map
	_save_game()
	return _build_understanding_unlocks(character_id, current_value, updated_value)


func _apply_step_rewards(step: Dictionary) -> void:
	for reward in step.get("understanding_rewards", []):
		var reward_dict: Dictionary = reward
		var unlock_steps: Array = add_character_understanding(
			str(reward_dict.get("character_id", "")),
			int(reward_dict.get("amount", 0))
		)
		for unlock_step in unlock_steps:
			_pending_unlock_steps.append(unlock_step)


func _build_understanding_unlocks(character_id: String, previous_value: int, current_value: int) -> Array:
	var unlock_steps: Array[Dictionary] = []
	var character := _find_character_by_id(character_id)
	if character.is_empty():
		return unlock_steps

	for echo in character.get("echoes", []):
		var echo_dict: Dictionary = echo
		var unlock_value := int(echo_dict.get("unlock_value", 0))
		if previous_value < unlock_value and current_value >= unlock_value:
			var lines: Array[String] = []
			lines.append("理解已达到 %d。" % unlock_value)
			lines.append("回响剧情【%s】已解锁。" % str(echo_dict.get("title", "未命名回响")))
			for line in echo_dict.get("story_lines", []):
				lines.append(str(line))
			unlock_steps.append({
				"title": "%s · 回响解锁" % str(character.get("name", "角色")),
				"lines": lines
			})

	var cg_unlock: Dictionary = character.get("cg_unlock", {})
	if not cg_unlock.is_empty():
		var cg_unlock_value := int(cg_unlock.get("unlock_value", 100))
		if previous_value < cg_unlock_value and current_value >= cg_unlock_value:
			var cg_lines: Array[String] = []
			cg_lines.append("理解已达到 %d。" % cg_unlock_value)
			cg_lines.append("角色 CG【%s】已解锁。" % str(cg_unlock.get("title", "未命名 CG")))
			for line in cg_unlock.get("story_lines", []):
				cg_lines.append(str(line))
			unlock_steps.append({
				"title": "%s · 角色 CG 解锁" % str(character.get("name", "角色")),
				"lines": cg_lines
			})

	return unlock_steps


func _find_character_by_id(character_id: String) -> Dictionary:
	for character in _character_data.get("characters", []):
		var character_dict: Dictionary = character
		if str(character_dict.get("id", "")) == character_id:
			return character_dict
	return {}


func _resolve_step_background(step_index: int) -> String:
	if step_index >= 0 and step_index < _flow_steps.size():
		var current_step: Dictionary = _flow_steps[step_index]
		var direct_background := str(current_step.get("background_image", ""))
		if not direct_background.is_empty():
			return direct_background

	for index in range(step_index, -1, -1):
		var previous_step: Dictionary = _flow_steps[index]
		var previous_background := str(previous_step.get("background_image", ""))
		if not previous_background.is_empty():
			return previous_background

	for index in range(step_index + 1, _flow_steps.size()):
		var next_step: Dictionary = _flow_steps[index]
		var next_background := str(next_step.get("background_image", ""))
		if not next_background.is_empty():
			return next_background

	return ""


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

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	_current_step_index = int(parsed.get("current_step_index", 0))
	_game_state = parsed.get("game_state", {})

	if _game_state.is_empty():
		_reset_game_state()
	elif not _game_state.has("character_progress"):
		_game_state["character_progress"] = _build_initial_character_progress()

	return true
