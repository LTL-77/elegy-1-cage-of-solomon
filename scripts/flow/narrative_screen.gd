extends Control

signal completed

@onready var _background_image: TextureRect = %BackgroundImage
@onready var _dim_overlay: ColorRect = %DimOverlay
@onready var _panel_layer: Control = %PanelLayer
@onready var _title_label: Label = %TitleLabel
@onready var _body_label: RichTextLabel = %BodyLabel
@onready var _continue_button: Button = %ContinueButton

var _lines: Array = []
var _line_index := 0
var _background_size := Vector2.ZERO
var _clean_view := false


func _ready() -> void:
	get_viewport().size_changed.connect(_update_background_layout)
	_update_background_layout()


func setup(title: String, lines: Array, background_image_path: String = "") -> void:
	_title_label.text = title
	_lines = lines.duplicate()
	_line_index = 0
	_clean_view = false
	_panel_layer.visible = true
	_set_background(background_image_path)
	_show_current_line()
	call_deferred("_focus_continue")


func _focus_continue() -> void:
	if not _clean_view:
		_continue_button.grab_focus()


func regain_focus() -> void:
	call_deferred("_focus_continue")


func _show_current_line() -> void:
	if _line_index >= _lines.size():
		completed.emit()
		return

	_body_label.text = _format_rich_text(str(_lines[_line_index]))
	_continue_button.text = "继续"
	if _line_index == _lines.size() - 1:
		_continue_button.text = "进入下一步"


func _on_continue_button_pressed() -> void:
	_line_index += 1
	_show_current_line()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("clean_view") and not event.is_echo():
		_toggle_clean_view()
		get_viewport().set_input_as_handled()


func _toggle_clean_view() -> void:
	_clean_view = not _clean_view
	_panel_layer.visible = not _clean_view
	_dim_overlay.visible = not _clean_view
	if not _clean_view:
		call_deferred("_focus_continue")
	else:
		get_viewport().gui_release_focus()


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
