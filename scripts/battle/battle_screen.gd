extends Control

signal battle_finished(victory: bool, updated_player: Dictionary)

const SAFE_SPIRIT_COLOR := Color("78c4d4")
const DANGER_SPIRIT_COLOR := Color("d47878")
const OVERLOAD_SPIRIT_COLOR := Color("d4a978")
const PLAYER_BODY_COLOR := Color(0.164706, 0.172549, 0.227451, 1.0)
const PLAYER_HEAD_COLOR := Color(0.819608, 0.831373, 0.870588, 1.0)
const PLAYER_ACCENT_COLOR := Color(0.47451, 0.498039, 0.603922, 1.0)
const ENEMY_BODY_COLOR := Color(0.203922, 0.180392, 0.2, 1.0)
const ENEMY_HEAD_COLOR := Color(0.792157, 0.772549, 0.741176, 1.0)
const ENEMY_ACCENT_COLOR := Color(0.47451, 0.392157, 0.380392, 1.0)
const BOSS_BODY_COLOR := Color(0.211765, 0.14902, 0.25098, 1.0)
const BOSS_HEAD_COLOR := Color(0.854902, 0.835294, 0.898039, 1.0)
const BOSS_ACCENT_COLOR := Color(0.592157, 0.486275, 0.701961, 1.0)

@onready var _battle_name_label: Label = %BattleNameLabel
@onready var _status_label: RichTextLabel = %StatusLabel
@onready var _player_label: RichTextLabel = %PlayerLabel
@onready var _enemy_label: RichTextLabel = %EnemyLabel
@onready var _log_label: RichTextLabel = %LogLabel
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _battlefield_root: Control = %BattlefieldRoot
@onready var _battlefield_glow: ColorRect = %BattlefieldGlow
@onready var _battlefield_wall: ColorRect = %BattlefieldWall
@onready var _battlefield_floor: ColorRect = %BattlefieldFloor
@onready var _battlefield_stripe: ColorRect = %BattlefieldStripe
@onready var _player_portrait_root: Control = %PlayerPortraitRoot
@onready var _player_body: ColorRect = %PlayerBody
@onready var _player_head: ColorRect = %PlayerHead
@onready var _player_accent: ColorRect = %PlayerAccent
@onready var _player_sigil: Label = %PlayerSigil
@onready var _player_flash: ColorRect = %PlayerFlash
@onready var _enemy_formation_root: Control = %EnemyFormationRoot
@onready var _enemy_formation: HBoxContainer = %EnemyFormation
@onready var _physical_attack_button: Button = %PhysicalAttackButton
@onready var _spirit_attack_button: Button = %SpiritAttackButton
@onready var _skill_one_button: Button = %SkillOneButton
@onready var _skill_two_button: Button = %SkillTwoButton
@onready var _skill_three_button: Button = %SkillThreeButton

var _battle_data: Dictionary = {}
var _player: Dictionary = {}
var _enemies: Array = []
var _battle_over := false
var _turn_locked := false
var _log_lines: PackedStringArray = []
var _player_origin := Vector2.ZERO
var _enemy_actors: Array[Dictionary] = []


func _ready() -> void:
	_player_origin = _player_portrait_root.position
	_style_action_buttons()


func setup(encounter: Dictionary, player_data: Dictionary) -> void:
	if not is_node_ready():
		await ready

	_battle_data = encounter.duplicate(true)
	_player = player_data.duplicate(true)
	_enemies = []
	_battle_over = false
	_turn_locked = false
	_log_lines = PackedStringArray()
	_player_portrait_root.position = _player_origin
	_apply_player_style()
	_player_flash.color.a = 0.0

	for enemy_data in encounter.get("enemies", []):
		var enemy: Dictionary = enemy_data.duplicate(true)
		enemy["cage_marks"] = 0
		enemy["sealed_turns_left"] = 0
		enemy["isolated_turns_left"] = 0
		enemy["weakened_turns_left"] = 0
		_enemies.append(enemy)

	_rebuild_enemy_formation()
	_apply_battlefield_style()
	_battle_name_label.text = str(encounter.get("name", "战斗"))
	_feedback_label.text = "对峙开始"
	_feedback_label.modulate = Color(0.95, 0.88, 0.78, 1.0)
	_set_action_button_text(_physical_attack_button, str(_player.get("physical_attack_name", "囚印")), -1)
	_set_action_button_text(_spirit_attack_button, str(_player.get("spirit_attack_name", "灵击")), int(_player.get("spirit_attack_cost", 0)))
	_set_action_button_text(_skill_one_button, str(_player.get("skill_one_name", "缄束")), int(_player.get("skill_one_cost", 0)))
	_set_action_button_text(_skill_two_button, str(_player.get("skill_two_name", "永隔之域")), int(_player.get("skill_two_cost", 0)))
	_set_action_button_text(_skill_three_button, str(_player.get("skill_three_name", "囚笼收拢")), int(_player.get("skill_three_cost", 0)))
	_append_log(str(encounter.get("intro_text", "")))
	_update_ui()
	call_deferred("_focus_default_action")


func _style_action_buttons() -> void:
	for button in [_physical_attack_button, _spirit_attack_button, _skill_one_button, _skill_two_button, _skill_three_button]:
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.19, 0.17, 0.19, 1.0)
		normal.border_width_left = 2
		normal.border_width_top = 2
		normal.border_width_right = 2
		normal.border_width_bottom = 2
		normal.border_color = Color(0.48, 0.42, 0.36, 1.0)
		normal.corner_radius_top_left = 52
		normal.corner_radius_top_right = 52
		normal.corner_radius_bottom_right = 52
		normal.corner_radius_bottom_left = 52
		var hover := normal.duplicate()
		hover.bg_color = Color(0.25, 0.22, 0.25, 1.0)
		var pressed := normal.duplicate()
		pressed.bg_color = Color(0.34, 0.26, 0.22, 1.0)
		var disabled := normal.duplicate()
		disabled.bg_color = Color(0.12, 0.12, 0.12, 0.85)
		disabled.border_color = Color(0.30, 0.30, 0.30, 0.85)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("disabled", disabled)
		button.add_theme_font_size_override("font_size", 15)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _set_action_button_text(button: Button, skill_name: String, cost: int) -> void:
	var display_name := skill_name
	if skill_name == "永隔之域":
		display_name = "永隔\n之域"
	elif skill_name == "囚笼收拢":
		display_name = "囚笼\n收拢"
	elif skill_name == "缄束":
		display_name = "缄束"
	elif skill_name == "灵击":
		display_name = "灵击"
	elif skill_name == "囚印":
		display_name = "囚印"

	if cost < 0:
		button.text = display_name
	else:
		button.text = "%s\n%d" % [display_name, cost]


func _focus_default_action() -> void:
	if not _turn_locked and not _battle_over:
		_physical_attack_button.grab_focus()


func regain_focus() -> void:
	call_deferred("_focus_default_action")


func _update_ui() -> void:
	_player_label.text = _format_unit(_player)
	_enemy_label.text = _format_enemy_block()
	_log_label.text = "\n".join(_log_lines)
	if _log_lines.size() > 0:
		_log_label.scroll_to_line(_log_lines.size() - 1)
	_status_label.text = _build_status_text()
	_refresh_enemy_formation()

	var spirit: int = int(_player.get("spirit", 0))
	_physical_attack_button.disabled = _battle_over or _turn_locked
	_spirit_attack_button.disabled = _battle_over or _turn_locked or spirit < int(_player.get("spirit_attack_cost", 0))
	_skill_one_button.disabled = _battle_over or _turn_locked or spirit < int(_player.get("skill_one_cost", 0))
	_skill_two_button.disabled = _battle_over or _turn_locked or spirit < int(_player.get("skill_two_cost", 0))
	_skill_three_button.disabled = _battle_over or _turn_locked or spirit < int(_player.get("skill_three_cost", 0)) or _highest_cage_marks() < 2


func _format_unit(unit: Dictionary) -> String:
	return "[b]%s[/b]\nHP %d/%d  %s\nATK %d  DEF %d  SPD %d\n灵性 %d/%d  %s" % [
		str(unit.get("name", "单位")),
		int(unit.get("hp", 0)),
		int(unit.get("max_hp", 0)),
		_bar_text(int(unit.get("hp", 0)), int(unit.get("max_hp", 1)), 10),
		int(unit.get("atk", 0)),
		int(unit.get("def", 0)),
		int(unit.get("spd", 0)),
		int(unit.get("spirit", 0)),
		int(unit.get("max_spirit", 0)),
		_bar_text(int(unit.get("spirit", 0)), max(int(unit.get("max_spirit", 1)), 1), 8)
	]


func _format_enemy_block() -> String:
	var lines: PackedStringArray = []
	for enemy in _living_enemies():
		var status_parts: PackedStringArray = []
		var marks: int = int(enemy.get("cage_marks", 0))
		if marks > 0:
			status_parts.append("囚印 %d" % marks)
		if int(enemy.get("sealed_turns_left", 0)) > 0:
			status_parts.append("缄束")
		if int(enemy.get("isolated_turns_left", 0)) > 0:
			status_parts.append("永隔")
		if int(enemy.get("weakened_turns_left", 0)) > 0:
			status_parts.append("迟滞")

		var status_suffix: String = ""
		if not status_parts.is_empty():
			status_suffix = " | " + " / ".join(status_parts)

		lines.append("[b]%s[/b]  HP %d/%d  %s%s" % [
			str(enemy.get("name", "敌人")),
			int(enemy.get("hp", 0)),
			int(enemy.get("max_hp", 0)),
			_bar_text(int(enemy.get("hp", 0)), int(enemy.get("max_hp", 1)), 8),
			status_suffix
		])

	if lines.is_empty():
		lines.append("没有存活的敌人。")

	return "\n".join(lines)


func _build_status_text() -> String:
	var spirit: int = int(_player.get("spirit", 0))
	var max_spirit: int = max(int(_player.get("max_spirit", 1)), 1)
	var ratio: float = float(spirit) / float(max_spirit)

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
	if _battle_over or _turn_locked:
		return

	_turn_locked = true
	_update_ui()

	if _process_turn_start(_player):
		_turn_locked = false
		_update_ui()
		_end_battle(false)
		return

	var target: Dictionary = _first_enemy()
	if target.is_empty():
		_turn_locked = false
		_update_ui()
		_end_battle(true)
		return

	var feedback: String = ""
	match action:
		"physical_attack":
			feedback = "因第尔斯挥出【%s】" % str(_player.get("physical_attack_name", "囚印"))
			_use_cage_mark(target)
		"spirit_attack":
			if not _spend_player_spirit(int(_player.get("spirit_attack_cost", 0))):
				_turn_locked = false
				return
			feedback = "因第尔斯打出【%s】" % str(_player.get("spirit_attack_name", "灵击"))
			_use_spirit_attack(target)
		"skill_one":
			if not _spend_player_spirit(int(_player.get("skill_one_cost", 0))):
				_turn_locked = false
				return
			feedback = "因第尔斯落下【%s】" % str(_player.get("skill_one_name", "缄束"))
			_use_seal(target)
		"skill_two":
			if not _spend_player_spirit(int(_player.get("skill_two_cost", 0))):
				_turn_locked = false
				return
			feedback = "因第尔斯张开【%s】" % str(_player.get("skill_two_name", "永隔之域"))
			_use_isolation(target)
		"skill_three":
			if not _spend_player_spirit(int(_player.get("skill_three_cost", 0))):
				_turn_locked = false
				return
			feedback = "因第尔斯收拢【%s】" % str(_player.get("skill_three_name", "囚笼收拢"))
			_use_collapse(target)

	_cleanup_dead_enemies()
	_update_ui()
	await _animate_exchange(true, feedback, 0)

	if _living_enemies().is_empty():
		_turn_locked = false
		_update_ui()
		_end_battle(true)
		return

	var enemy_index := 0
	for enemy in _living_enemies():
		if _process_turn_start(enemy):
			enemy_index += 1
			continue

		var damage: int = _enemy_attack_damage(enemy)
		_player["hp"] = max(0, int(_player.get("hp", 0)) - damage)
		_append_log("%s 对因第尔斯造成了 %d 点伤害。" % [enemy["name"], damage])
		_update_ui()
		await _animate_exchange(false, "%s 发起了攻击" % enemy["name"], enemy_index)

		if int(_player.get("hp", 0)) <= 0:
			_turn_locked = false
			_update_ui()
			_end_battle(false)
			return

		if _enemy_can_use_skill(enemy):
			enemy["spirit"] = int(enemy.get("spirit", 0)) - int(enemy.get("skill_cost", 0))
			var skill_damage: int = max(1, int(enemy.get("atk", 0)) + int(round(float(enemy.get("spirit", 0)) * float(enemy.get("skill_power", 0.0)))) - int(_player.get("def", 0)))
			_player["hp"] = max(0, int(_player.get("hp", 0)) - skill_damage)
			_append_log("%s 强行压上灵性，再追加了 %d 点伤害。" % [enemy["name"], skill_damage])
			_update_ui()
			await _animate_skill_followup("%s 压上灵性追击" % enemy["name"], enemy_index)

			if int(_player.get("hp", 0)) <= 0:
				_turn_locked = false
				_update_ui()
				_end_battle(false)
				return

		_tick_enemy_status(enemy)
		enemy_index += 1

	_turn_locked = false
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
	var marks: int = int(target.get("cage_marks", 0))
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
	var marks: int = int(target.get("cage_marks", 0))
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
	var marks: int = int(target.get("cage_marks", 0))
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
		_update_ui()
		_end_battle(false)
		return false
	return true


func _damage_bonus_from_isolation(target: Dictionary) -> int:
	if int(target.get("isolated_turns_left", 0)) > 0:
		return int(_player.get("isolation_damage_bonus", 0))
	return 0


func _enemy_attack_damage(enemy: Dictionary) -> int:
	var effective_atk: int = int(enemy.get("atk", 0))
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

	var overload_left: int = int(unit.get("overload_turns_left", 0))
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

	_log_lines.append("• " + line)
	while _log_lines.size() > 8:
		_log_lines.remove_at(0)


func _end_battle(victory: bool) -> void:
	_battle_over = true
	_turn_locked = false
	if victory:
		_feedback_label.text = "战斗胜利"
		_feedback_label.modulate = Color(0.92, 0.94, 0.82, 1.0)
		_append_log("战斗胜利。")
	else:
		_feedback_label.text = "战斗失败"
		_feedback_label.modulate = Color(0.94, 0.74, 0.74, 1.0)
		_append_log("战斗失败。即将重新开始。")
	_update_ui()
	battle_finished.emit(victory, _player.duplicate(true))


func _apply_player_style() -> void:
	_player_body.color = PLAYER_BODY_COLOR
	_player_head.color = PLAYER_HEAD_COLOR
	_player_accent.color = PLAYER_ACCENT_COLOR
	_player_sigil.text = "因"
	_player_body.modulate = Color.WHITE
	_player_head.modulate = Color.WHITE
	_player_accent.modulate = Color.WHITE


func _rebuild_enemy_formation() -> void:
	for child in _enemy_formation.get_children():
		child.queue_free()
	_enemy_actors.clear()

	for index in range(_enemies.size()):
		var actor: Dictionary = _create_enemy_actor(index)
		_enemy_formation.add_child(actor["root"])
		_enemy_actors.append(actor)


func _create_enemy_actor(index: int) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(140, 200)

	var shadow := ColorRect.new()
	shadow.position = Vector2(20, 164)
	shadow.size = Vector2(94, 18)
	shadow.color = Color(0.0392157, 0.0431373, 0.0588235, 0.58)
	root.add_child(shadow)

	var body := ColorRect.new()
	body.position = Vector2(44, 66)
	body.size = Vector2(52, 96)
	root.add_child(body)

	var head := ColorRect.new()
	head.position = Vector2(52, 28)
	head.size = Vector2(36, 36)
	root.add_child(head)

	var accent := ColorRect.new()
	accent.position = Vector2(58, 84)
	accent.size = Vector2(24, 58)
	root.add_child(accent)

	var sigil := Label.new()
	sigil.position = Vector2(38, 92)
	sigil.size = Vector2(64, 44)
	sigil.add_theme_font_size_override("font_size", 24)
	sigil.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sigil.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(sigil)

	var flash := ColorRect.new()
	flash.position = Vector2(36, 22)
	flash.size = Vector2(68, 146)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 0.905882, 0.905882, 0)
	root.add_child(flash)

	var name_label := Label.new()
	name_label.position = Vector2(8, 182)
	name_label.size = Vector2(124, 18)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	root.add_child(name_label)

	return {
		"root": root,
		"shadow": shadow,
		"body": body,
		"head": head,
		"accent": accent,
		"sigil": sigil,
		"flash": flash,
		"name_label": name_label,
		"origin": root.position,
		"index": index
	}


func _refresh_enemy_formation() -> void:
	for index in range(_enemy_actors.size()):
		var actor: Dictionary = _enemy_actors[index]
		var root: Control = actor["root"]
		if index >= _enemies.size():
			root.visible = false
			continue

		var enemy: Dictionary = _enemies[index]
		var is_boss := str(enemy.get("name", "")).contains("所罗门")
		var body: ColorRect = actor["body"]
		var head: ColorRect = actor["head"]
		var accent: ColorRect = actor["accent"]
		var sigil: Label = actor["sigil"]
		var flash: ColorRect = actor["flash"]
		var name_label: Label = actor["name_label"]

		if is_boss:
			body.color = BOSS_BODY_COLOR
			head.color = BOSS_HEAD_COLOR
			accent.color = BOSS_ACCENT_COLOR
			sigil.text = "北"
		else:
			body.color = ENEMY_BODY_COLOR
			head.color = ENEMY_HEAD_COLOR
			accent.color = ENEMY_ACCENT_COLOR
			sigil.text = "卫"

		body.modulate = Color.WHITE
		head.modulate = Color.WHITE
		accent.modulate = Color.WHITE
		root.visible = true
		root.modulate.a = 1.0 if int(enemy.get("hp", 0)) > 0 else 0.28
		name_label.text = str(enemy.get("name", "敌人"))
		flash.color.a = 0.0 if int(enemy.get("hp", 0)) > 0 else flash.color.a


func _bar_text(current: int, maximum: int, segments: int) -> String:
	var safe_max: int = maxi(maximum, 1)
	var filled: int = int(round(float(clampi(current, 0, safe_max)) / float(safe_max) * float(segments)))
	var text: String = ""
	for index in range(segments):
		text += "■" if index < filled else "□"
	return text


func _apply_battlefield_style() -> void:
	if _enemies.size() == 1 and str((_enemies[0] as Dictionary).get("name", "")).contains("所罗门"):
		_battlefield_glow.color = Color(0.42, 0.36, 0.52, 0.16)
		_battlefield_wall.color = Color(0.15, 0.13, 0.19, 1.0)
		_battlefield_floor.color = Color(0.19, 0.17, 0.22, 1.0)
		_battlefield_stripe.color = Color(0.65, 0.63, 0.72, 0.24)
	else:
		_battlefield_glow.color = Color(0.38, 0.29, 0.22, 0.10)
		_battlefield_wall.color = Color(0.145, 0.121, 0.145, 1.0)
		_battlefield_floor.color = Color(0.20, 0.17, 0.17, 1.0)
		_battlefield_stripe.color = Color(0.47, 0.39, 0.32, 0.34)


func _animate_exchange(player_is_attacking: bool, feedback: String, enemy_index: int) -> void:
	_feedback_label.text = feedback
	_feedback_label.modulate = Color(0.95, 0.88, 0.78, 1.0)

	var actor_root: Control
	var target_root: Control
	var target_flash: ColorRect
	var actor_start: Vector2
	var target_start: Vector2
	var lunge: Vector2

	if player_is_attacking:
		actor_root = _player_portrait_root
		actor_start = _player_origin
		var actor_dict: Dictionary = _enemy_actors[min(enemy_index, _enemy_actors.size() - 1)]
		target_root = actor_dict["root"]
		target_flash = actor_dict["flash"]
		target_start = target_root.position
		lunge = Vector2(30.0, -8.0)
	else:
		var enemy_dict: Dictionary = _enemy_actors[min(enemy_index, _enemy_actors.size() - 1)]
		actor_root = enemy_dict["root"]
		target_root = _player_portrait_root
		target_flash = _player_flash
		actor_start = actor_root.position
		target_start = _player_origin
		lunge = Vector2(-30.0, -8.0)

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(actor_root, "position", actor_start + lunge, 0.15)
	tween.parallel().tween_property(target_root, "scale", Vector2(0.96, 1.04), 0.10)
	tween.parallel().tween_property(target_flash, "color:a", 0.7, 0.08)
	tween.tween_property(actor_root, "position", actor_start, 0.16)
	tween.parallel().tween_property(target_root, "position", target_start + Vector2(lunge.x * 0.32, 0.0), 0.08)
	tween.parallel().tween_property(target_flash, "color:a", 0.0, 0.14)
	tween.tween_property(target_root, "position", target_start, 0.12)
	tween.parallel().tween_property(target_root, "scale", Vector2.ONE, 0.12)
	await tween.finished


func _animate_skill_followup(feedback: String, enemy_index: int) -> void:
	_feedback_label.text = feedback
	_feedback_label.modulate = Color(0.86, 0.82, 0.96, 1.0)

	var enemy_dict: Dictionary = _enemy_actors[min(enemy_index, _enemy_actors.size() - 1)]
	var enemy_flash: ColorRect = enemy_dict["flash"]

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_player_flash, "color:a", 0.72, 0.08)
	tween.parallel().tween_property(_player_body, "modulate", Color(0.88, 0.86, 1.0, 1.0), 0.10)
	tween.parallel().tween_property(_player_head, "modulate", Color(0.92, 0.90, 1.0, 1.0), 0.10)
	tween.parallel().tween_property(_player_accent, "modulate", Color(0.78, 0.74, 1.0, 1.0), 0.10)
	tween.parallel().tween_property(enemy_flash, "color:a", 0.82, 0.10)
	tween.tween_property(_player_flash, "color:a", 0.0, 0.18)
	tween.parallel().tween_property(enemy_flash, "color:a", 0.0, 0.18)
	tween.parallel().tween_property(_player_body, "modulate", Color.WHITE, 0.18)
	tween.parallel().tween_property(_player_head, "modulate", Color.WHITE, 0.18)
	tween.parallel().tween_property(_player_accent, "modulate", Color.WHITE, 0.18)
	await tween.finished
