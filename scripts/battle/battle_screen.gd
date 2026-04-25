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
@onready var _physical_attack_button: Button = %PhysicalAttackButton
@onready var _spirit_attack_button: Button = %SpiritAttackButton
@onready var _skill_one_button: Button = %SkillOneButton
@onready var _skill_two_button: Button = %SkillTwoButton
@onready var _skill_three_button: Button = %SkillThreeButton

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

	for enemy_data in encounter.get("enemies", []):
		var enemy: Dictionary = enemy_data.duplicate(true)
		enemy["cage_marks"] = 0
		enemy["sealed_turns_left"] = 0
		enemy["isolated_turns_left"] = 0
		enemy["weakened_turns_left"] = 0
		_enemies.append(enemy)

	_battle_name_label.text = str(encounter.get("name", "战斗"))
	_physical_attack_button.text = str(_player.get("physical_attack_name", "囚印"))
	_spirit_attack_button.text = "%s (%d)" % [str(_player.get("spirit_attack_name", "灵击")), int(_player.get("spirit_attack_cost", 0))]
	_skill_one_button.text = "%s (%d)" % [str(_player.get("skill_one_name", "缄束")), int(_player.get("skill_one_cost", 0))]
	_skill_two_button.text = "%s (%d)" % [str(_player.get("skill_two_name", "永隔之域")), int(_player.get("skill_two_cost", 0))]
	_skill_three_button.text = "%s (%d)" % [str(_player.get("skill_three_name", "囚笼收拢")), int(_player.get("skill_three_cost", 0))]
	_append_log(str(encounter.get("intro_text", "")))
	_update_ui()
	call_deferred("_focus_default_action")


func _focus_default_action() -> void:
	_physical_attack_button.grab_focus()


func regain_focus() -> void:
	call_deferred("_focus_default_action")


func _update_ui() -> void:
	_player_label.text = _format_unit(_player)
	_enemy_label.text = _format_enemy_block()
	_log_label.text = "\n".join(_log_lines)
	_status_label.text = _build_status_text()

	var spirit := int(_player.get("spirit", 0))
	_physical_attack_button.disabled = _battle_over
	_spirit_attack_button.disabled = _battle_over or spirit < int(_player.get("spirit_attack_cost", 0))
	_skill_one_button.disabled = _battle_over or spirit < int(_player.get("skill_one_cost", 0))
	_skill_two_button.disabled = _battle_over or spirit < int(_player.get("skill_two_cost", 0))
	_skill_three_button.disabled = _battle_over or spirit < int(_player.get("skill_three_cost", 0)) or _highest_cage_marks() < 2


func _format_unit(unit: Dictionary) -> String:
	return "[b]%s[/b]\nHP %d/%d\nATK %d  DEF %d  SPD %d\n灵性 %d/%d" % [
		str(unit.get("name", "单位")),
		int(unit.get("hp", 0)),
		int(unit.get("max_hp", 0)),
		int(unit.get("atk", 0)),
		int(unit.get("def", 0)),
		int(unit.get("spd", 0)),
		int(unit.get("spirit", 0)),
		int(unit.get("max_spirit", 0))
	]


func _format_enemy_block() -> String:
	var lines: PackedStringArray = []
	for enemy in _living_enemies():
		var status_parts: PackedStringArray = []
		var marks := int(enemy.get("cage_marks", 0))
		if marks > 0:
			status_parts.append("囚印 %d" % marks)
		if int(enemy.get("sealed_turns_left", 0)) > 0:
			status_parts.append("缄束")
		if int(enemy.get("isolated_turns_left", 0)) > 0:
			status_parts.append("永隔")
		if int(enemy.get("weakened_turns_left", 0)) > 0:
			status_parts.append("迟滞")

		var status_suffix := ""
		if not status_parts.is_empty():
			status_suffix = " | " + " / ".join(status_parts)

		lines.append("[b]%s[/b] HP %d/%d%s" % [
			str(enemy.get("name", "敌人")),
			int(enemy.get("hp", 0)),
			int(enemy.get("max_hp", 0)),
			status_suffix
		])

	if lines.is_empty():
		lines.append("没有存活的敌人。")

	return "\n".join(lines)


func _build_status_text() -> String:
	var spirit := int(_player.get("spirit", 0))
	var max_spirit: int = max(int(_player.get("max_spirit", 1)), 1)
	var ratio := float(spirit) / float(max_spirit)

	if spirit > max_spirit:
		return "[color=%s]灵性已进入崩解状态，之后的代价无法逆转。[/color]" % OVERLOAD_SPIRIT_COLOR.to_html()
	if ratio <= 0.25:
		return "[color=%s]灵性过低，再一次消耗可能直接导致枯竭。[/color]" % DANGER_SPIRIT_COLOR.to_html()
	return "[color=%s]因第尔斯仍在可控区间内，但越高的灵性也越接近崩解。[/color]" % SAFE_SPIRIT_COLOR.to_html()


func _on_physical_attack_button_pressed() -> void:
	_player_turn("physical_attack")


func _on_spirit_attack_button_pressed() -> void:
	_player_turn("spirit_attack")


func _on_skill_one_button_pressed() -> void:
	_player_turn("skill_one")


func _on_skill_two_button_pressed() -> void:
	_player_turn("skill_two")


func _on_skill_three_button_pressed() -> void:
	_player_turn("skill_three")


func _player_turn(action: String) -> void:
	if _battle_over:
		return

	if _process_turn_start(_player):
		_end_battle(false)
		return

	var target: Dictionary = _first_enemy()
	if target.is_empty():
		_end_battle(true)
		return

	match action:
		"physical_attack":
			_use_cage_mark(target)
		"spirit_attack":
			if not _spend_player_spirit(int(_player.get("spirit_attack_cost", 0))):
				return
			_use_spirit_attack(target)
		"skill_one":
			if not _spend_player_spirit(int(_player.get("skill_one_cost", 0))):
				return
			_use_seal(target)
		"skill_two":
			if not _spend_player_spirit(int(_player.get("skill_two_cost", 0))):
				return
			_use_isolation(target)
		"skill_three":
			if not _spend_player_spirit(int(_player.get("skill_three_cost", 0))):
				return
			_use_collapse(target)

	_cleanup_dead_enemies()
	if _living_enemies().is_empty():
		_end_battle(true)
		return

	for enemy in _living_enemies():
		if _process_turn_start(enemy):
			continue

		var damage: int = _enemy_attack_damage(enemy)
		_player["hp"] = max(0, int(_player.get("hp", 0)) - damage)
		_append_log("%s 对因第尔斯造成了 %d 点伤害。" % [enemy["name"], damage])

		if _enemy_can_use_skill(enemy):
			enemy["spirit"] = int(enemy.get("spirit", 0)) - int(enemy.get("skill_cost", 0))
			var skill_damage: int = max(1, int(enemy.get("atk", 0)) + int(round(float(enemy.get("spirit", 0)) * float(enemy.get("skill_power", 0.0)))) - int(_player.get("def", 0)))
			_player["hp"] = max(0, int(_player.get("hp", 0)) - skill_damage)
			_append_log("%s 强行压上灵性，再追加了 %d 点伤害。" % [enemy["name"], skill_damage])

		_tick_enemy_status(enemy)

		if int(_player.get("hp", 0)) <= 0:
			_end_battle(false)
			return

	_update_ui()
	call_deferred("_focus_default_action")


func _use_cage_mark(target: Dictionary) -> void:
	var damage: int = _basic_damage(_player, target) + _damage_bonus_from_isolation(target)
	target["hp"] = max(0, int(target.get("hp", 0)) - damage)
	target["cage_marks"] = min(3, int(target.get("cage_marks", 0)) + 1)
	_append_log("因第尔斯以【%s】斩中 %s，造成 %d 点伤害，并留下 1 层囚印。" % [
		str(_player.get("physical_attack_name", "囚印")),
		target["name"],
		damage
	])


func _use_spirit_attack(target: Dictionary) -> void:
	var spirit_bonus: int = int(_player.get("spirit_attack_power", 0)) + int(round(float(_player.get("spirit", 0)) * 0.15))
	var damage: int = max(1, spirit_bonus - int(target.get("def", 0)) + _damage_bonus_from_isolation(target))
	target["hp"] = max(0, int(target.get("hp", 0)) - damage)
	target["cage_marks"] = min(3, int(target.get("cage_marks", 0)) + 1)
	_append_log("因第尔斯以【%s】撕开 %s 的防线，造成 %d 点伤害，并再压上一层囚印。" % [
		str(_player.get("spirit_attack_name", "灵击")),
		target["name"],
		damage
	])


func _use_seal(target: Dictionary) -> void:
	var marks := int(target.get("cage_marks", 0))
	var damage: int = max(1, int(_player.get("skill_one_power", 0)) + marks - int(target.get("def", 0)) + _damage_bonus_from_isolation(target))
	target["hp"] = max(0, int(target.get("hp", 0)) - damage)
	target["sealed_turns_left"] = max(int(target.get("sealed_turns_left", 0)), int(_player.get("skill_one_seal_turns", 1)))
	if marks >= 2:
		target["weakened_turns_left"] = max(int(target.get("weakened_turns_left", 0)), 2)
		_append_log("【%s】钉住了 %s 的动作，造成 %d 点伤害，并令其陷入缄束与迟滞。" % [
			str(_player.get("skill_one_name", "缄束")),
			target["name"],
			damage
		])
	else:
		_append_log("【%s】压住了 %s 的节奏，造成 %d 点伤害，并封住了它的灵性技。" % [
			str(_player.get("skill_one_name", "缄束")),
			target["name"],
			damage
		])


func _use_isolation(target: Dictionary) -> void:
	var marks := int(target.get("cage_marks", 0))
	target["isolated_turns_left"] = max(int(target.get("isolated_turns_left", 0)), int(_player.get("skill_two_isolation_turns", 2)))
	target["sealed_turns_left"] = max(int(target.get("sealed_turns_left", 0)), 1)

	var damage := 0
	if marks >= 2:
		damage = int(_player.get("skill_two_bonus_damage", 0)) + _damage_bonus_from_isolation(target)
		target["hp"] = max(0, int(target.get("hp", 0)) - damage)
		_append_log("因第尔斯张开【%s】，把 %s 拖入只剩自己的世界，并追上 %d 点伤害。" % [
			str(_player.get("skill_two_name", "永隔之域")),
			target["name"],
			damage
		])
	else:
		_append_log("因第尔斯张开【%s】，强行切断 %s 与外界的连结。" % [
			str(_player.get("skill_two_name", "永隔之域")),
			target["name"]
		])


func _use_collapse(target: Dictionary) -> void:
	var marks := int(target.get("cage_marks", 0))
	var damage: int = int(_player.get("skill_three_bonus_damage", 0)) + marks * 2 + _damage_bonus_from_isolation(target)
	target["hp"] = max(0, int(target.get("hp", 0)) - damage)
	target["cage_marks"] = max(0, marks - 2)
	target["weakened_turns_left"] = max(int(target.get("weakened_turns_left", 0)), 1)
	_append_log("【%s】骤然收拢，撕碎了 %s 身上的囚印，造成 %d 点重伤。" % [
		str(_player.get("skill_three_name", "囚笼收拢")),
		target["name"],
		damage
	])


func _spend_player_spirit(cost: int) -> bool:
	_player["spirit"] = int(_player.get("spirit", 0)) - cost
	if int(_player.get("spirit", 0)) < 0:
		_append_log("因第尔斯透支了灵性，直接陷入枯竭。")
		_player["hp"] = 0
		_end_battle(false)
		return false
	return true


func _damage_bonus_from_isolation(target: Dictionary) -> int:
	if int(target.get("isolated_turns_left", 0)) > 0:
		return int(_player.get("isolation_damage_bonus", 0))
	return 0


func _enemy_attack_damage(enemy: Dictionary) -> int:
	var effective_atk := int(enemy.get("atk", 0))
	if int(enemy.get("weakened_turns_left", 0)) > 0:
		effective_atk -= 2
	if int(enemy.get("isolated_turns_left", 0)) > 0:
		effective_atk -= 1
	return max(1, effective_atk - int(_player.get("def", 0)))


func _enemy_can_use_skill(enemy: Dictionary) -> bool:
	if int(enemy.get("max_spirit", 0)) <= 0:
		return false
	if int(enemy.get("sealed_turns_left", 0)) > 0:
		return false
	if int(enemy.get("isolated_turns_left", 0)) > 0:
		return false
	if int(enemy.get("spirit", 0)) < int(enemy.get("skill_cost", 0)):
		return false
	return int(enemy.get("hp", 0)) <= int(enemy.get("max_hp", 0)) / 2


func _tick_enemy_status(enemy: Dictionary) -> void:
	for key in ["sealed_turns_left", "isolated_turns_left", "weakened_turns_left"]:
		var turns_left: int = int(enemy.get(key, 0))
		if turns_left > 0:
			enemy[key] = turns_left - 1


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
		var max_spirit: int = int(unit.get("max_spirit", 0))
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


func _first_enemy() -> Dictionary:
	var enemies: Array = _living_enemies()
	if enemies.is_empty():
		return {}
	return enemies.front()


func _highest_cage_marks() -> int:
	var highest := 0
	for enemy in _living_enemies():
		highest = max(highest, int(enemy.get("cage_marks", 0)))
	return highest


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
