extends Control

signal battle_finished(victory: bool, updated_player: Dictionary)

const SAFE_SPIRIT_COLOR := Color("78c4d4")
const DANGER_SPIRIT_COLOR := Color("d47878")
const OVERLOAD_SPIRIT_COLOR := Color("d4a978")

@onready var _battle_name_label: Label = %BattleNameLabel
@onready var _status_label: RichTextLabel = %StatusLabel
@onready var _player_label: RichTextLabel = %PlayerLabel
@onready var _enemy_label: RichTextLabel = %EnemyLabel
@onready var _log_label: RichTextLabel = %LogLabel
@onready var _attack_button: Button = %AttackButton
@onready var _skill_button: Button = %SkillButton
@onready var _focus_button: Button = %FocusButton

var _battle_data: Dictionary = {}
var _player: Dictionary = {}
var _enemies: Array = []
var _battle_over := false
var _log_lines: PackedStringArray = []


func setup(encounter: Dictionary, player_data: Dictionary) -> void:
	_battle_data = encounter.duplicate(true)
	_player = player_data.duplicate(true)
	_enemies = []
	_battle_over = false
	_log_lines = PackedStringArray()

	for enemy in encounter.get("enemies", []):
		_enemies.append(enemy.duplicate(true))

	_battle_name_label.text = str(encounter.get("name", "Battle"))
	_append_log(str(encounter.get("intro_text", "")))
	_update_ui()


func _update_ui() -> void:
	_player_label.text = _format_unit(_player)
	_enemy_label.text = _format_enemy_block()
	_log_label.text = "\n".join(_log_lines)
	_status_label.text = _build_status_text()

	var skill_cost := int(_player.get("skill_cost", 0))
	_skill_button.disabled = _battle_over or int(_player.get("spirit", 0)) - skill_cost < 0
	_attack_button.disabled = _battle_over
	_focus_button.disabled = _battle_over


func _format_unit(unit: Dictionary) -> String:
	var spirit := int(unit.get("spirit", 0))
	var max_spirit := int(unit.get("max_spirit", 0))
	return "[b]%s[/b]\nHP %d/%d\nATK %d  DEF %d  SPD %d\nSpirit %d/%d" % [
		str(unit.get("name", "Unit")),
		int(unit.get("hp", 0)),
		int(unit.get("max_hp", 0)),
		int(unit.get("atk", 0)),
		int(unit.get("def", 0)),
		int(unit.get("spd", 0)),
		spirit,
		max_spirit
	]


func _format_enemy_block() -> String:
	var lines: PackedStringArray = []
	for enemy in _living_enemies():
		lines.append("[b]%s[/b] HP %d/%d  SPD %d" % [
			str(enemy.get("name", "Enemy")),
			int(enemy.get("hp", 0)),
			int(enemy.get("max_hp", 0)),
			int(enemy.get("spd", 0))
		])

	if lines.is_empty():
		lines.append("没有存活的敌人。")

	return "\n".join(lines)


func _build_status_text() -> String:
	var spirit := int(_player.get("spirit", 0))
	var max_spirit: int = max(int(_player.get("max_spirit", 1)), 1)
	var threshold_ratio := float(spirit) / float(max_spirit)

	if spirit > max_spirit:
		return "[color=%s]灵性已进入崩解状态，之后的代价无法逆转。[/color]" % OVERLOAD_SPIRIT_COLOR.to_html()
	if threshold_ratio <= 0.25:
		return "[color=%s]灵性过低，再一次消耗可能直接导致枯竭。[/color]" % DANGER_SPIRIT_COLOR.to_html()
	return "[color=%s]灵性仍在安全区间内。[/color]" % SAFE_SPIRIT_COLOR.to_html()


func _on_attack_button_pressed() -> void:
	_player_turn("attack")


func _on_skill_button_pressed() -> void:
	_player_turn("skill")


func _on_focus_button_pressed() -> void:
	_player_turn("focus")


func _player_turn(action: String) -> void:
	if _battle_over:
		return

	if _process_turn_start(_player):
		_end_battle(false)
		return

	match action:
		"attack":
			var target: Dictionary = _living_enemies().front()
			if target != null:
				var damage: int = _basic_damage(_player, target)
				target["hp"] = max(0, int(target.get("hp", 0)) - damage)
				_append_log("%s 对 %s 造成了 %d 点伤害。" % [_player["name"], target["name"], damage])
		"skill":
			var skill_cost := int(_player.get("skill_cost", 0))
			_player["spirit"] = int(_player.get("spirit", 0)) - skill_cost
			if int(_player.get("spirit", 0)) < 0:
				_append_log("%s 透支了灵性，直接陷入枯竭。" % _player["name"])
				_player["hp"] = 0
				_end_battle(false)
				return

			var skill_target: Dictionary = _living_enemies().front()
			if skill_target != null:
				var spirit_bonus: int = int(round(float(_player.get("spirit", 0)) * float(_player.get("skill_power", 0.0))))
				var damage: int = max(1, int(_player.get("atk", 0)) + spirit_bonus - int(skill_target.get("def", 0)))
				skill_target["hp"] = max(0, int(skill_target.get("hp", 0)) - damage)
				_append_log("%s 对 %s 施展灵性技，造成 %d 点伤害。" % [_player["name"], skill_target["name"], damage])
		"focus":
			_player["spirit"] = min(int(_player.get("max_spirit", 0)), int(_player.get("spirit", 0)) + 5)
			_append_log("%s 收束心神，恢复了灵性。" % _player["name"])

	_cleanup_dead_enemies()
	if _living_enemies().is_empty():
		_end_battle(true)
		return

	for enemy in _living_enemies():
		if _process_turn_start(enemy):
			continue

		var damage: int = _basic_damage(enemy, _player)
		_player["hp"] = max(0, int(_player.get("hp", 0)) - damage)
		_append_log("%s 对 %s 造成了 %d 点伤害。" % [enemy["name"], _player["name"], damage])

		if int(enemy.get("max_spirit", 0)) > 0 and int(enemy.get("spirit", 0)) >= int(enemy.get("skill_cost", 0)) and int(enemy.get("hp", 0)) <= int(enemy.get("max_hp", 0)) / 2:
			enemy["spirit"] = int(enemy.get("spirit", 0)) - int(enemy.get("skill_cost", 0))
			var skill_damage: int = max(1, int(enemy.get("atk", 0)) + int(round(float(enemy.get("spirit", 0)) * float(enemy.get("skill_power", 0.0)))) - int(_player.get("def", 0)))
			_player["hp"] = max(0, int(_player.get("hp", 0)) - skill_damage)
			_append_log("%s 以灵性技追击，造成 %d 点伤害。" % [enemy["name"], skill_damage])

		if int(_player.get("hp", 0)) <= 0:
			_end_battle(false)
			return

	_update_ui()


func _process_turn_start(unit: Dictionary) -> bool:
	if int(unit.get("hp", 0)) <= 0:
		return true

	var overload_left := int(unit.get("overload_turns_left", 0))
	if overload_left > 0:
		overload_left -= 1
		unit["overload_turns_left"] = overload_left
		_append_log("%s 已进入崩解，距离死亡还剩 %d 回合。" % [unit["name"], overload_left])
		if overload_left <= 0:
			unit["hp"] = 0
			_append_log("%s 在崩解中彻底瓦解。" % unit["name"])
			return true
	else:
		var max_spirit := int(unit.get("max_spirit", 0))
		if max_spirit > 0:
			unit["spirit"] = min(max_spirit, int(unit.get("spirit", 0)) + int(unit.get("spirit_recovery", 0)))

	if int(unit.get("spirit", 0)) > int(unit.get("max_spirit", 0)):
		unit["overload_turns_left"] = int(unit.get("overload_turns", 2))
		_append_log("%s 的灵性越界，进入崩解。" % unit["name"])

	return false


func _basic_damage(attacker: Dictionary, defender: Dictionary) -> int:
	return max(1, int(attacker.get("atk", 0)) - int(defender.get("def", 0)))


func _living_enemies() -> Array:
	return _enemies.filter(func(enemy: Dictionary) -> bool: return int(enemy.get("hp", 0)) > 0)


func _cleanup_dead_enemies() -> void:
	for enemy in _enemies:
		if int(enemy.get("hp", 0)) == 0 and not enemy.get("defeated_logged", false):
			enemy["defeated_logged"] = true
			_append_log("%s 倒下了。" % enemy["name"])


func _append_log(line: String) -> void:
	if line.is_empty():
		return

	_log_lines.append(line)
	while _log_lines.size() > 8:
		_log_lines.remove_at(0)


func _end_battle(victory: bool) -> void:
	_battle_over = true
	if victory:
		_append_log("战斗胜利。")
	else:
		_append_log("战斗失败。即将重新开始。")
	_update_ui()
	battle_finished.emit(victory, _player.duplicate(true))
