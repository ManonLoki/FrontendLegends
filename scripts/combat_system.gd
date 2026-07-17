extends Node

const COMBAT_RULES := preload("res://scripts/combat/combat_rules.gd")
const COMBAT_STATUS := preload("res://scripts/combat/combat_status.gd")
const ENEMY_AI := preload("res://scripts/combat/enemy_ai.gd")
const ULTIMATE_ACTIONS := preload("res://scripts/combat/ultimate_actions.gd")
const PLAYER_RECOVERY_ACTIONS := preload("res://scripts/combat/player_recovery_actions.gd")
var rules := COMBAT_RULES.new()
@onready var status_effects := COMBAT_STATUS.new(self)
@onready var enemy_ai := ENEMY_AI.new(self)
@onready var ultimate_actions := ULTIMATE_ACTIONS.new(self)
@onready var player_recovery := PLAYER_RECOVERY_ACTIONS.new(self)

const FLEE_BASE := 0.40
const FLEE_PER_AGILITY := 0.03

## 招架招式减伤：基础 15%，每高出该招式解锁等级 1 级再加 1%，封顶 35%。
const PARRY_REDUCE_BASE := 0.15
const PARRY_REDUCE_PER_LEVEL := 0.01
const PARRY_REDUCE_CAP := 0.35

const WEAKNESS_DAMAGE_MULT := 1.30
const NPC_FORCE_USE_RATE := 0.45
const NPC_FORCE_INNER_POWER_RATIO := 0.25
## 玩家与 NPC 触发进攻招式时共用的命中加成。
const MOVE_HIT_BONUS := 0.12

## initial_player_hp 记录开战体力，结算时按净损失的 15%、功法减免和当场重伤计算伤势，
## 再以真实体力上限的 20% 封顶，避免治疗或临时削上限重复放大惩罚。
func create_session(enemy_id: String, lethal: bool = true) -> Dictionary:
	return rules.create_session(enemy_id, lethal)

## 执行玩家攻击并依次结算招式、加力、装备、状态和战报。
func player_attack(session: Dictionary, turn_started := false, damage_scale := 1.0, hit_bonus_extra := 0.0, attack_power_bonus := 0.0, action_label := "出手", allow_attack_move := true) -> Dictionary:
	var turn_check := {"can_act": true, "message": ""} if turn_started else start_turn(session, "player")
	if not turn_check.can_act:
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var enemy_attributes: Dictionary = rules.npc_combat_attributes(session.enemy)
	var player_attributes: Dictionary = rules.player_combat_attributes()
	var attack_moves: Array = SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "attack") if allow_attack_move else []
	var attack_move: Dictionary = {}
	if not attack_moves.is_empty() and randf() < rules.move_trigger_rate("attack", attack_moves.size()):
		attack_move = _weighted_pick(attack_moves)
	var move_hit_bonus := MOVE_HIT_BONUS if not attack_move.is_empty() else 0.0
	var attack_verb := "使出【%s】" % attack_move.get("name", "招式") if not attack_move.is_empty() else action_label
	var enemy_equipment := _npc_equipment_bonus(session.enemy)
	var enemy_skill_bonus := _npc_combat_bonus(session.enemy)
	var player_skill_bonus := SkillSystem.combat_bonus()
	var equipment := InventorySystem.equipment_bonus()
	var defense := GameState.defense_base(float(enemy_attributes.get("constitution", 0))) + float(enemy_skill_bonus.get("defense", 0)) + float(enemy_equipment.get("defense", 0))
	var result: Dictionary = GameState.resolve_attack(_player_attack_power() + attack_power_bonus, player_attributes, enemy_attributes, defense, (float(player_skill_bonus.get("hit", 0)) + float(equipment.get("hit", 0))) * 0.01 + move_hit_bonus + hit_bonus_extra, (float(enemy_skill_bonus.get("dodge", 0)) + float(enemy_equipment.get("dodge", 0))) * 0.01, (float(enemy_skill_bonus.get("parry", 0)) + float(enemy_equipment.get("parry", 0))) * 0.01, float(equipment.get("crit", 0)) * 0.01)
	if not result.hit:
		session.log.append("%s%s，%s身形一晃避开了。" % [_player_name(), attack_verb, session.enemy.get("displayName", "敌人")])
		return result
	var enemy_dodge_move := _npc_move(session.enemy, "dodge")
	if not enemy_dodge_move.is_empty():
		session.log.append("%s出招，%s危急间使出【%s】，身形一晃避开了。" % [_player_name(), session.enemy.get("displayName", "敌人"), enemy_dodge_move.get("name", "身法")])
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "dodged": true}
	var enemy_parry := _npc_move(session.enemy, "parry")
	var parry_move_tag := ""
	if not enemy_parry.is_empty():
		var reduction := minf(PARRY_REDUCE_CAP, PARRY_REDUCE_BASE + maxi(0, int(enemy_parry.get("level", 0)) - int(enemy_parry.get("unlock", 0))) * PARRY_REDUCE_PER_LEVEL)
		result.damage = int(floor(float(result.damage) * (1.0 - reduction)))
		parry_move_tag = "（招架招式【%s】，减伤%d%%）" % [enemy_parry.get("name", "招架"), int(round(reduction * 100.0))]
	if int(session.get("enemy_status", {}).get("weakness", 0)) > 0:
		result.damage = int(ceil(float(result.damage) * WEAKNESS_DAMAGE_MULT))
	var force_extra := _apply_player_force_power(result)
	var move_tag := ""
	var status_tag := ""
	if not attack_move.is_empty():
		var status := _roll_attack_move_status(attack_move)
		var extra := int(floor(8.0 + maxi(0, int(attack_move.get("level", 0)) - int(attack_move.get("unlock", 0))) * 0.6))
		if not status.is_empty():
			extra = int(floor(float(extra) * 0.5))
		result.damage += extra
		move_tag = "（招式+%d）" % extra
		if not status.is_empty():
			var turns := randi_range(1, 3)
			add_status(session, "enemy", str(status.kind), turns)
			status_tag = "（施加%s%d回合）" % [_status_name(str(status.kind)), turns]
	result.damage = maxi(1, int(floor(float(result.damage) * maxf(0.0, damage_scale))))
	var wound := int(InventorySystem.equipment_bonus().get("woundInflict", 0))
	var wound_tag := ""
	session.enemy_hp = maxi(0 if bool(session.get("lethal", true)) else 1, int(session.enemy_hp) - int(result.damage))
	if wound > 0 and int(session.enemy_hp) > 0:
		var old_max := maxi(1, int(session.enemy_max_hp))
		var new_max := maxi(1, old_max - wound)
		session.enemy_hp = maxi(0 if bool(session.get("lethal", true)) else 1, mini(new_max, int(floor(float(session.enemy_hp) * float(new_max) / float(old_max)))))
		session.enemy_max_hp = new_max
		wound_tag = "（致伤削上限 −%d）" % wound
	var tags := ("暴击！" if result.crit else "") + ("（被招架）" if result.parried else "")
	tags += move_tag
	if force_extra > 0: tags += "（加力+%d，耗精力%d）" % [force_extra, SkillSystem.force_power()]
	tags += wound_tag + status_tag + parry_move_tag
	session.log.append("%s%s，命中 %d 点%s。%s余 %d 体力。" % [_player_name(), attack_verb, result.damage, tags, session.enemy.get("displayName", "敌人"), session.enemy_hp])
	return result

## 只有当前精力足以支付完整档位时才生效；加力按本次伤害的递减比例增伤。
func _apply_player_force_power(result: Dictionary) -> int:
	var force := SkillSystem.force_power()
	if force <= 0 or int(GameState.combat_state.mp) < force:
		return 0
	GameState.combat_state.mp -= force
	var extra := rules.force_damage_bonus(int(result.get("damage", 0)), force)
	result.damage = int(result.get("damage", 0)) + extra
	return extra

## 与 player_attack 结构对称；NPC 在命中后按 AI 配置尝试消耗精力加力。
func enemy_attack(session: Dictionary, turn_started := false, damage_scale := 1.0, hit_bonus_extra := 0.0, attack_power_bonus := 0.0, action_label := "进招", allow_attack_move := true) -> Dictionary:
	var turn_check := {"can_act": true, "message": ""} if turn_started else start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var enemy_attributes: Dictionary = rules.npc_combat_attributes(session.enemy)
	var player_attributes: Dictionary = rules.player_combat_attributes()
	var enemy_equipment := _npc_equipment_bonus(session.enemy)
	var equipment := InventorySystem.equipment_bonus()
	var enemy_skill_bonus := _npc_combat_bonus(session.enemy)
	var player_skill_bonus := SkillSystem.combat_bonus()
	var attack_move := _npc_move(session.enemy, "attack") if allow_attack_move else {}
	var move_hit_bonus := MOVE_HIT_BONUS if not attack_move.is_empty() else 0.0
	var attack_verb := "使出【%s】" % attack_move.get("name", "招式") if not attack_move.is_empty() else action_label
	var result: Dictionary = GameState.resolve_attack(_enemy_attack_power(session.enemy) + attack_power_bonus, enemy_attributes, player_attributes, _player_defense(), (float(enemy_skill_bonus.get("hit", 0)) + float(enemy_equipment.get("hit", 0))) * 0.01 + move_hit_bonus + hit_bonus_extra, (float(player_skill_bonus.get("dodge", 0)) + float(equipment.get("dodge", 0))) * 0.01, (float(player_skill_bonus.get("parry", 0)) + float(equipment.get("parry", 0))) * 0.01, float(enemy_equipment.get("crit", 0)) * 0.01)
	if not result.hit:
		session.log.append("%s%s，%s身形一晃避开了。" % [session.enemy.get("displayName", "敌人"), attack_verb, _player_name()])
		return result
	var player_dodge_moves: Array = SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "dodge")
	if not player_dodge_moves.is_empty() and randf() < rules.move_trigger_rate("dodge", player_dodge_moves.size()):
		var dodge_move: Dictionary = _weighted_pick(player_dodge_moves)
		session.log.append("%s出招，%s危急间使出【%s】，身形一晃避开了。" % [session.enemy.get("displayName", "敌人"), _player_name(), dodge_move.get("name", "身法")])
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "dodged": true, "message": "你成功闪避"}
	var player_parry := SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "parry")
	var parry_move_tag := ""
	if not player_parry.is_empty() and randf() < rules.move_trigger_rate("parry", player_parry.size()):
		var parry_move: Dictionary = _weighted_pick(player_parry)
		var reduction := minf(PARRY_REDUCE_CAP, PARRY_REDUCE_BASE + maxi(0, int(parry_move.get("level", 0)) - int(parry_move.get("unlock", 0))) * PARRY_REDUCE_PER_LEVEL)
		result.damage = int(floor(float(result.damage) * (1.0 - reduction)))
		parry_move_tag = "（招架招式【%s】，减伤%d%%）" % [parry_move.get("name", "招架"), int(round(reduction * 100.0))]
	if int(session.get("player_status", {}).get("weakness", 0)) > 0:
		result.damage = int(ceil(float(result.damage) * WEAKNESS_DAMAGE_MULT))
	var enemy_force_extra := _apply_enemy_force_power(session, result)
	var move_tag := ""
	var status_tag := ""
	if not attack_move.is_empty():
		var status := _roll_attack_move_status(attack_move)
		var extra := int(floor(8.0 + maxi(0, int(attack_move.get("level", 0)) - int(attack_move.get("unlock", 0))) * 0.6))
		if not status.is_empty():
			extra = int(floor(float(extra) * 0.5))
		result.damage += extra
		move_tag = "（招式+%d）" % extra
		if not status.is_empty():
			var turns := randi_range(1, 3)
			add_status(session, "player", str(status.kind), turns)
			status_tag = "（施加%s%d回合）" % [_status_name(str(status.kind)), turns]
	result.damage = maxi(1, int(floor(float(result.damage) * maxf(0.0, damage_scale))))
	var wound := int(enemy_equipment.get("woundInflict", 0))
	var injury_tag := _maybe_apply_in_battle_injury(session, result)
	GameState.combat_state.hp = maxi(0 if bool(session.get("lethal", true)) else 1, int(GameState.combat_state.hp) - int(result.damage))
	var wound_tag := ""
	if wound > 0 and int(GameState.combat_state.hp) > 0:
		var old_max := maxi(1, int(session.get("player_max_hp", _player_hp_max())))
		var reduced_max := maxi(1, old_max - wound)
		GameState.combat_state.hp = maxi(0 if bool(session.get("lethal", true)) else 1, mini(reduced_max, int(floor(float(GameState.combat_state.hp) * float(reduced_max) / float(old_max)))))
		session.player_max_hp = reduced_max
		wound_tag = "（致伤削上限 −%d）" % wound
	session.player_hp = GameState.combat_state.hp
	_track_player_state(session)
	var tags := ("暴击！" if result.crit else "") + ("（被招架）" if result.parried else "")
	tags += move_tag
	if enemy_force_extra > 0: tags += "（加力+%d）" % enemy_force_extra
	tags += injury_tag + wound_tag + status_tag + parry_move_tag
	session.log.append("%s%s，命中 %d 点%s。%s余 %d 体力。" % [session.enemy.get("displayName", "敌人"), attack_verb, result.damage, tags, _player_name(), GameState.combat_state.hp])
	return result

## NPC 默认只在部分回合使用四分之一内功加力；可由 ai.forceUseRate/forceRatio 覆盖。
## 这样高阶人物仍有爆发，但不会每次普攻都按全部内功自动增伤。
func _apply_enemy_force_power(session: Dictionary, result: Dictionary) -> int:
	var ai: Dictionary = session.enemy.get("ai", {})
	if randf() >= clampf(float(ai.get("forceUseRate", NPC_FORCE_USE_RATE)), 0.0, 1.0):
		return 0
	var ratio := clampf(float(ai.get("forceRatio", NPC_FORCE_INNER_POWER_RATIO)), 0.0, 1.0)
	var force := maxi(0, int(ceil(float(_npc_inner_power(session.enemy)) * ratio)))
	if force <= 0 or int(session.get("enemy_mp", 0)) < force:
		return 0
	session.enemy_mp = int(session.enemy_mp) - force
	var extra := rules.force_damage_bonus(int(result.get("damage", 0)), force)
	result.damage = int(result.get("damage", 0)) + extra
	return extra

## 根据单次受击结果尝试增加本场战斗伤势。
func _maybe_apply_in_battle_injury(session: Dictionary, result: Dictionary) -> String:
	return rules.maybe_apply_in_battle_injury(session, result)

## 从候选招式中按权重随机选择一项。
func _weighted_pick(moves: Array) -> Dictionary:
	return rules.weighted_pick(moves)

## 按招式解锁等级表滚动附加异常状态。
func _roll_attack_move_status(move: Dictionary) -> Dictionary:
	return rules.roll_attack_move_status(move)

## 把内部状态键转换为中文战报名称。
func _status_name(kind: String) -> String:
	return rules.status_name(kind)

## 返回 NPC 当前可使用的指定类型招式。
func _npc_move(npc: Dictionary, kind: String) -> Dictionary:
	return rules.npc_move(npc, kind)

## 委托敌方人工智能完成一个回合决策。
func enemy_action(session: Dictionary) -> Dictionary:
	return enemy_ai.act(session)

## NPC 版“已解锁绝招”：等级门槛与消耗表与玩家侧共用 skill_loadout.gd 中的定义。
func _npc_ults(npc: Dictionary) -> Array:
	return enemy_ai.npc_ults(npc)

## 委托统一绝招执行器处理敌方绝招。
func _enemy_use_ult(session: Dictionary, ult: Dictionary, turn_started := false) -> Dictionary:
	return ultimate_actions.enemy_use(session, ult, turn_started)

## 使用一件战斗药品恢复玩家体力。
func use_item(session: Dictionary, item_id: String) -> Dictionary:
	return player_recovery.use_item(session, item_id)

## 消耗精力执行摸鱼并恢复等量体力。
func rest(session: Dictionary) -> Dictionary:
	return player_recovery.rest(session)

## 推进指定一方的回合状态并返回能否行动。
func start_turn(session: Dictionary, side: String) -> Dictionary:
	return status_effects.start_turn(session, side)

## 为指定一方添加或延长异常状态。
func add_status(session: Dictionary, side: String, status: String, turns: int) -> void:
	status_effects.add_status(session, side, status, turns)

## 记录玩家最低体力与重伤状态。
func _track_player_state(session: Dictionary) -> void:
	status_effects.track_player_state(session)

## 选择并施展玩家绝招。
func use_ult(session: Dictionary, ult_ref: Variant = 0) -> Dictionary:
	return ultimate_actions.player_use(session, ult_ref)

## 逃跑成功率恒定夹在 [10%, 90%] 之间：再悬殊的身法差距也留一线生机/风险。
func flee(session: Dictionary) -> bool:
	var self_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var rate := clampf(FLEE_BASE + (float(self_attributes.get("agility", 0)) - float(enemy_attributes.get("agility", 0))) * FLEE_PER_AGILITY, 0.10, 0.90)
	var escaped := randf() < rate
	session.log.append("你觑得空隙，抽身遁走！" if escaped else "逃跑不及，被拦了下来！")
	return escaped

## 完成回合状态检查后尝试逃跑。
func flee_action(session: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "player")
	if not turn_check.can_act:
		return {"escaped": false, "skipped": true, "message": turn_check.message}
	var escaped := flee(session)
	return {"escaped": escaped, "skipped": false, "message": str(session.log[-1])}

## 返回玩家当前有效战斗体力上限。
func _player_hp_max() -> int:
	return rules.player_hp_max()

## 汇总玩家属性、功法和装备得到攻击力。
func _player_attack_power() -> float:
	return rules.player_attack_power()

## 返回玩家姓名，空值时使用默认称呼。
func _player_name() -> String:
	return rules.player_name()

## 汇总玩家架构、功法和装备得到防御力。
func _player_defense() -> float:
	return rules.player_defense()

## 汇总 NPC 属性、功法和装备得到攻击力。
func _enemy_attack_power(enemy: Dictionary) -> float:
	return rules.enemy_attack_power(enemy)

## 汇总 NPC 当前装备功法的战斗加成。
func _npc_combat_bonus(npc: Dictionary) -> Dictionary:
	return rules.npc_combat_bonus(npc)

## 根据 NPC 架构功法计算内功值。
func _npc_inner_power(npc: Dictionary) -> int:
	return rules.npc_inner_power(npc)

## 汇总 NPC 已装备物品的战斗属性。
func _npc_equipment_bonus(npc: Dictionary) -> Dictionary:
	return rules.npc_equipment_bonus(npc)
