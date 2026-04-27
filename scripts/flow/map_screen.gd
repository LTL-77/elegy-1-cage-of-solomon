extends Node2D

signal completed

const PLAYER_SCENE := preload("res://scenes/map/map_player.tscn")
const BASE_VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const DEFAULT_ENTITY_RADIUS := 56.0
const DEFAULT_THEME := {
	"backdrop_color": Color(0.105882, 0.109804, 0.145098, 1.0),
	"distant_glow_color": Color(0.278431, 0.227451, 0.176471, 0.16),
	"far_wall_color": Color(0.160784, 0.156863, 0.180392, 1.0),
	"main_gate_color": Color(0.219608, 0.196078, 0.180392, 1.0),
	"gate_seam_color": Color(0.0823529, 0.0745098, 0.0784314, 1.0),
	"ground_color": Color(0.203922, 0.184314, 0.176471, 1.0),
	"road_stripe_color": Color(0.45098, 0.392157, 0.317647, 0.38),
	"show_main_gate": true,
	"show_road_stripe": true,
	"gate_x_ratio": 0.76,
	"gate_width": 166.0,
	"gate_height": 336.0,
	"gate_top": 106.0,
	"wall_top": 88.0,
	"wall_height": 240.0,
	"glow_top": 66.0,
	"glow_height": 104.0,
	"ground_height": 180.0,
	"player_anchor_x": 132.0,
	"player_anchor_y": 490.0,
	"top_panel_width": 0.54
}

@onready var _title_label: Label = %TitleLabel
@onready var _description_label: RichTextLabel = %DescriptionLabel
@onready var _prompt_label: RichTextLabel = %PromptLabel
@onready var _result_label: RichTextLabel = %ResultLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _background_detail_layer: Node2D = %BackgroundDetailLayer
@onready var _architecture_layer: Node2D = %ArchitectureLayer
@onready var _prop_layer: Node2D = %PropLayer
@onready var _hotspot_layer: Node2D = %HotspotLayer
@onready var _foreground_layer: Node2D = %ForegroundLayer
@onready var _player_anchor: Marker2D = %PlayerAnchor
@onready var _backdrop: ColorRect = %Backdrop
@onready var _background_image: TextureRect = %BackgroundImage
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
var _camera: Camera2D
var _required_inspections := 1
var _visited_entities: Dictionary = {}
var _entities: Array[Area2D] = []
var _step_data: Dictionary = {}
var _bounds := {"left": 96.0, "right": 1184.0, "top": 330.0, "bottom": 500.0}
var _event_lines: Array[String] = []
var _event_index := 0
var _active_event_entity: Area2D
var _dialog_open := false
var _map_theme: Dictionary = DEFAULT_THEME.duplicate(true)
var _background_image_path := ""
var _background_image_size := Vector2.ZERO
var _background_image_rect := Rect2()
var _clean_view := false


func _ready() -> void:
	get_viewport().size_changed.connect(_update_layout)
	_event_panel.visible = false
	_update_layout()


func regain_focus() -> void:
	get_viewport().gui_release_focus()
	if _dialog_open and not _clean_view:
		_event_continue_button.grab_focus()


func setup(step: Dictionary) -> void:
	_step_data = step.duplicate(true)
	_required_inspections = int(step.get("required_inspections", 0))
	_visited_entities.clear()
	_entities.clear()
	_dialog_open = false
	_event_panel.visible = false
	_clean_view = false
	_top_panel.visible = true
	_bottom_panel.visible = true

	var bounds: Dictionary = step.get("map_bounds", {})
	_bounds = {
		"left": float(bounds.get("left", 96.0)),
		"right": float(bounds.get("right", 1184.0)),
		"top": float(bounds.get("top", 330.0)),
		"bottom": float(bounds.get("bottom", 500.0))
	}

	_title_label.text = str(step.get("title", "地图"))
	_description_label.text = _format_rich_text(str(step.get("description", "")))
	_result_label.text = "靠近对象后按 Enter 互动。"
	_map_theme = _build_theme(step.get("map_theme", {}))
	_background_image_path = str(step.get("background_image", ""))
	_configure_background_image()
	_apply_theme_colors()

	for child in _hotspot_layer.get_children():
		child.queue_free()
	for child in _background_detail_layer.get_children():
		child.queue_free()
	for child in _architecture_layer.get_children():
		child.queue_free()
	for child in _prop_layer.get_children():
		child.queue_free()
	for child in _foreground_layer.get_children():
		child.queue_free()

	_build_player()
	_build_background_scene(str(step.get("scene_style", _map_theme.get("scene_style", "gate"))))
	_build_props(step.get("map_props", []))
	_build_entities(step.get("map_entities", []))
	_update_layout()
	if is_instance_valid(_player):
		_player.position = _player_anchor.position
		_update_camera_limits()
		if is_instance_valid(_camera):
			_camera.reset_smoothing()
	_update_progress()
	_update_prompt()


func _build_player() -> void:
	if is_instance_valid(_player):
		_player.queue_free()

	_player = PLAYER_SCENE.instantiate()
	_player.position = _player_anchor.position
	_player.move_speed = 260.0
	add_child(_player)
	_camera = Camera2D.new()
	_camera.enabled = true
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_player.add_child(_camera)
	_camera.make_current()


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

		if bool(entity_data.get("show_visual", true)):
			var visual: Node2D = _create_prop_visual(
				str(entity_data.get("prop_style", _default_prop_style(entity_data))),
				_entity_color(str(entity_data.get("type", "inspect")))
			)
			root.add_child(visual)

		if bool(entity_data.get("show_label", true)):
			var label := Label.new()
			label.text = str(entity_data.get("label", "对象"))
			label.position = Vector2(-60.0, -84.0)
			label.size = Vector2(120.0, 24.0)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			root.add_child(label)

		if bool(entity_data.get("show_highlight", true)):
			root.add_child(_create_interaction_highlight(_entity_color(str(entity_data.get("type", "inspect")))))

		_hotspot_layer.add_child(root)
		_entities.append(root)


func _build_props(source_props: Array) -> void:
	for prop_data_variant in source_props:
		var prop_data: Dictionary = prop_data_variant
		var root := Node2D.new()
		root.set_meta("prop_data", prop_data.duplicate(true))
		root.position = Vector2(float(prop_data.get("x", 0.0)), float(prop_data.get("y", 0.0)))

		var color := _prop_color(str(prop_data.get("color_role", "detail")))
		var visual := _create_prop_visual(str(prop_data.get("style", "crate")), color)
		root.add_child(visual)

		_prop_layer.add_child(root)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return

	_update_entity_highlights()

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
	if event.is_action_pressed("clean_view") and not event.is_echo():
		_toggle_clean_view()
		get_viewport().set_input_as_handled()
		return

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
	_bottom_panel.visible = false

	_event_lines.clear()
	for line in entity_data.get("event_lines", []):
		_event_lines.append(str(line))
	if _event_lines.is_empty():
		_event_lines.append(str(entity_data.get("result", "")))

	_event_index = 0
	_event_title_label.text = str(entity_data.get("label", "事件"))
	_event_panel.visible = not _clean_view
	_pulse_entity(entity)
	_play_panel_shake(_event_panel)
	_play_camera_shake(16.0)
	_show_event_line()
	if not _clean_view:
		_event_continue_button.grab_focus()


func _show_event_line() -> void:
	if _event_index >= _event_lines.size():
		_finish_event()
		return

	_event_body_label.text = _format_rich_text(_event_lines[_event_index])
	_event_continue_button.text = "继续"
	if _event_index == _event_lines.size() - 1:
		_event_continue_button.text = "结束"


func _finish_event() -> void:
	var entity_data: Dictionary = _active_event_entity.get_meta("entity_data", {})
	var entity_id := str(entity_data.get("id", ""))
	_visited_entities[entity_id] = true
	_result_label.text = _format_rich_text(str(entity_data.get("result_summary", _event_lines.back() if not _event_lines.is_empty() else "")))
	_play_panel_shake(_bottom_panel)
	_dialog_open = false
	_event_panel.visible = false
	_bottom_panel.visible = not _clean_view

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


func _pulse_entity(entity: Area2D) -> void:
	if entity == null:
		return
	var tween := create_tween()
	tween.tween_property(entity, "scale", Vector2(1.06, 1.06), 0.06)
	tween.tween_property(entity, "scale", Vector2.ONE, 0.1)


func _play_panel_shake(panel: Control) -> void:
	if panel == null:
		return
	var base_position := panel.position
	var tween := create_tween()
	tween.tween_property(panel, "position", base_position + Vector2(10.0, 0.0), 0.04)
	tween.tween_property(panel, "position", base_position + Vector2(-8.0, 0.0), 0.05)
	tween.tween_property(panel, "position", base_position, 0.05)


func _play_camera_shake(amount: float) -> void:
	if _camera == null:
		return
	_camera.offset = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(_camera, "offset", Vector2(amount, 0.0), 0.04)
	tween.tween_property(_camera, "offset", Vector2(-amount * 0.75, 0.0), 0.05)
	tween.tween_property(_camera, "offset", Vector2.ZERO, 0.06)


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
	_update_background_image_layout(viewport_size)

	_distant_glow.position = Vector2(0.0, _theme_float("glow_top", 66.0) * scale_vector.y)
	_distant_glow.size = Vector2(viewport_size.x, _theme_float("glow_height", 104.0) * scale_vector.y)

	_far_wall.position = Vector2(0.0, _theme_float("wall_top", 88.0) * scale_vector.y)
	_far_wall.size = Vector2(viewport_size.x, _theme_float("wall_height", 240.0) * scale_vector.y)

	var gate_x := viewport_size.x * _theme_float("gate_x_ratio", 0.76)
	var gate_width := maxf(_theme_float("gate_width", 166.0) * scale_vector.x, 140.0)
	var gate_top := _theme_float("gate_top", 106.0) * scale_vector.y
	var gate_height := _theme_float("gate_height", 336.0) * scale_vector.y
	_main_gate.position = Vector2(gate_x, gate_top)
	_main_gate.size = Vector2(gate_width, gate_height)
	_main_gate.visible = not _uses_background_image() and bool(_map_theme.get("show_main_gate", true))

	_gate_seam.position = _main_gate.position + Vector2((_main_gate.size.x - 8.0) * 0.5, 0.0)
	_gate_seam.size = Vector2(8.0, _main_gate.size.y)
	_gate_seam.visible = _main_gate.visible

	var ground_top := viewport_size.y - _theme_float("ground_height", 180.0) * scale_vector.y
	_ground.position = Vector2(0.0, ground_top)
	_ground.size = Vector2(viewport_size.x, viewport_size.y - ground_top)

	_road_stripe.position = Vector2(104.0 * scale_vector.x, ground_top + 54.0 * scale_vector.y)
	_road_stripe.size = Vector2(viewport_size.x - 208.0 * scale_vector.x, 8.0 * scale_vector.y)
	_road_stripe.visible = not _uses_background_image() and bool(_map_theme.get("show_road_stripe", true))

	if _uses_background_image():
		_player_anchor.position = Vector2(
			_background_image_rect.position.x + _theme_float("player_anchor_x", 132.0) * _background_image_rect.size.x / maxf(_background_image_size.x, 1.0),
			_background_image_rect.position.y + _theme_float("player_anchor_y", 490.0) * _background_image_rect.size.y / maxf(_background_image_size.y, 1.0)
		)
	else:
		_player_anchor.position = Vector2(
			_theme_float("player_anchor_x", 132.0) * scale_vector.x,
			ground_top - (540.0 - _theme_float("player_anchor_y", 490.0)) * scale_vector.y
		)
	_background_detail_layer.position = Vector2.ZERO
	_architecture_layer.position = Vector2.ZERO
	_hotspot_layer.position = Vector2.ZERO
	_prop_layer.position = Vector2.ZERO
	_foreground_layer.position = Vector2.ZERO

	_top_panel.offset_left = 24.0
	_top_panel.offset_top = 20.0
	_top_panel.offset_right = minf(viewport_size.x * _theme_float("top_panel_width", 0.54), 688.0)
	_top_panel.offset_bottom = 164.0

	_bottom_panel.offset_left = 24.0
	_bottom_panel.offset_top = viewport_size.y - 172.0
	_bottom_panel.offset_right = viewport_size.x - 24.0
	_bottom_panel.offset_bottom = viewport_size.y - 24.0

	_event_panel.offset_left = 24.0
	_event_panel.offset_top = viewport_size.y - 196.0
	_event_panel.offset_right = viewport_size.x - 24.0
	_event_panel.offset_bottom = viewport_size.y - 24.0

	_reposition_entities(scale_vector, ground_top)
	_reposition_background_layers(scale_vector, ground_top)
	_reposition_props(scale_vector, ground_top)
	_update_camera_limits()


func _reposition_entities(scale_vector: Vector2, ground_top: float) -> void:
	for index in range(_entities.size()):
		var entity := _entities[index]
		var entity_data: Dictionary = entity.get_meta("entity_data", {})
		entity.position = _map_to_screen_position(entity_data, scale_vector, ground_top)


func _reposition_props(scale_vector: Vector2, ground_top: float) -> void:
	for prop in _prop_layer.get_children():
		var prop_data: Dictionary = prop.get_meta("prop_data", {})
		prop.position = _map_to_screen_position(prop_data, scale_vector, ground_top)


func _reposition_background_layers(scale_vector: Vector2, ground_top: float) -> void:
	for layer in [_background_detail_layer, _architecture_layer, _foreground_layer]:
		for node in layer.get_children():
			var scene_data: Dictionary = node.get_meta("scene_data", {})
			node.position = _map_to_screen_position(scene_data, scale_vector, ground_top)


func _scaled_left_limit() -> float:
	if _uses_background_image():
		return _background_image_rect.position.x + float(_bounds.get("left", 0.0)) * _background_image_rect.size.x / maxf(_background_image_size.x, 1.0)
	return float(_bounds.get("left", 96.0)) * get_viewport_rect().size.x / BASE_VIEWPORT_SIZE.x


func _scaled_right_limit() -> float:
	if _uses_background_image():
		return _background_image_rect.position.x + float(_bounds.get("right", 0.0)) * _background_image_rect.size.x / maxf(_background_image_size.x, 1.0)
	return float(_bounds.get("right", 1184.0)) * get_viewport_rect().size.x / BASE_VIEWPORT_SIZE.x


func _scaled_top_limit() -> float:
	if _uses_background_image():
		return _background_image_rect.position.y + float(_bounds.get("top", 0.0)) * _background_image_rect.size.y / maxf(_background_image_size.y, 1.0)
	return float(_bounds.get("top", 330.0)) * get_viewport_rect().size.y / BASE_VIEWPORT_SIZE.y


func _scaled_bottom_limit() -> float:
	if _uses_background_image():
		return _background_image_rect.position.y + float(_bounds.get("bottom", 0.0)) * _background_image_rect.size.y / maxf(_background_image_size.y, 1.0)
	return float(_bounds.get("bottom", 500.0)) * get_viewport_rect().size.y / BASE_VIEWPORT_SIZE.y


func _entity_color(entity_type: String) -> Color:
	match entity_type:
		"enemy":
			return Color(0.84, 0.45, 0.42, 0.95)
		"boss":
			return Color(0.96, 0.67, 0.25, 0.98)
		_:
			return Color(0.86, 0.78, 0.67, 0.9)

func _create_interaction_highlight(base_color: Color) -> Node2D:
	var root := Node2D.new()
	root.name = "InteractionHighlight"
	root.position = Vector2(0.0, -82.0)
	root.z_index = 30

	var ring := Line2D.new()
	ring.name = "Ring"
	ring.width = 3.0
	ring.closed = true
	ring.default_color = base_color
	ring.points = PackedVector2Array([
		Vector2(0.0, -12.0),
		Vector2(14.0, 0.0),
		Vector2(0.0, 12.0),
		Vector2(-14.0, 0.0)
	])
	root.add_child(ring)

	var pointer := Polygon2D.new()
	pointer.name = "Pointer"
	pointer.color = base_color
	pointer.polygon = PackedVector2Array([
		Vector2(0.0, 18.0),
		Vector2(8.0, 4.0),
		Vector2(-8.0, 4.0)
	])
	root.add_child(pointer)

	var glow := Polygon2D.new()
	glow.name = "Glow"
	glow.color = Color(base_color.r, base_color.g, base_color.b, 0.16)
	glow.polygon = PackedVector2Array([
		Vector2(0.0, -20.0),
		Vector2(22.0, 0.0),
		Vector2(0.0, 20.0),
		Vector2(-22.0, 0.0)
	])
	root.add_child(glow)

	return root


func _update_entity_highlights() -> void:
	var time := Time.get_ticks_msec() / 1000.0
	for index in range(_entities.size()):
		var entity := _entities[index]
		var highlight := entity.get_node_or_null("InteractionHighlight")
		if highlight == null:
			continue

		var entity_data: Dictionary = entity.get_meta("entity_data", {})
		var entity_id := str(entity_data.get("id", ""))
		if _visited_entities.get(entity_id, false):
			highlight.visible = false
			continue

		highlight.visible = true
		var base_color := _entity_color(str(entity_data.get("type", "inspect")))
		var locked := _requires_more_inspections(entity_data)
		if locked:
			base_color = Color(0.55, 0.57, 0.62, 0.82)

		var in_range := false
		if is_instance_valid(_player):
			in_range = _player.position.distance_to(entity.position) <= float(entity_data.get("radius", DEFAULT_ENTITY_RADIUS))

		var pulse := 0.92 + 0.08 * sin(time * 4.0 + float(index))
		var hover := 4.0 * sin(time * 3.0 + float(index) * 0.6)
		highlight.position.y = -82.0 + hover
		highlight.scale = Vector2.ONE * pulse

		var ring: Line2D = highlight.get_node("Ring")
		var pointer: Polygon2D = highlight.get_node("Pointer")
		var glow: Polygon2D = highlight.get_node("Glow")
		var emphasis := 1.0
		if in_range:
			emphasis = 1.25
		ring.default_color = Color(base_color.r, base_color.g, base_color.b, clampf(0.75 * emphasis, 0.0, 1.0))
		pointer.color = Color(base_color.r, base_color.g, base_color.b, clampf(0.88 * emphasis, 0.0, 1.0))
		glow.color = Color(base_color.r, base_color.g, base_color.b, 0.14 if locked else 0.20 * emphasis)


func _prop_color(role: String) -> Color:
	match role:
		"metal":
			return Color(0.60, 0.62, 0.70, 0.96)
		"warning":
			return Color(0.76, 0.45, 0.31, 0.96)
		"stone":
			return Color(0.46, 0.44, 0.49, 0.96)
		"light":
			return Color(0.88, 0.72, 0.38, 0.98)
		_:
			return Color(0.54, 0.46, 0.39, 0.96)


func _default_prop_style(entity_data: Dictionary) -> String:
	var label := str(entity_data.get("label", ""))
	var entity_type := str(entity_data.get("type", "inspect"))
	if entity_type == "boss":
		return "door"
	if entity_type == "enemy":
		return "guard"
	if label.contains("门锚"):
		return "anchor"
	if label.contains("巡防") or label.contains("巡逻"):
		return "guard"
	if label.contains("裂隙石"):
		return "cart"
	if label.contains("灯柱") or label.contains("灯"):
		return "lamp"
	if label.contains("塌") or label.contains("碎"):
		return "rubble"
	if label.contains("污水") or label.contains("排水"):
		return "drain"
	if label.contains("刻字") or label.contains("兵略"):
		return "figure"
	if label.contains("诱饵"):
		return "crate"
	return "sign"


func _create_prop_visual(style: String, base_color: Color) -> Node2D:
	var root := Node2D.new()
	match style:
		"rubble":
			_add_pixel_rect(root, Rect2(-34, -18, 24, 18), base_color.darkened(0.2))
			_add_pixel_rect(root, Rect2(-8, -30, 28, 30), base_color)
			_add_pixel_rect(root, Rect2(16, -18, 18, 18), base_color.darkened(0.1))
		"anchor":
			_add_pixel_rect(root, Rect2(-8, -36, 16, 36), base_color)
			_add_pixel_rect(root, Rect2(-20, -28, 40, 8), base_color.lightened(0.12))
			_add_pixel_rect(root, Rect2(-28, -12, 56, 12), base_color.darkened(0.18))
		"lamp":
			_add_pixel_rect(root, Rect2(-6, -46, 12, 46), base_color.darkened(0.3))
			_add_pixel_rect(root, Rect2(-18, -52, 36, 12), _prop_color("light"))
			_add_pixel_rect(root, Rect2(-10, -58, 20, 8), _prop_color("light").lightened(0.2))
		"cart":
			_add_pixel_rect(root, Rect2(-32, -24, 64, 24), base_color.darkened(0.15))
			_add_pixel_rect(root, Rect2(-24, -40, 48, 16), base_color)
			_add_pixel_rect(root, Rect2(-28, -8, 16, 8), Color(0.22, 0.22, 0.27, 1.0))
			_add_pixel_rect(root, Rect2(12, -8, 16, 8), Color(0.22, 0.22, 0.27, 1.0))
		"guard":
			_add_pixel_rect(root, Rect2(-10, -46, 20, 46), base_color.darkened(0.08))
			_add_pixel_rect(root, Rect2(-8, -58, 16, 16), Color(0.78, 0.72, 0.66, 1.0))
			_add_pixel_rect(root, Rect2(10, -34, 12, 26), base_color.lightened(0.14))
		"door":
			_add_pixel_rect(root, Rect2(-40, -70, 80, 70), base_color.darkened(0.18))
			_add_pixel_rect(root, Rect2(-36, -66, 72, 62), base_color)
			_add_pixel_rect(root, Rect2(-4, -66, 8, 62), base_color.darkened(0.32))
		"figure":
			_add_pixel_rect(root, Rect2(-10, -44, 20, 44), base_color.darkened(0.12))
			_add_pixel_rect(root, Rect2(-8, -58, 16, 16), Color(0.74, 0.70, 0.67, 1.0))
		"drain":
			_add_pixel_rect(root, Rect2(-34, -10, 68, 10), base_color.darkened(0.3))
			_add_pixel_rect(root, Rect2(-28, -24, 56, 14), base_color)
		"crate":
			_add_pixel_rect(root, Rect2(-24, -28, 48, 28), base_color)
			_add_pixel_rect(root, Rect2(-24, -16, 48, 4), base_color.lightened(0.12))
			_add_pixel_rect(root, Rect2(-2, -28, 4, 28), base_color.darkened(0.12))
		_:
			_add_pixel_rect(root, Rect2(-8, -42, 16, 42), base_color.darkened(0.12))
			_add_pixel_rect(root, Rect2(-22, -54, 44, 18), base_color)

	return root


func _build_background_scene(scene_style: String) -> void:
	if _uses_background_image():
		return
	match scene_style:
		"mine":
			_add_scene_piece(_background_detail_layer, "beam", "stone", 170, 428)
			_add_scene_piece(_background_detail_layer, "beam", "stone", 354, 408)
			_add_scene_piece(_background_detail_layer, "beam", "stone", 550, 420)
			_add_scene_piece(_architecture_layer, "cavern", "stone", 320, 372)
			_add_scene_piece(_architecture_layer, "cavern", "stone", 682, 360)
			_add_scene_piece(_prop_layer, "lamp", "light", 1010, 458)
			_add_scene_piece(_foreground_layer, "beam", "detail", 1140, 514)
		"cargo":
			_add_scene_piece(_background_detail_layer, "tower", "stone", 176, 366)
			_add_scene_piece(_background_detail_layer, "tower", "stone", 962, 362)
			_add_scene_piece(_architecture_layer, "wall_segment", "stone", 336, 362)
			_add_scene_piece(_architecture_layer, "wall_segment", "stone", 760, 362)
			_add_scene_piece(_architecture_layer, "grate", "metal", 586, 452)
			_add_scene_piece(_foreground_layer, "rail", "metal", 670, 516)
		"outer":
			_add_scene_piece(_background_detail_layer, "spire", "stone", 206, 350)
			_add_scene_piece(_background_detail_layer, "spire", "stone", 994, 348)
			_add_scene_piece(_architecture_layer, "arcade", "stone", 386, 388)
			_add_scene_piece(_architecture_layer, "arcade", "stone", 790, 388)
			_add_scene_piece(_architecture_layer, "banner", "warning", 612, 402)
			_add_scene_piece(_foreground_layer, "hedge", "detail", 1080, 514)
		"sanctum":
			_add_scene_piece(_background_detail_layer, "pillar", "stone", 322, 378)
			_add_scene_piece(_background_detail_layer, "pillar", "stone", 876, 378)
			_add_scene_piece(_architecture_layer, "sanctum_frame", "stone", 666, 368)
			_add_scene_piece(_architecture_layer, "banner", "warning", 472, 394)
			_add_scene_piece(_architecture_layer, "banner", "warning", 860, 394)
			_add_scene_piece(_foreground_layer, "rail", "metal", 728, 514)
		_:
			_add_scene_piece(_background_detail_layer, "tower", "stone", 220, 360)
			_add_scene_piece(_architecture_layer, "wall_segment", "stone", 720, 370)


func _add_scene_piece(layer: Node2D, style: String, color_role: String, x: float, y: float) -> void:
	var root := Node2D.new()
	root.set_meta("scene_data", {
		"x": x,
		"y": y
	})
	root.add_child(_create_scene_visual(style, _prop_color(color_role)))
	layer.add_child(root)


func _create_scene_visual(style: String, base_color: Color) -> Node2D:
	var root := Node2D.new()
	match style:
		"beam":
			_add_pixel_rect(root, Rect2(-52, -12, 104, 12), base_color.darkened(0.18))
			_add_pixel_rect(root, Rect2(-44, -34, 16, 34), base_color)
			_add_pixel_rect(root, Rect2(28, -34, 16, 34), base_color)
		"cavern":
			_add_pixel_rect(root, Rect2(-90, -92, 180, 92), base_color.darkened(0.22))
			_add_pixel_rect(root, Rect2(-76, -74, 152, 28), base_color.darkened(0.08))
		"tower":
			_add_pixel_rect(root, Rect2(-28, -130, 56, 130), base_color.darkened(0.22))
			_add_pixel_rect(root, Rect2(-40, -148, 80, 18), base_color)
			_add_pixel_rect(root, Rect2(-14, -104, 28, 16), base_color.lightened(0.08))
		"wall_segment":
			_add_pixel_rect(root, Rect2(-120, -102, 240, 102), base_color.darkened(0.16))
			_add_pixel_rect(root, Rect2(-120, -70, 240, 8), base_color.lightened(0.10))
		"grate":
			_add_pixel_rect(root, Rect2(-74, -30, 148, 30), base_color.darkened(0.22))
			_add_pixel_rect(root, Rect2(-66, -28, 8, 26), base_color.lightened(0.08))
			_add_pixel_rect(root, Rect2(-34, -28, 8, 26), base_color.lightened(0.08))
			_add_pixel_rect(root, Rect2(-2, -28, 8, 26), base_color.lightened(0.08))
			_add_pixel_rect(root, Rect2(30, -28, 8, 26), base_color.lightened(0.08))
		"arcade":
			_add_pixel_rect(root, Rect2(-104, -112, 208, 16), base_color)
			_add_pixel_rect(root, Rect2(-96, -96, 20, 96), base_color.darkened(0.18))
			_add_pixel_rect(root, Rect2(-10, -96, 20, 96), base_color.darkened(0.18))
			_add_pixel_rect(root, Rect2(76, -96, 20, 96), base_color.darkened(0.18))
		"banner":
			_add_pixel_rect(root, Rect2(-6, -78, 12, 78), base_color.darkened(0.3))
			_add_pixel_rect(root, Rect2(6, -68, 34, 50), base_color)
		"hedge":
			_add_pixel_rect(root, Rect2(-64, -22, 128, 22), base_color.darkened(0.16))
			_add_pixel_rect(root, Rect2(-50, -38, 100, 18), base_color)
		"pillar":
			_add_pixel_rect(root, Rect2(-22, -126, 44, 126), base_color.darkened(0.16))
			_add_pixel_rect(root, Rect2(-32, -142, 64, 16), base_color)
			_add_pixel_rect(root, Rect2(-32, -12, 64, 12), base_color.darkened(0.24))
		"sanctum_frame":
			_add_pixel_rect(root, Rect2(-112, -146, 224, 18), base_color)
			_add_pixel_rect(root, Rect2(-98, -128, 24, 128), base_color.darkened(0.20))
			_add_pixel_rect(root, Rect2(74, -128, 24, 128), base_color.darkened(0.20))
			_add_pixel_rect(root, Rect2(-74, -112, 148, 98), base_color.darkened(0.08))
		"rail":
			_add_pixel_rect(root, Rect2(-140, -10, 280, 10), base_color.darkened(0.28))
			_add_pixel_rect(root, Rect2(-120, -20, 16, 10), base_color)
			_add_pixel_rect(root, Rect2(-40, -20, 16, 10), base_color)
			_add_pixel_rect(root, Rect2(40, -20, 16, 10), base_color)
			_add_pixel_rect(root, Rect2(120, -20, 16, 10), base_color)
		"spire":
			_add_pixel_rect(root, Rect2(-24, -138, 48, 138), base_color.darkened(0.18))
			_add_pixel_rect(root, Rect2(-12, -166, 24, 28), base_color)
		_:
			_add_pixel_rect(root, Rect2(-40, -40, 80, 40), base_color)
	return root


func _add_pixel_rect(parent: Node, rect: Rect2, color: Color) -> void:
	var pixel_rect := ColorRect.new()
	pixel_rect.position = rect.position
	pixel_rect.size = rect.size
	pixel_rect.color = color
	parent.add_child(pixel_rect)


func _build_theme(step_theme: Dictionary) -> Dictionary:
	var theme := DEFAULT_THEME.duplicate(true)
	for key in step_theme.keys():
		theme[key] = step_theme[key]
	return theme


func _apply_theme_colors() -> void:
	_backdrop.color = _theme_color("backdrop_color", DEFAULT_THEME["backdrop_color"])
	_distant_glow.color = _theme_color("distant_glow_color", DEFAULT_THEME["distant_glow_color"])
	_far_wall.color = _theme_color("far_wall_color", DEFAULT_THEME["far_wall_color"])
	_main_gate.color = _theme_color("main_gate_color", DEFAULT_THEME["main_gate_color"])
	_gate_seam.color = _theme_color("gate_seam_color", DEFAULT_THEME["gate_seam_color"])
	_ground.color = _theme_color("ground_color", DEFAULT_THEME["ground_color"])
	_road_stripe.color = _theme_color("road_stripe_color", DEFAULT_THEME["road_stripe_color"])
	_update_procedural_backdrop_visibility()


func _theme_float(key: String, fallback: float) -> float:
	return float(_map_theme.get(key, fallback))


func _theme_color(key: String, fallback: Color) -> Color:
	var value: Variant = _map_theme.get(key, fallback)
	if value is Color:
		return value
	if value is String:
		return Color.from_string(str(value), fallback)
	if value is Array and value.size() >= 3:
		var alpha := 1.0
		if value.size() >= 4:
			alpha = float(value[3])
		return Color(float(value[0]), float(value[1]), float(value[2]), alpha)
	return fallback


func _configure_background_image() -> void:
	_background_image.texture = null
	_background_image.visible = false
	_background_image_size = Vector2.ZERO
	_background_image_rect = Rect2()
	_update_procedural_backdrop_visibility()
	if _background_image_path.is_empty():
		return
	var texture: Texture2D = load(_background_image_path)
	if texture == null:
		return
	_background_image.texture = texture
	_background_image.visible = true
	_background_image_size = texture.get_size()
	_update_procedural_backdrop_visibility()


func _update_procedural_backdrop_visibility() -> void:
	var uses_image := _uses_background_image()
	_distant_glow.visible = not uses_image
	_far_wall.visible = not uses_image
	_main_gate.visible = not uses_image and bool(_map_theme.get("show_main_gate", true))
	_gate_seam.visible = _main_gate.visible
	_ground.visible = not uses_image
	_road_stripe.visible = not uses_image and bool(_map_theme.get("show_road_stripe", true))


func _update_background_image_layout(viewport_size: Vector2) -> void:
	if not _uses_background_image():
		_background_image_rect = Rect2()
		return
	var image_size := _background_image_size
	var minimum_fill_scale := maxf(viewport_size.x / image_size.x, viewport_size.y / image_size.y)
	var configured_scale := _theme_float("background_scale", 1.0)
	var scale := maxf(minimum_fill_scale, configured_scale)
	var draw_size := image_size * scale
	var draw_position := Vector2.ZERO
	_background_image.position = draw_position
	_background_image.size = draw_size
	_background_image_rect = Rect2(draw_position, draw_size)


func _uses_background_image() -> bool:
	return _background_image.visible and _background_image_size != Vector2.ZERO


func _map_to_screen_position(data: Dictionary, scale_vector: Vector2, ground_top: float) -> Vector2:
	if _uses_background_image():
		return Vector2(
			_background_image_rect.position.x + float(data.get("x", 0.0)) * _background_image_rect.size.x / maxf(_background_image_size.x, 1.0),
			_background_image_rect.position.y + float(data.get("y", 0.0)) * _background_image_rect.size.y / maxf(_background_image_size.y, 1.0)
		)
	return Vector2(
		float(data.get("x", 0.0)) * scale_vector.x,
		ground_top - (540.0 - float(data.get("y", 0.0))) * scale_vector.y
	)


func _update_camera_limits() -> void:
	if not is_instance_valid(_camera):
		return
	if _uses_background_image():
		_camera.limit_left = int(floor(_background_image_rect.position.x))
		_camera.limit_top = int(floor(_background_image_rect.position.y))
		_camera.limit_right = int(ceil(_background_image_rect.position.x + _background_image_rect.size.x))
		_camera.limit_bottom = int(ceil(_background_image_rect.position.y + _background_image_rect.size.y))
		return

	var viewport_size := get_viewport_rect().size
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(ceil(viewport_size.x))
	_camera.limit_bottom = int(ceil(viewport_size.y))


func _toggle_clean_view() -> void:
	_clean_view = not _clean_view
	_top_panel.visible = not _clean_view
	_bottom_panel.visible = not _clean_view and not _dialog_open
	_event_panel.visible = _dialog_open and not _clean_view
	if _clean_view:
		get_viewport().gui_release_focus()
	elif _dialog_open:
		_event_continue_button.grab_focus()


func _format_rich_text(text: String) -> String:
	var formatted := text
	formatted = formatted.replace("[b]", "[color=#e3c58a]")
	formatted = formatted.replace("[/b]", "[/color]")
	return formatted
