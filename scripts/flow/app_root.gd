extends Node

const TITLE_SCENE := preload("res://scenes/title/title_screen.tscn")
const NARRATIVE_SCENE := preload("res://scenes/narrative/narrative_screen.tscn")
const INTERACTION_SCENE := preload("res://scenes/narrative/interaction_screen.tscn")
const BATTLE_SCENE := preload("res://scenes/battle/battle_screen.tscn")
const MAP_SCENE := preload("res://scenes/map/beiyao_gate_map.tscn")
const CHARACTER_SCENE := preload("res://scenes/character/character_screen.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SAVE_SLOT_MENU_SCENE := preload("res://scenes/ui/save_slot_menu.tscn")

const FLOW_DATA_PATH := "res://data/demo_flow.json"
const BATTLE_DATA_PATH := "res://data/battles.json"
const CHARACTER_DATA_PATH := "res://data/characters.json"
const LEGACY_SAVE_PATH := "user://savegame.json"
const SAVE_DIR := "user://saves"
const AUTOSAVE_SLOT := 0
const TOTAL_SAVE_SLOTS := 5
const AUTOSAVE_INTERVAL := 300.0
const MAP_SNAPSHOT_INTERVAL := 0.5

var _flow_steps: Array = []
var _battle_data: Dictionary = {}
var _character_data: Dictionary = {}
var _current_screen: Node
var _overlay_screen: Control
var _current_step_index := 0
var _game_state := {}
var _pre_battle_player_state := {}
var _pending_unlock_steps: Array[Dictionary] = []
var _current_mode := "title"
var _play_time_seconds := 0.0
var _autosave_elapsed := 0.0
var _map_snapshot_elapsed := 0.0
var _last_map_checkpoint := {}


func _ready() -> void:
	_apply_window_mode()
	_load_content()
	_migrate_legacy_save()
	_reset_game_state()
	_show_title()


func _process(delta: float) -> void:
	if _should_track_play_time():
		_play_time_seconds += delta

	if _should_capture_map_snapshot():
		_map_snapshot_elapsed += delta
		if _map_snapshot_elapsed >= MAP_SNAPSHOT_INTERVAL:
			_capture_map_snapshot()
			_map_snapshot_elapsed = 0.0
	else:
		_map_snapshot_elapsed = 0.0

	if _should_run_autosave():
		_autosave_elapsed += delta
		if _autosave_elapsed >= AUTOSAVE_INTERVAL:
			_save_to_slot(AUTOSAVE_SLOT, true, "interval")
	else:
		_autosave_elapsed = 0.0


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

	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if _current_mode != "title":
			_open_pause_menu()
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
		"character_progress": _build_initial_character_progress(),
		"map_progress": {}
	}
	_current_step_index = 0
	_play_time_seconds = 0.0
	_autosave_elapsed = 0.0
	_pending_unlock_steps.clear()
	_last_map_checkpoint = {}


func _show_title() -> void:
	_current_mode = "title"
	_swap_screen(TITLE_SCENE.instantiate())
	_current_screen.new_game_requested.connect(_on_new_game_requested)
	_current_screen.load_game_requested.connect(_on_load_game_requested)
	_current_screen.character_menu_requested.connect(_on_character_menu_requested)
	_current_screen.quit_requested.connect(_on_quit_requested)
	_current_screen.set_has_save(_has_any_save())


func _on_new_game_requested() -> void:
	_reset_game_state()
	_save_to_slot(AUTOSAVE_SLOT, true, "new_game")
	_run_current_step()


func _on_load_game_requested() -> void:
	_open_save_slot_menu("load")


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
	_current_mode = "narrative"
	_swap_screen(NARRATIVE_SCENE.instantiate())
	_current_screen.setup(step.get("title", ""), step.get("lines", []), _resolve_step_background(_current_step_index))
	_current_screen.completed.connect(_complete_step)


func _show_unlock_narrative(step: Dictionary) -> void:
	_current_mode = "narrative"
	_swap_screen(NARRATIVE_SCENE.instantiate())
	_current_screen.setup(step.get("title", ""), step.get("lines", []), _resolve_step_background(_current_step_index))
	_current_screen.completed.connect(_run_current_step)


func _show_interaction(step: Dictionary) -> void:
	_current_mode = "interaction"
	_swap_screen(INTERACTION_SCENE.instantiate())
	_current_screen.setup(step, _resolve_step_background(_current_step_index))
	_current_screen.completed.connect(_complete_step)


func _show_map(step: Dictionary) -> void:
	_current_mode = "map"
	_swap_screen(MAP_SCENE.instantiate())
	_current_screen.setup(step, _game_state.get("map_progress", {}).get(str(step.get("id", "")), {}))
	_current_screen.completed.connect(_complete_step)
	_capture_map_snapshot()


func _show_battle(step: Dictionary) -> void:
	_current_mode = "battle"
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
	_capture_runtime_state()
	var step: Dictionary = _flow_steps[_current_step_index]
	var completed_steps: Array = _game_state.get("completed_steps", [])
	completed_steps.append(step.get("id", "step_%d" % _current_step_index))
	_game_state["completed_steps"] = completed_steps
	_apply_step_rewards(step)
	_current_step_index += 1
	_save_to_slot(AUTOSAVE_SLOT, true, "step_complete")
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


func _open_pause_menu() -> void:
	if is_instance_valid(_overlay_screen):
		return

	_overlay_screen = PAUSE_MENU_SCENE.instantiate()
	add_child(_overlay_screen)
	var allow_save := _current_mode in ["map", "narrative", "interaction"]
	var allow_exit_battle := _current_mode == "battle"
	_overlay_screen.setup(_format_play_time(_play_time_seconds), allow_save, allow_exit_battle)
	_overlay_screen.resume_requested.connect(_close_overlay)
	_overlay_screen.save_requested.connect(_on_pause_save_requested)
	_overlay_screen.exit_battle_requested.connect(_on_pause_exit_battle_requested)
	_overlay_screen.return_title_requested.connect(_on_pause_return_title_requested)


func _on_pause_save_requested() -> void:
	_close_overlay()
	_open_save_slot_menu("save")


func _on_pause_exit_battle_requested() -> void:
	_close_overlay()
	_exit_battle_to_map()


func _on_pause_return_title_requested() -> void:
	_close_overlay()
	if _current_mode != "battle":
		_save_to_slot(AUTOSAVE_SLOT, true, "return_title")
	_show_title()


func _open_save_slot_menu(mode: String) -> void:
	if is_instance_valid(_overlay_screen):
		return

	_overlay_screen = SAVE_SLOT_MENU_SCENE.instantiate()
	add_child(_overlay_screen)
	_overlay_screen.setup(mode, _build_save_slot_entries())
	_overlay_screen.close_requested.connect(_close_overlay)
	_overlay_screen.slot_selected.connect(_on_save_slot_selected.bind(mode))


func _on_save_slot_selected(slot_index: int, mode: String) -> void:
	if mode == "load":
		if _load_from_slot(slot_index):
			_close_overlay()
			_run_current_step()
			return
	else:
		_save_to_slot(slot_index, slot_index == AUTOSAVE_SLOT, "manual")
		_close_overlay()
		return

	_close_overlay()


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
			lines.append("理解已达到 %d。 " % unlock_value)
			lines.append("回响剧情《%s》已解锁。 " % str(echo_dict.get("title", "未命名回响")))
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
			cg_lines.append("理解已达到 %d。 " % cg_unlock_value)
			cg_lines.append("角色 CG《%s》已解锁。 " % str(cg_unlock.get("title", "未命名CG")))
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


func _should_track_play_time() -> bool:
	return _current_mode != "title" and not is_instance_valid(_overlay_screen)


func _should_capture_map_snapshot() -> bool:
	return _current_mode == "map" and is_instance_valid(_current_screen)


func _should_run_autosave() -> bool:
	return _current_mode in ["map", "narrative", "interaction"] and not is_instance_valid(_overlay_screen)


func _capture_runtime_state() -> void:
	if _current_mode == "map":
		_capture_map_snapshot()
	_game_state["play_time_seconds"] = int(_play_time_seconds)


func _capture_map_snapshot() -> void:
	if not is_instance_valid(_current_screen):
		return
	if not _current_screen.has_method("build_state_snapshot"):
		return
	if _current_step_index < 0 or _current_step_index >= _flow_steps.size():
		return

	var step: Dictionary = _flow_steps[_current_step_index]
	var step_id := str(step.get("id", ""))
	if step_id.is_empty():
		return

	var map_progress: Dictionary = _game_state.get("map_progress", {})
	map_progress[step_id] = _current_screen.call("build_state_snapshot")
	_game_state["map_progress"] = map_progress
	_last_map_checkpoint = {
		"step_index": _current_step_index,
		"game_state": _game_state.duplicate(true),
		"play_time_seconds": _play_time_seconds
	}


func _exit_battle_to_map() -> void:
	if _last_map_checkpoint.is_empty():
		_show_title()
		return

	_current_step_index = int(_last_map_checkpoint.get("step_index", 0))
	_game_state = (_last_map_checkpoint.get("game_state", {}) as Dictionary).duplicate(true)
	_play_time_seconds = float(_last_map_checkpoint.get("play_time_seconds", _play_time_seconds))
	_autosave_elapsed = 0.0
	_run_current_step()


func _ensure_save_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func _slot_path(slot_index: int) -> String:
	if slot_index == AUTOSAVE_SLOT:
		return "%s/autosave.json" % SAVE_DIR
	return "%s/slot_%d.json" % [SAVE_DIR, slot_index]


func _build_save_slot_entries() -> Array:
	var entries: Array = []
	for slot_index in range(TOTAL_SAVE_SLOTS):
		var payload := _read_save_slot(slot_index)
		var metadata: Dictionary = payload.get("meta", {})
		var occupied := not payload.is_empty()
		entries.append({
			"slot_index": slot_index,
			"title": "自动存档" if slot_index == AUTOSAVE_SLOT else "手动存档 %d" % slot_index,
			"occupied": occupied,
			"step_title": str(metadata.get("step_title", "空槽")),
			"play_time_text": _format_play_time(float(metadata.get("play_time_seconds", 0.0))),
			"saved_at": str(metadata.get("saved_at", "")),
			"summary": str(metadata.get("summary", ""))
		})
	return entries


func _has_any_save() -> bool:
	for slot_index in range(TOTAL_SAVE_SLOTS):
		if FileAccess.file_exists(_slot_path(slot_index)):
			return true
	return false


func _save_to_slot(slot_index: int, is_auto: bool, reason: String) -> void:
	_capture_runtime_state()
	_ensure_save_dir()

	var file := FileAccess.open(_slot_path(slot_index), FileAccess.WRITE)
	if file == null:
		push_error("Failed to save slot %d." % slot_index)
		return

	var meta := {
		"slot_index": slot_index,
		"is_auto": is_auto,
		"play_time_seconds": int(_play_time_seconds),
		"step_id": _current_step_id(),
		"step_title": _current_step_title(),
		"summary": _current_step_summary(),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"reason": reason
	}
	var payload := {
		"current_step_index": _current_step_index,
		"game_state": _game_state,
		"play_time_seconds": _play_time_seconds,
		"meta": meta
	}
	file.store_string(JSON.stringify(payload, "\t"))
	_autosave_elapsed = 0.0


func _load_from_slot(slot_index: int) -> bool:
	var payload := _read_save_slot(slot_index)
	if payload.is_empty():
		return false

	_current_step_index = int(payload.get("current_step_index", 0))
	_game_state = (payload.get("game_state", {}) as Dictionary).duplicate(true)
	_play_time_seconds = float(payload.get("play_time_seconds", _game_state.get("play_time_seconds", 0.0)))
	_pending_unlock_steps.clear()
	_autosave_elapsed = 0.0
	_ensure_game_state_defaults()
	return true


func _read_save_slot(slot_index: int) -> Dictionary:
	var path := _slot_path(slot_index)
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _ensure_game_state_defaults() -> void:
	if _game_state.is_empty():
		_reset_game_state()
		return
	if not _game_state.has("character_progress"):
		_game_state["character_progress"] = _build_initial_character_progress()
	if not _game_state.has("map_progress"):
		_game_state["map_progress"] = {}


func _migrate_legacy_save() -> void:
	if _has_any_save():
		return
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return

	var file := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	_current_step_index = int(parsed.get("current_step_index", 0))
	_game_state = (parsed.get("game_state", {}) as Dictionary).duplicate(true)
	_play_time_seconds = float(_game_state.get("play_time_seconds", 0.0))
	_ensure_game_state_defaults()
	_save_to_slot(AUTOSAVE_SLOT, true, "legacy_migration")
	_reset_game_state()


func _current_step_id() -> String:
	if _current_step_index >= 0 and _current_step_index < _flow_steps.size():
		return str((_flow_steps[_current_step_index] as Dictionary).get("id", ""))
	return "title"


func _current_step_title() -> String:
	if _current_step_index >= 0 and _current_step_index < _flow_steps.size():
		return str((_flow_steps[_current_step_index] as Dictionary).get("title", "未命名步骤"))
	return "主标题"


func _current_step_summary() -> String:
	if _current_step_index >= 0 and _current_step_index < _flow_steps.size():
		var step: Dictionary = _flow_steps[_current_step_index]
		if step.has("description"):
			return str(step.get("description", ""))
		if step.has("lines") and not (step.get("lines", []) as Array).is_empty():
			return str((step.get("lines", []) as Array)[0])
	return ""


func _format_play_time(total_seconds: float) -> String:
	var seconds := int(total_seconds)
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	var remain := seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, remain]
