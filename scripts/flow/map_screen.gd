extends Node2D

signal completed

const PLAYER_SCENE := preload("res://scenes/map/map_player.tscn")
const BASE_VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const DEFAULT_ENTITY_RADIUS := 56.0

@onready var _title_label: Label = %TitleLabel
@onready var _description_label: RichTextLabel = %DescriptionLabel
@onready var _prompt_label: RichTextLabel = %PromptLabel
@onready var _result_label: RichTextLabel = %ResultLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _hotspot_layer: Node2D = %HotspotLayer
@onready var _player_anchor: Marker2D = %PlayerAnchor
@onready var _backdrop: ColorRect = %Backdrop
@onready var _distant_glow: ColorRect = %DistantGlow
@onready var _far_wall: ColorRect = %FarWall
@onready var _main_gate: ColorRect = %MainGate
@onready var _gate_seam: ColorRect = %GateSeam
@onready var _ground: ColorRect = %Ground
@onready var _road_stripe: ColorRect = %RoadStripe
@onready var _top_panel: PanelContainer = %TopPanel
@onready var _bottom_panel: PanelContainer = %BottomPanel
@onready var _event_panel: PanelContainer = %EventPanel
@onready var _event_title_label: Label = %EventTitleLabel
@onready var _event_body_label: RichTextLabel = %EventBodyLabel
@onready var _event_continue_button: Button = %EventContinueButton

var _player: CharacterBody2D
var _required_inspections := 1
var _visited_entities: Dictionary = {}
var _entities: Array[Area2D] = []
var _step_data: Dictionary = {}
var _bounds := {"left": 96.0, "right": 1184.0, "top": 330.0, "bottom": 500.0}
var _event_lines: Array[String] = []
var _event_index := 0
var _active_event_entity: Area2D
var _dialog_open := false


func _ready() -> void:
	get_viewport().size_changed.connect(_update_layout)
	_event_panel.visible = false
	_update_layout()


func regain_focus() -> void:
	get_viewport().gui_release_focus()
	if _dialog_open:
		_event_continue_button.grab_focus()


func setup(step: Dictionary) -> void:
	_step_data = step.duplicate(true)
	_required_inspections = int(step.get("required_inspections", 0))
	_visited_entities.clear()
	_entities.clear()
	_dialog_open = false
	_event_panel.visible = false

	var bounds: Dictionary = step.get("map_bounds", {})
	_bounds = {
		"left": float(bounds.get("left", 96.0)),
		"right": float(bounds.get("right", 1184.0)),
		"top": float(bounds.get("top", 330.0)),
		"bottom": float(bounds.get("bottom", 500.0))
	}

	_title_label.text = str(step.get("title", "地图"))
	_description_label.text = str(step.get("description", ""))
	_result_label.text = "靠近对象后按 Enter 互动。"

	for child in _hotspot_layer.get_children():
		child.queue_free()

	_build_player()
	_build_entities(step.get("map_entities", []))
	_update_layout()
	_update_progress()
	_update_prompt()


func _build_player() -> void:
	if is_instance_valid(_player):
		_player.queue_free()

	_player = PLAYER_SCENE.instantiate()
	_player.position = _player_anchor.position
	_player.move_speed = 260.0
	add_child(_player)


func _build_entities(source_entities: Array) -> void:
	for entity_data_variant in source_entities:
		var entity_data: Dictionary = entity_data_variant
		var root := Area2D.new()
		root.set_meta("entity_data", entity_data.duplicate(true))
		root.position = Vector2(float(entity_data.get("x", 0.0)), float(entity_data.get("y", 0.0)))

		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = float(entity_data.get("radius", DEFAULT_ENTITY_RADIUS))
		collision.shape = shape
		root.add_child(collision)

		var marker := Sprite2D.new()
		marker.texture = preload("res://icon.svg")
		marker.scale = Vector2.ONE * float(entity_data.get("marker_scale", 0.14))
		marker.modulate = _entity_color(str(entity_data.get("type", "inspect")))
		root.add_child(marker)

		var label := Label.new()
		label.text = str(entity_data.get("label", "对象"))
		label.position = Vector2(-60.0, -72.0)
		label.size = Vector2(120.0, 24.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(label)

		_hotspot_layer.add_child(root)
		_entities.append(root)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return

	if _dialog_open:
		return

	_clamp_player()
	_check_proximity_triggers()
	_update_prompt()


func _clamp_player() -> void:
	_player.position.x = clamp(_player.position.x, _scaled_left_limit(), _scaled_right_limit())
	_player.position.y = clamp(_player.position.y, _scaled_top_limit(), _scaled_bottom_limit())


func _check_proximity_triggers() -> void:
	for entity in _entities:
		var entity_data: Dictionary = entity.get_meta("entity_data", {})
		if str(entity_data.get("trigger_mode", "interact")) != "proximity":
			continue
		if _visited_entities.get(str(entity_data.get("id", "")), false):
			continue
		if _requires_more_inspections(entity_data):
			continue
		if _player.position.distance_to(entity.position) <= float(entity_data.get("radius", DEFAULT_ENTITY_RADIUS)):
			_start_event(entity)
			return


func _update_prompt() -> void:
	var entity := _current_entity()
	if entity == null:
		if _remaining_inspections() > 0:
			_prompt_label.text = "继续调查北遥，理解这座城正在腐烂的方式。"
		else:
			_prompt_label.text = "调查已足够，接近敌人或危险区域后会触发下一段。"
		return

	var entity_data: Dictionary = entity.get_meta("entity_data", {})
	var entity_id := str(entity_data.get("id", ""))
	if _visited_entities.get(entity_id, false):
		_prompt_label.text = "这里已经处理过了。"
		return

	if _requires_more_inspections(entity_data):
		_prompt_label.text = "还需要继续调查。当前仍不能直接推进这场遭遇。"
		return

	var action_text := "接近后会自动触发"
	if str(entity_data.get("trigger_mode", "interact")) == "interact":
		action_text = "按 Enter 互动"
	_prompt_label.text = "%s：%s" % [action_text, str(entity_data.get("label", "对象"))]


func _unhandled_input(event: InputEvent) -> void:
	if _dialog_open:
		return

	if event.is_action_pressed("ui_accept") and not event.is_echo():
		var entity := _current_entity()
		if entity != null:
			_start_event(entity)
			get_viewport().set_input_as_handled()


func _start_event(entity: Area2D) -> void:
	var entity_data: Dictionary = entity.get_meta("entity_data", {})
	var entity_id := str(entity_data.get("id", ""))
	if _visited_entities.get(entity_id, false):
		return
	if _requires_more_inspections(entity_data):
		_result_label.text = "还需要先完成更多调查。"
		return

	_active_event_entity = entity
	_dialog_open = true
	if is_instance_valid(_player):
		_player.input_enabled = false

	_event_lines.clear()
	for line in entity_data.get("event_lines", []):
		_event_lines.append(str(line))
	if _event_lines.is_empty():
		_event_lines.append(str(entity_data.get("result", "")))

	_event_index = 0
	_event_title_label.text = str(entity_data.get("label", "事件"))
	_event_panel.visible = true
	_show_event_line()
	_event_continue_button.grab_focus()


func _show_event_line() -> void:
	if _event_index >= _event_lines.size():
		_finish_event()
		return

	_event_body_label.text = _event_lines[_event_index]
	_event_continue_button.text = "继续"
	if _event_index == _event_lines.size() - 1:
		_event_continue_button.text = "结束"


func _finish_event() -> void:
	var entity_data: Dictionary = _active_event_entity.get_meta("entity_data", {})
	var entity_id := str(entity_data.get("id", ""))
	_visited_entities[entity_id] = true
	_result_label.text = str(entity_data.get("result_summary", _event_lines.back() if not _event_lines.is_empty() else ""))
	_dialog_open = false
	_event_panel.visible = false

	if is_instance_valid(_player):
		_player.input_enabled = true

	if bool(entity_data.get("completes_step", false)):
		completed.emit()
		return

	_update_progress()
	_update_prompt()


func _on_event_continue_button_pressed() -> void:
	_event_index += 1
	_show_event_line()


func _update_progress() -> void:
	if _required_inspections <= 0:
		_progress_label.text = "当前区域已切换为推进阶段"
		return

	_progress_label.text = "调查进度 %d / %d" % [_completed_inspections(), _required_inspections]


func _completed_inspections() -> int:
	var count := 0
	for entity in _entities:
		var entity_data: Dictionary = entity.get_meta("entity_data", {})
		if str(entity_data.get("type", "inspect")) != "inspect":
			continue
		if _visited_entities.get(str(entity_data.get("id", "")), false):
			count += 1
	return count


func _remaining_inspections() -> int:
	return max(0, _required_inspections - _completed_inspections())


func _requires_more_inspections(entity_data: Dictionary) -> bool:
	if not bool(entity_data.get("requires_inspections", false)):
		return false
	return _remaining_inspections() > 0


func _current_entity() -> Area2D:
	var nearest: Area2D = null
	var best_distance := INF

	for entity in _entities:
		var entity_data: Dictionary = entity.get_meta("entity_data", {})
		var radius := float(entity_data.get("radius", DEFAULT_ENTITY_RADIUS))
		var distance := _player.position.distance_to(entity.position)
		if distance <= radius and distance < best_distance:
			best_distance = distance
			nearest = entity

	return nearest


func _update_layout() -> void:
	var viewport_size := get_viewport_rect().size
	var scale_vector := Vector2(
		viewport_size.x / BASE_VIEWPORT_SIZE.x,
		viewport_size.y / BASE_VIEWPORT_SIZE.y
	)

	_backdrop.position = Vector2.ZERO
	_backdrop.size = viewport_size

	_distant_glow.position = Vector2(0.0, 66.0 * scale_vector.y)
	_distant_glow.size = Vector2(viewport_size.x, 104.0 * scale_vector.y)

	_far_wall.position = Vector2(0.0, 88.0 * scale_vector.y)
	_far_wall.size = Vector2(viewport_size.x, 240.0 * scale_vector.y)

	var gate_x := viewport_size.x * 0.76
	var gate_width := maxf(166.0 * scale_vector.x, 140.0)
	var gate_top := 106.0 * scale_vector.y
	var gate_height := 336.0 * scale_vector.y
	_main_gate.position = Vector2(gate_x, gate_top)
	_main_gate.size = Vector2(gate_width, gate_height)

	_gate_seam.position = _main_gate.position + Vector2((_main_gate.size.x - 8.0) * 0.5, 0.0)
	_gate_seam.size = Vector2(8.0, _main_gate.size.y)

	var ground_top := viewport_size.y - 180.0 * scale_vector.y
	_ground.position = Vector2(0.0, ground_top)
	_ground.size = Vector2(viewport_size.x, viewport_size.y - ground_top)

	_road_stripe.position = Vector2(104.0 * scale_vector.x, ground_top + 54.0 * scale_vector.y)
	_road_stripe.size = Vector2(viewport_size.x - 208.0 * scale_vector.x, 8.0 * scale_vector.y)

	_player_anchor.position = Vector2(132.0 * scale_vector.x, ground_top - 50.0 * scale_vector.y)
	_hotspot_layer.position = Vector2.ZERO

	_top_panel.offset_left = 24.0
	_top_panel.offset_top = 20.0
	_top_panel.offset_right = minf(viewport_size.x * 0.54, 688.0)
	_top_panel.offset_bottom = 164.0

	_bottom_panel.offset_left = 24.0
	_bottom_panel.offset_top = viewport_size.y - 172.0
	_bottom_panel.offset_right = viewport_size.x - 24.0
	_bottom_panel.offset_bottom = viewport_size.y - 24.0

	_event_panel.offset_left = viewport_size.x * 0.18
	_event_panel.offset_top = viewport_size.y * 0.18
	_event_panel.offset_right = viewport_size.x * 0.82
	_event_panel.offset_bottom = viewport_size.y * 0.48

	_reposition_entities(scale_vector, ground_top)


func _reposition_entities(scale_vector: Vector2, ground_top: float) -> void:
	for index in range(_entities.size()):
		var entity := _entities[index]
		var entity_data: Dictionary = entity.get_meta("entity_data", {})
		entity.position = Vector2(
			float(entity_data.get("x", 0.0)) * scale_vector.x,
			ground_top - (540.0 - float(entity_data.get("y", 0.0))) * scale_vector.y
		)


func _scaled_left_limit() -> float:
	return float(_bounds.get("left", 96.0)) * get_viewport_rect().size.x / BASE_VIEWPORT_SIZE.x


func _scaled_right_limit() -> float:
	return float(_bounds.get("right", 1184.0)) * get_viewport_rect().size.x / BASE_VIEWPORT_SIZE.x


func _scaled_top_limit() -> float:
	return float(_bounds.get("top", 330.0)) * get_viewport_rect().size.y / BASE_VIEWPORT_SIZE.y


func _scaled_bottom_limit() -> float:
	return float(_bounds.get("bottom", 500.0)) * get_viewport_rect().size.y / BASE_VIEWPORT_SIZE.y


func _entity_color(entity_type: String) -> Color:
	match entity_type:
		"enemy":
			return Color(0.84, 0.45, 0.42, 0.95)
		"boss":
			return Color(0.96, 0.67, 0.25, 0.98)
		_:
			return Color(0.86, 0.78, 0.67, 0.9)
