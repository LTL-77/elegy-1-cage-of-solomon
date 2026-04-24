extends Control

signal completed

@onready var _title_label: Label = %TitleLabel
@onready var _body_label: RichTextLabel = %BodyLabel
@onready var _continue_button: Button = %ContinueButton

var _lines: Array = []
var _line_index := 0


func setup(title: String, lines: Array) -> void:
	_title_label.text = title
	_lines = lines.duplicate()
	_line_index = 0
	_show_current_line()


func _show_current_line() -> void:
	if _line_index >= _lines.size():
		completed.emit()
		return

	_body_label.text = str(_lines[_line_index])
	_continue_button.text = "Continue"

	if _line_index == _lines.size() - 1:
		_continue_button.text = "Proceed"


func _on_continue_button_pressed() -> void:
	_line_index += 1
	_show_current_line()
