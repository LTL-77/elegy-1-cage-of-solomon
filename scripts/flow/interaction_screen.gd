extends Control

signal completed

@onready var _background_image: TextureRect = %BackgroundImage
@onready var _dim_overlay: ColorRect = %DimOverlay
@onready var _panel_layer: Control = %PanelLayer
@onready var _dock_panel: PanelContainer = %DockPanel
@onready var _title_label: Label = %TitleLabel
@onready var _description_label: RichTextLabel = %DescriptionLabel
@onready var _options_container: VBoxContainer = %OptionsContainer
@onready var _result_label: RichTextLabel = %ResultLabel
@onready var _continue_button: Button = %ContinueButton

var _visited: Dictionary = {}
var _required_inspections := 1
var _background_size := Vector2.ZERO
var _clean_view := false


func _ready() -> void:
	get_viewport().size_changed.connect(_update_background_layout)
	_update_background_layout()


func setup(step: Dictionary, background_image_path: String = "") -> void:
	_visited = {}
	_required_inspections = int(step.get("required_inspections", 1))
	_clean_view = false
	_panel_layer.visible = true
	_dim_overlay.visible = true
	_title_label.text = str(step.get("title", "交互"))
	_description_label.text = _format_rich_text(str(step.get("description", "")))
	_result_label.text = "选择一个可调查的点。"
	_continue_button.disabled = true
	_set_background(background_image_path)

	for child in _options_container.get_children():
		child.queue_free()

	for option_variant in step.get("options", []):
		var option: Dictionary = option_variant
		var button := Button.new()
		button.text = str(option.get("label", "选项"))
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_on_option_pressed.bind(option, button))
		_options_container.add_child(button)

	call_deferred("_focus_first_option")


func _focus_first_option() -> void:
	for child in _options_container.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			return
	_continue_button.grab_focus()


func regain_focus() -> void:
	if _clean_view:
		return
	call_deferred("_focus_first_option")


func _on_option_pressed(option: Dictionary, button: Button) -> void:
	var option_id := str(option.get("id", button.text))
	_visited[option_id] = true
	button.disabled = true
	_result_label.text = _format_rich_text(str(option.get("result", "")))
	_continue_button.disabled = _visited.size() < _required_inspections
	_play_button_feedback(button)
	_play_panel_feedback()
	if _continue_button.disabled:
		call_deferred("_focus_first_option")
	else:
		_continue_button.grab_focus()


func _on_continue_button_pressed() -> void:
	completed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("clean_view") and not event.is_echo():
		_toggle_clean_view()
		get_viewport().set_input_as_handled()


func _toggle_clean_view() -> void:
	_clean_view = not _clean_view
	_panel_layer.visible = not _clean_view
	_dim_overlay.visible = not _clean_view
	if _clean_view:
		get_viewport().gui_release_focus()
	else:
		call_deferred("_focus_first_option")


func _set_background(background_image_path: String) -> void:
	_background_image.texture = null
	_background_image.visible = false
	_background_size = Vector2.ZERO
	if background_image_path.is_empty():
		return
	var texture: Texture2D = load(background_image_path)
	if texture == null:
		return
	_background_image.texture = texture
	_background_image.visible = true
	_background_size = texture.get_size()
	_update_background_layout()


func _update_background_layout() -> void:
	if _background_image == null:
		return
	if not _background_image.visible or _background_size == Vector2.ZERO:
		_background_image.position = Vector2.ZERO
		_background_image.size = get_viewport_rect().size
		return

	var viewport_size := get_viewport_rect().size
	var scale := maxf(viewport_size.x / _background_size.x, viewport_size.y / _background_size.y)
	var draw_size := _background_size * scale
	var draw_position := Vector2((viewport_size.x - draw_size.x) * 0.5, (viewport_size.y - draw_size.y) * 0.5)
	_background_image.position = draw_position
	_background_image.size = draw_size


func _format_rich_text(text: String) -> String:
	var formatted := text
	formatted = formatted.replace("[b]", "[color=#e3c58a]")
	formatted = formatted.replace("[/b]", "[/color]")
	return formatted


func _play_button_feedback(button: Button) -> void:
	if button == null:
		return
	button.scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.04, 1.04), 0.06)
	tween.tween_property(button, "scale", Vector2.ONE, 0.08)


func _play_panel_feedback() -> void:
	if _dock_panel == null:
		return
	var base_position := _dock_panel.position
	var tween := create_tween()
	tween.tween_property(_dock_panel, "position", base_position + Vector2(10.0, 0.0), 0.05)
	tween.tween_property(_dock_panel, "position", base_position + Vector2(-6.0, 0.0), 0.06)
	tween.tween_property(_dock_panel, "position", base_position, 0.05)
