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
	_title_label.text = str(step.get("title", "Interaction"))
	_description_label.text = str(step.get("description", ""))
	_required_inspections = int(step.get("required_inspections", 1))
	_result_label.text = "Select an interaction point."
	_continue_button.disabled = true

	for child in _options_container.get_children():
		child.queue_free()

	for option in step.get("options", []):
		var button := Button.new()
		button.text = str(option.get("label", "Option"))
		button.pressed.connect(_on_option_pressed.bind(option, button))
		_options_container.add_child(button)


func _on_option_pressed(option: Dictionary, button: Button) -> void:
	var option_id := str(option.get("id", button.text))
	_visited[option_id] = true
	button.disabled = true
	_result_label.text = str(option.get("result", ""))
	_continue_button.disabled = _visited.size() < _required_inspections


func _on_continue_button_pressed() -> void:
	completed.emit()
