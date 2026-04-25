extends Control

signal completed

@onready var _title_label: Label = %TitleLabel
@onready var _description_label: RichTextLabel = %DescriptionLabel
@onready var _options_container: VBoxContainer = %OptionsContainer
@onready var _result_label: RichTextLabel = %ResultLabel
@onready var _continue_button: Button = %ContinueButton

var _visited: Dictionary = {}
var _required_inspections := 1


func setup(step: Dictionary) -> void:
	_visited = {}
	_title_label.text = str(step.get("title", "互动"))
	_description_label.text = str(step.get("description", ""))
	_required_inspections = int(step.get("required_inspections", 1))
	_result_label.text = "选择一个可调查的点。"
	_continue_button.disabled = true

	for child in _options_container.get_children():
		child.queue_free()

	for option in step.get("options", []):
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
	call_deferred("_focus_first_option")


func _on_option_pressed(option: Dictionary, button: Button) -> void:
	var option_id := str(option.get("id", button.text))
	_visited[option_id] = true
	button.disabled = true
	_result_label.text = str(option.get("result", ""))
	_continue_button.disabled = _visited.size() < _required_inspections
	if _continue_button.disabled:
		call_deferred("_focus_first_option")
	else:
		_continue_button.grab_focus()


func _on_continue_button_pressed() -> void:
	completed.emit()
