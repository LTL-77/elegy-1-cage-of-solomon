extends Control

signal slot_selected(slot_index: int)
signal close_requested

@onready var _title_label: Label = %TitleLabel
@onready var _slot_container: VBoxContainer = %SlotContainer
@onready var _hint_label: Label = %HintLabel
@onready var _close_button: Button = %CloseButton

var _mode := "load"


func setup(mode: String, entries: Array) -> void:
	_mode = mode
	_title_label.text = "读取存档" if mode == "load" else "保存到存档"
	_hint_label.text = "自动存档固定在第一个槽位。" if mode == "save" else "选择一个存档继续。"

	for child in _slot_container.get_children():
		child.queue_free()

	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 78)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.text = _build_slot_text(entry)
		button.disabled = _is_slot_disabled(entry)
		button.pressed.connect(_on_slot_pressed.bind(int(entry.get("slot_index", 0))))
		_slot_container.add_child(button)

	call_deferred("_focus_first_slot")


func _focus_first_slot() -> void:
	for child in _slot_container.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			return
	_close_button.grab_focus()


func _build_slot_text(entry: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("%s    %s" % [str(entry.get("title", "")), str(entry.get("play_time_text", "00:00:00"))])
	if bool(entry.get("occupied", false)):
		lines.append(str(entry.get("step_title", "未命名步骤")))
		var saved_at := str(entry.get("saved_at", ""))
		if not saved_at.is_empty():
			lines.append(saved_at)
	else:
		lines.append("空槽")
	return "\n".join(lines)


func _is_slot_disabled(entry: Dictionary) -> bool:
	var slot_index := int(entry.get("slot_index", 0))
	if _mode == "save":
		return slot_index == 0
	return not bool(entry.get("occupied", false))


func _on_slot_pressed(slot_index: int) -> void:
	slot_selected.emit(slot_index)


func _on_close_button_pressed() -> void:
	close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close_requested.emit()
		get_viewport().set_input_as_handled()
