extends Control

signal close_requested

@onready var _character_list: ItemList = %CharacterList
@onready var _name_label: Label = %NameLabel
@onready var _profession_label: Label = %ProfessionLabel
@onready var _blessing_label: Label = %BlessingLabel
@onready var _understanding_label: Label = %UnderstandingLabel
@onready var _inversion_label: Label = %InversionLabel
@onready var _portrait_label: RichTextLabel = %PortraitLabel
@onready var _summary_label: RichTextLabel = %SummaryLabel
@onready var _bio_label: RichTextLabel = %BioLabel
@onready var _stats_label: RichTextLabel = %StatsLabel
@onready var _hidden_label: RichTextLabel = %HiddenLabel
@onready var _echo_list: ItemList = %EchoList
@onready var _echo_detail_label: RichTextLabel = %EchoDetailLabel
@onready var _close_button: Button = %CloseButton

var _characters: Array[Dictionary] = []
var _current_index := 0
var _current_echo_entries: Array[Dictionary] = []


func setup(characters: Array, selected_character_id: String = "") -> void:
	_characters.clear()
	for character in characters:
		var character_dict: Dictionary = character
		_characters.append(character_dict.duplicate(true))

	_character_list.clear()
	for character in _characters:
		_character_list.add_item(str(character.get("name", "未命名角色")))

	_current_index = _resolve_selected_index(selected_character_id)
	if not _characters.is_empty():
		_character_list.select(_current_index)
		_show_character(_current_index)

	call_deferred("_focus_character_list")


func _resolve_selected_index(selected_character_id: String) -> int:
	if selected_character_id.is_empty():
		return 0

	for index in range(_characters.size()):
		if str(_characters[index].get("id", "")) == selected_character_id:
			return index

	return 0


func _focus_character_list() -> void:
	if _character_list.get_item_count() > 0:
		_character_list.grab_focus()
	else:
		_close_button.grab_focus()


func _show_character(index: int) -> void:
	if index < 0 or index >= _characters.size():
		return

	_current_index = index
	var character := _characters[index]
	var understanding: Dictionary = character.get("understanding", {})
	var visible_stats: Dictionary = character.get("visible_stats", {})
	var hidden_states: Dictionary = character.get("hidden_states", {})
	var blessings: Array = character.get("blessings", [])
	var understanding_value := int(understanding.get("current_value", 0))
	var stage_text := _stage_text_for_value(understanding_value)

	_name_label.text = str(character.get("name", "未命名角色"))
	_profession_label.text = "职业：%s" % str(character.get("profession", "未记录"))
	_blessing_label.text = _format_blessings(bool(character.get("has_blessing", false)), blessings)
	_understanding_label.text = "当前理解：%d / 100  ·  %s" % [understanding_value, stage_text]
	_inversion_label.text = "是否已反演：%s" % ("是" if bool(understanding.get("is_inverted", false)) else "否")
	_portrait_label.text = "[b]立绘[/b]\n%s" % str(character.get("portrait_note", "暂无立绘信息。"))
	_summary_label.text = str(character.get("summary", ""))
	_bio_label.text = str(character.get("biography", ""))
	_stats_label.text = _format_visible_stats(visible_stats)
	_hidden_label.text = _format_hidden_states(understanding, hidden_states, stage_text)
	_rebuild_echo_archive(character, understanding_value)


func _format_blessings(has_blessing: bool, blessings: Array) -> String:
	if not has_blessing:
		return "眷顾：无"

	return "眷顾：%s" % " / ".join(blessings)


func _format_visible_stats(visible_stats: Dictionary) -> String:
	return "[b]明面属性[/b]\n生命 %d\n物攻 %d\n灵性 %d\n物防 %d\n速度 %d" % [
		int(visible_stats.get("life", 0)),
		int(visible_stats.get("physical_attack", 0)),
		int(visible_stats.get("spirituality", 0)),
		int(visible_stats.get("physical_defense", 0)),
		int(visible_stats.get("speed", 0))
	]


func _format_hidden_states(understanding: Dictionary, hidden_states: Dictionary, stage_text: String) -> String:
	var understanding_lock_text := "可继续提升"
	if bool(understanding.get("is_inverted", false)):
		understanding_lock_text = "角色已被反演，理解已锁定"

	return "[b]隐藏属性状态[/b]\n理解阶段：%s\n理解状态：%s\n罪业：%s\n%s\n反演阈值：%s\n理解提示：%s" % [
		stage_text,
		understanding_lock_text,
		str(hidden_states.get("sin_status", "未知")),
		str(hidden_states.get("sin_hint", "")),
		str(hidden_states.get("inversion_threshold_hint", "隐藏")),
		str(hidden_states.get("understanding_hint", "暂无补充"))
	]


func _rebuild_echo_archive(character: Dictionary, understanding_value: int) -> void:
	_current_echo_entries.clear()
	_echo_list.clear()

	for echo in character.get("echoes", []):
		var echo_dict: Dictionary = echo
		var unlock_value := int(echo_dict.get("unlock_value", 0))
		var unlocked := understanding_value >= unlock_value
		var display_name := "%s%s" % [
			"已解锁 · " if unlocked else "未解锁 · ",
			str(echo_dict.get("title", "未命名回响"))
		]
		_echo_list.add_item(display_name)
		_current_echo_entries.append({
			"type": "echo",
			"title": str(echo_dict.get("title", "未命名回响")),
			"unlock_value": unlock_value,
			"unlocked": unlocked,
			"summary": str(echo_dict.get("summary", "")),
			"sin": str(echo_dict.get("sin", "")),
			"story_lines": echo_dict.get("story_lines", [])
		})

	var cg_unlock: Dictionary = character.get("cg_unlock", {})
	if not cg_unlock.is_empty():
		var cg_unlock_value := int(cg_unlock.get("unlock_value", 100))
		var cg_unlocked := understanding_value >= cg_unlock_value
		_echo_list.add_item("%s角色 CG · %s" % [
			"已解锁 · " if cg_unlocked else "未解锁 · ",
			str(cg_unlock.get("title", "未命名 CG"))
		])
		_current_echo_entries.append({
			"type": "cg",
			"title": str(cg_unlock.get("title", "未命名 CG")),
			"unlock_value": cg_unlock_value,
			"unlocked": cg_unlocked,
			"summary": str(cg_unlock.get("summary", "")),
			"sin": str(cg_unlock.get("sin", "")),
			"story_lines": cg_unlock.get("story_lines", [])
		})

	if _echo_list.get_item_count() > 0:
		_echo_list.select(0)
		_show_echo_entry(0)
	else:
		_echo_detail_label.text = "暂无回响记录。"


func _show_echo_entry(index: int) -> void:
	if index < 0 or index >= _current_echo_entries.size():
		return

	var entry := _current_echo_entries[index]
	var unlocked := bool(entry.get("unlocked", false))
	var lines: PackedStringArray = []
	lines.append("[b]%s[/b]" % str(entry.get("title", "未命名条目")))
	lines.append("解锁条件：理解 %d" % int(entry.get("unlock_value", 0)))
	lines.append("")

	if unlocked:
		lines.append(str(entry.get("summary", "")))
		lines.append("")
		for story_line in entry.get("story_lines", []):
			lines.append(str(story_line))
		lines.append("")
		lines.append("罪业：%s" % str(entry.get("sin", "")))
	else:
		lines.append("尚未解锁。")

	_echo_detail_label.text = "\n".join(lines).strip_edges()


func _stage_text_for_value(value: int) -> String:
	if value >= 100:
		return "阶段五：忠诚的背面"
	if value >= 80:
		return "阶段四：未留下的影"
	if value >= 60:
		return "阶段三：被信任者"
	if value >= 40:
		return "阶段二：自囚之笼"
	if value >= 20:
		return "阶段一：孤身之人"
	return "阶段零：未建立理解"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close_requested.emit()
		get_viewport().set_input_as_handled()


func _on_character_list_item_selected(index: int) -> void:
	_show_character(index)


func _on_echo_list_item_selected(index: int) -> void:
	_show_echo_entry(index)


func _on_close_button_pressed() -> void:
	close_requested.emit()
