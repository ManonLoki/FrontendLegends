extends Node

const COMBAT_RULES := preload("res://scripts/combat/combat_rules.gd")
const COMBAT_STATUS := preload("res://scripts/combat/combat_status.gd")
var rules := COMBAT_RULES.new()
@onready var status_effects := COMBAT_STATUS.new(self)

const CRIT_BASE := 0.03
const CRIT_PER_CONSTITUTION := 0.0035
const FLEE_BASE := 0.40
const FLEE_PER_AGILITY := 0.03

## 门派绝招命中修正（百分点，见参考项目 UltEffects.ts）：连击每击 -5%、异常 +10%、降上限 +5%、巨伤 -15%。
const ULT_HIT_BONUS := {"multi": -0.05, "abnormal": 0.10, "reduceMax": 0.05, "hugeDamage": -0.15}

## 攻击招式附带异常状态表：10 个招式槽位中 6 个携带状态（见参考项目 SectMoves.ts）。
const ATTACK_MOVE_STATUS_TABLE := {20: "paralysis", 40: "weakness", 50: "poison", 70: "paralysis", 80: "weakness", 90: "poison"}

const ENEMY_ULT_USE_RATE := 0.35
const ENEMY_ITEM_USE_RATE := 0.55
const ENEMY_REST_USE_RATE := 0.30
const ENEMY_ITEM_HP_RATIO := 0.30
const ENEMY_REST_HP_RATIO := 0.50
const ENEMY_REST_MIN_MP := 8
const ENEMY_CONSUMABLE_HEAL_RATIO := 0.25

## 己方/敌方共用的招式触发概率曲线：基础 25% + 每个已解锁招式 4%，封顶 55%。
const MOVE_TRIGGER_BASE := 0.25
const MOVE_TRIGGER_PER_MOVE := 0.04
const MOVE_TRIGGER_CAP := 0.55

## 招架伤害减免：基础 15% + 每高出敌方 1 级 1%，封顶 35%。
const PARRY_REDUCE_BASE := 0.15
const PARRY_REDUCE_PER_LEVEL := 0.01
const PARRY_REDUCE_CAP := 0.35

const WEAKNESS_DAMAGE_MULT := 1.30

## 绝招按 kind 分级的威力倍率/命中副作用，_enemy_use_ult 与 use_ult 共用同一套数值表。
const ULT_MULTI_POWER_TIER1 := 0.55
const ULT_MULTI_POWER_TIER2 := 0.50
const ULT_MULTI_HITS_TIER1 := 3
const ULT_MULTI_HITS_TIER2 := 5
const ULT_ABNORMAL_POWER_TIER1 := 0.60
const ULT_ABNORMAL_POWER_TIER2 := 0.70
const ULT_ABNORMAL_PARALYZE_CHANCE_TIER1 := 0.80
const ULT_ABNORMAL_PARALYZE_CHANCE_TIER2 := 0.95
const ULT_REDUCE_MAX_POWER_TIER1 := 0.55
const ULT_REDUCE_MAX_POWER_TIER2 := 0.65
const ULT_REDUCE_MAX_RATIO_TIER1 := 0.08
const ULT_REDUCE_MAX_RATIO_TIER2 := 0.15
const ULT_HUGE_DAMAGE_POWER_TIER1 := 2.5
const ULT_HUGE_DAMAGE_POWER_TIER2 := 4.0

## initial_player_hp 记录战斗开始时的体力快照，供 battle_resolve.gd 结算战后伤势
## （伤势 = 战斗中实际损失的体力，与体力上限变动无关）。
func create_session(enemy_id: String, lethal: bool = true) -> Dictionary:
	return rules.create_session(enemy_id, lethal)

func _npc_mp_max(npc: Dictionary) -> int:
	return rules.npc_mp_max(npc)

func player_attack(session: Dictionary, turn_started := false, damage_scale := 1.0, hit_bonus_extra := 0.0, attack_power_bonus := 0.0, action_label := "出手", allow_attack_move := true) -> Dictionary:
	var turn_check := {"can_act": true, "message": ""} if turn_started else start_turn(session, "player")
	if not turn_check.can_act:
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var attack_moves: Array = SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "attack") if allow_attack_move else []
	var attack_move: Dictionary = {}
	if not attack_moves.is_empty() and randf() < minf(MOVE_TRIGGER_CAP, MOVE_TRIGGER_BASE + attack_moves.size() * MOVE_TRIGGER_PER_MOVE):
		attack_move = _weighted_pick(attack_moves)
	var move_hit_bonus := 0.12 if not attack_move.is_empty() else 0.0
	var attack_verb := "使出【%s】" % attack_move.get("name", "招式") if not attack_move.is_empty() else action_label
	var enemy_equipment := _npc_equipment_bonus(session.enemy)
	var defense := GameState.defense_base(float(enemy_attributes.get("constitution", 0))) + _npc_best_combat_bonus(session.enemy, "defPerLv") + float(enemy_equipment.get("defense", 0))
	var result: Dictionary = GameState.resolve_attack(_player_attack_power() + attack_power_bonus, GameState.profile.get("attributes", {}), enemy_attributes, defense, float(InventorySystem.equipment_bonus().get("hit", 0)) * 0.01 + move_hit_bonus + hit_bonus_extra, (_npc_best_combat_bonus(session.enemy, "dodgePerLv") + float(enemy_equipment.get("dodge", 0))) * 0.01, (_npc_passive_parry(session.enemy) + float(enemy_equipment.get("parry", 0))) * 0.01, float(InventorySystem.equipment_bonus().get("crit", 0)) * 0.01)
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

## 严格对齐参考项目：只有当前精力足以支付完整加力档位时才生效，不允许用
## 剩余精力做“部分加力”；额外伤害按加力面板口径在 0～档位×2 间取整。
func _apply_player_force_power(result: Dictionary) -> int:
	var force := SkillSystem.force_power()
	if force <= 0 or int(GameState.combat_state.mp) < force:
		return 0
	GameState.combat_state.mp -= force
	var extra := maxi(1, int(floor(float(force) * randf_range(0.75, 1.25))))
	result.damage = int(result.get("damage", 0)) + extra
	return extra

## 与 player_attack 结构对称，但敌方没有“加力”（force_power）步骤——
## 加力是玩家专属的精力换伤害机制，NPC 不消耗精力做等价操作。
func enemy_attack(session: Dictionary, turn_started := false, damage_scale := 1.0, hit_bonus_extra := 0.0, attack_power_bonus := 0.0, action_label := "进招", allow_attack_move := true) -> Dictionary:
	var turn_check := {"can_act": true, "message": ""} if turn_started else start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_equipment := _npc_equipment_bonus(session.enemy)
	var equipment := InventorySystem.equipment_bonus()
	var attack_move := _npc_move(session.enemy, "attack") if allow_attack_move else {}
	var move_hit_bonus := 0.12 if not attack_move.is_empty() else 0.0
	var attack_verb := "使出【%s】" % attack_move.get("name", "招式") if not attack_move.is_empty() else action_label
	var result: Dictionary = GameState.resolve_attack(_enemy_attack_power(session.enemy) + attack_power_bonus, enemy_attributes, player_attributes, _player_defense(), float(enemy_equipment.get("hit", 0)) * 0.01 + move_hit_bonus + hit_bonus_extra, (SkillSystem.best_combat_bonus("dodgePerLv") + float(equipment.get("dodge", 0))) * 0.01, (float(SkillSystem.combat_bonus().get("parry", 0.0)) + float(equipment.get("parry", 0))) * 0.01, float(enemy_equipment.get("crit", 0)) * 0.01)
	if not result.hit:
		session.log.append("%s%s，%s身形一晃避开了。" % [session.enemy.get("displayName", "敌人"), attack_verb, _player_name()])
		return result
	var player_dodge_moves: Array = SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "dodge")
	if not player_dodge_moves.is_empty() and randf() < minf(MOVE_TRIGGER_CAP, MOVE_TRIGGER_BASE + player_dodge_moves.size() * MOVE_TRIGGER_PER_MOVE):
		var dodge_move: Dictionary = _weighted_pick(player_dodge_moves)
		session.log.append("%s出招，%s危急间使出【%s】，身形一晃避开了。" % [session.enemy.get("displayName", "敌人"), _player_name(), dodge_move.get("name", "身法")])
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "dodged": true, "message": "你成功闪避"}
	var player_parry := SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "parry")
	var parry_move_tag := ""
	if not player_parry.is_empty() and randf() < minf(MOVE_TRIGGER_CAP, MOVE_TRIGGER_BASE + player_parry.size() * MOVE_TRIGGER_PER_MOVE):
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
	session.player_damage_taken = int(session.get("player_damage_taken", 0)) + int(result.damage)
	_track_player_state(session)
	var tags := ("暴击！" if result.crit else "") + ("（被招架）" if result.parried else "")
	tags += move_tag
	if enemy_force_extra > 0: tags += "（加力+%d，耗精力%d）" % [enemy_force_extra, _npc_inner_power(session.enemy)]
	tags += injury_tag + wound_tag + status_tag + parry_move_tag
	session.log.append("%s%s，命中 %d 点%s。%s余 %d 体力。" % [session.enemy.get("displayName", "敌人"), attack_verb, result.damage, tags, _player_name(), GameState.combat_state.hp])
	return result

func _apply_enemy_force_power(session: Dictionary, result: Dictionary) -> int:
	var force := _npc_inner_power(session.enemy)
	if force <= 0 or int(session.get("enemy_mp", 0)) < force:
		return 0
	session.enemy_mp = int(session.enemy_mp) - force
	var extra := maxi(1, int(floor(float(force) * randf_range(0.75, 1.25))))
	result.damage = int(result.get("damage", 0)) + extra
	return extra

func _maybe_apply_in_battle_injury(session: Dictionary, result: Dictionary) -> String:
	return rules.maybe_apply_in_battle_injury(session, result)

func _weight_of(move: Dictionary) -> int:
	return rules.weight_of(move)

func _weighted_pick(moves: Array) -> Dictionary:
	return rules.weighted_pick(moves)

func _roll_attack_move_status(move: Dictionary) -> Dictionary:
	return rules.roll_attack_move_status(move)

func _status_name(kind: String) -> String:
	return rules.status_name(kind)

func _npc_move(npc: Dictionary, kind: String) -> Dictionary:
	return rules.npc_move(npc, kind)

func enemy_action(session: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"hit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var hp := int(session.get("enemy_hp", 0))
	var hp_max := maxi(1, int(session.get("enemy_max_hp", hp)))
	var enemy_mp := int(session.get("enemy_mp", 0))
	var hp_ratio := float(hp) / float(hp_max)
	var ai: Dictionary = session.enemy.get("ai", {})
	var rest_hp_ratio := float(ai.get("restHpRatio", ENEMY_REST_HP_RATIO))
	var rest_use_rate := float(ai.get("restUseRate", ENEMY_REST_USE_RATE))
	var item_hp_ratio := float(ai.get("itemHpRatio", ENEMY_ITEM_HP_RATIO))
	var item_use_rate := float(ai.get("itemUseRate", ENEMY_ITEM_USE_RATE))

	# NPC AI 决策按优先级：1) 濒死且精力够 → 概率摸鱼；2) 体力低且有虚拟药水 → 概率用药；
	# 3) 有可用绝招 → 35% 施展（优先高档）；4) 否则普攻。
	if hp_ratio < rest_hp_ratio and enemy_mp >= ENEMY_REST_MIN_MP and randf() < rest_use_rate:
		var heal := mini(enemy_mp, hp_max - hp)
		if heal > 0:
			session.enemy_hp = hp + heal
			session.enemy_mp = enemy_mp - heal
			session.log.append("%s 摸鱼恢复 %d 体力" % [session.enemy.get("displayName", "敌人"), heal])
			return {"ok": true, "rest": true, "damage": 0, "message": "敌方摸鱼恢复 %d 体力" % heal}

	var charges := int(ai.get("consumableCharges", 0))
	if hp_ratio < item_hp_ratio and charges > 0 and randf() < item_use_rate:
		var heal_amount := int(ai.get("consumableHeal", maxi(1, int(floor(float(hp_max) * ENEMY_CONSUMABLE_HEAL_RATIO)))))
		session.enemy_hp = mini(hp_max, hp + heal_amount)
		var updated_ai: Dictionary = ai.duplicate(true)
		updated_ai.consumableCharges = charges - 1
		session.enemy.ai = updated_ai
		session.log.append("%s 服下一颗丹药，体力 +%d" % [session.enemy.get("displayName", "敌人"), heal_amount])
		return {"ok": true, "item": true, "damage": 0, "message": "敌方服药回复 %d 体力" % heal_amount}

	var enemy_ults := _npc_ults(session.enemy)
	var affordable: Array = enemy_ults.filter(func(u): return enemy_mp >= int(u.get("mp_cost", 0)))
	if not affordable.is_empty() and randf() < ENEMY_ULT_USE_RATE:
		affordable.sort_custom(func(a, b): return int(a.get("tier", 1)) > int(b.get("tier", 1)))
		return _enemy_use_ult(session, affordable[0], true)

	return enemy_attack(session, true)

## NPC 版“已解锁绝招”：等级门槛（30/80）与消耗表须与玩家侧
## SkillSystem.unlocked_ults()/_make_ult() 保持一致，两处各自维护同一套数值。
func _npc_ults(npc: Dictionary) -> Array:
	var result: Array = []
	var skill_levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		if str(definition.get("theme", "")) != "arch" or definition.get("ult", {}).is_empty():
			continue
		var level_value := int(skill_levels.get(str(skill_id), 0))
		var inner_power := int(skill_levels.get("basicConstitution", 0)) + level_value * 2
		var config: Dictionary = definition.get("ult", {})
		var kind := str(config.get("kind", "hugeDamage"))
		var costs: Dictionary = {"multi": [25, 45], "abnormal": [30, 50], "reduceMax": [35, 60], "hugeDamage": [40, 70]}
		var names: Array = config.get("names", ["绝招", "绝招"])
		if level_value >= 30:
			result.append({"name": names[0], "kind": kind, "tier": 1, "inner_power": inner_power, "mp_cost": costs.get(kind, [40, 70])[0]})
		if level_value >= 80:
			result.append({"name": names[1], "kind": kind, "tier": 2, "inner_power": inner_power, "mp_cost": costs.get(kind, [40, 70])[1]})
	return result

func _enemy_use_ult(session: Dictionary, ult: Dictionary, turn_started := false) -> Dictionary:
	var turn_check := {"can_act": true, "message": ""} if turn_started else start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "damage": 0, "message": turn_check.message}
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var cost := int(ult.get("mp_cost", 0))
	if int(session.enemy_mp) < cost:
		return enemy_attack(session, true)
	session.enemy_mp = int(session.enemy_mp) - cost
	var kind := str(ult.get("kind", "hugeDamage"))
	var tier := int(ult.get("tier", 1))
	var label := "施展【%s】" % ult.get("name", "敌方绝招")
	var power_bonus := float(ult.get("inner_power", 0))
	var total_damage := 0
	var landed := 0
	if kind == "multi":
		var hits := ULT_MULTI_HITS_TIER1 if tier == 1 else ULT_MULTI_HITS_TIER2
		var scale := ULT_MULTI_POWER_TIER1 if tier == 1 else ULT_MULTI_POWER_TIER2
		for _index in hits:
			if int(GameState.combat_state.hp) <= (0 if bool(session.get("lethal", true)) else 1): break
			var hit := enemy_attack(session, true, scale, float(ULT_HIT_BONUS.multi), power_bonus, label, true)
			if bool(hit.get("hit", false)):
				landed += 1
				total_damage += int(hit.damage)
		session.log.append("连击 %d 击（%d 中）：%s" % [hits, landed, "共伤 %d。" % total_damage if total_damage > 0 else "一击未中。"])
	else:
		var scale := (ULT_ABNORMAL_POWER_TIER1 if tier == 1 else ULT_ABNORMAL_POWER_TIER2) if kind == "abnormal" else ((ULT_REDUCE_MAX_POWER_TIER1 if tier == 1 else ULT_REDUCE_MAX_POWER_TIER2) if kind == "reduceMax" else (ULT_HUGE_DAMAGE_POWER_TIER1 if tier == 1 else ULT_HUGE_DAMAGE_POWER_TIER2))
		var hit := enemy_attack(session, true, scale, float(ULT_HIT_BONUS.get(kind, 0.0)), power_bonus, label, false)
		if bool(hit.get("hit", false)):
			landed = 1
			total_damage = int(hit.damage)
			if kind == "abnormal" and randf() < (ULT_ABNORMAL_PARALYZE_CHANCE_TIER1 if tier == 1 else ULT_ABNORMAL_PARALYZE_CHANCE_TIER2):
				var turns := 1 if tier == 1 else randi_range(1, 2)
				add_status(session, "player", "paralysis", turns)
				session.log.append("%s麻痹，%d 回合无法出手。" % [_player_name(), turns])
			elif kind == "reduceMax" and int(GameState.combat_state.hp) > 0:
				var old_max := maxi(1, int(session.get("player_max_hp", _player_hp_max())))
				var reduce := maxi(1, int(floor(float(old_max) * (ULT_REDUCE_MAX_RATIO_TIER1 if tier == 1 else ULT_REDUCE_MAX_RATIO_TIER2))))
				var new_max := maxi(1, old_max - reduce)
				GameState.combat_state.hp = maxi(0 if bool(session.get("lethal", true)) else 1, mini(new_max, int(floor(float(GameState.combat_state.hp) * float(new_max) / float(old_max)))))
				session.player_hp = GameState.combat_state.hp
				session.player_max_hp = new_max
				session.log.append("%s气机受创，体力上限 −%d。" % [_player_name(), reduce])
	return {"ok": true, "damage": total_damage, "landed": landed, "ult": ult}

func use_item(session: Dictionary, item_id: String) -> Dictionary:
	var turn_check := start_turn(session, "player")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "message": turn_check.message}
	var definition := DataRegistry.get_item(item_id)
	var hp_gain := maxi(0, int(definition.get("effects", {}).get("hp", 0)))
	if str(definition.get("kind", "")) != "medicine" or hp_gain <= 0 or not InventorySystem.remove_item(item_id):
		return {"ok": false, "message": "身上没有伤药。"}
	var before := int(GameState.combat_state.hp)
	GameState.combat_state.hp = mini(int(session.get("player_max_hp", _player_hp_max())), before + hp_gain)
	session.player_hp = GameState.combat_state.hp
	var actual_gain := int(GameState.combat_state.hp) - before
	var message := "你服药调息，体力 +%d。" % hp_gain
	session.log.append(message)
	return {"ok": true, "message": message, "hp_gain": actual_gain}

func rest(session: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "player")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "message": turn_check.message}
	var missing := maxi(0, int(session.get("player_max_hp", _player_hp_max())) - int(GameState.combat_state.hp))
	if missing <= 0:
		var full_result := {"ok": false, "message": "体力已满，不必摸鱼。"}
		session.log.append(full_result.message)
		return full_result
	var amount := mini(int(GameState.combat_state.mp), missing)
	if amount <= 0:
		var empty_result := {"ok": false, "message": "精力不足，摸不了鱼。"}
		session.log.append(empty_result.message)
		return empty_result
	GameState.combat_state.mp -= amount
	GameState.combat_state.hp += amount
	session.player_hp = GameState.combat_state.hp
	session.log.append("你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount])
	return {"ok": true, "message": "你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount], "amount": amount}

func start_turn(session: Dictionary, side: String) -> Dictionary:
	return status_effects.start_turn(session, side)

func add_status(session: Dictionary, side: String, status: String, turns: int) -> void:
	status_effects.add_status(session, side, status, turns)

func _track_player_state(session: Dictionary) -> void:
	status_effects.track_player_state(session)

func use_ult(session: Dictionary, ult_ref: Variant = 0) -> Dictionary:
	var turn_check := start_turn(session, "player")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "message": turn_check.message}
	var ults: Array = SkillSystem.unlocked_ults()
	var ult: Dictionary = {}
	if ult_ref is Dictionary:
		ult = ult_ref
	else:
		var ult_index := int(ult_ref)
		if ult_index >= 0 and ult_index < ults.size(): ult = ults[ult_index]
	if ult.is_empty():
		return {"ok": false, "message": "你没有这门绝招。"}
	var cost := int(ult.get("mp_cost", 0))
	if int(GameState.combat_state.get("mp", 0)) < cost:
		return {"ok": false, "message": "精力不足，施展不出【%s】。" % ult.get("name", "绝招")}
	GameState.combat_state.mp = int(GameState.combat_state.mp) - cost
	var kind := str(ult.get("kind", "hugeDamage"))
	var tier := int(ult.get("tier", 1))
	var label := "施展【%s】" % ult.get("name", "绝招")
	var power_bonus := float(ult.get("inner_power", 0))
	var total_damage := 0
	var landed := 0
	if kind == "multi":
		var hits := ULT_MULTI_HITS_TIER1 if tier == 1 else ULT_MULTI_HITS_TIER2
		var scale := ULT_MULTI_POWER_TIER1 if tier == 1 else ULT_MULTI_POWER_TIER2
		for _index in hits:
			if int(session.enemy_hp) <= (0 if bool(session.get("lethal", true)) else 1): break
			var hit := player_attack(session, true, scale, float(ULT_HIT_BONUS.multi), power_bonus, label, true)
			if bool(hit.get("hit", false)):
				landed += 1
				total_damage += int(hit.damage)
		session.log.append("连击 %d 击（%d 中）：%s" % [hits, landed, "共伤 %d。" % total_damage if total_damage > 0 else "一击未中。"])
	else:
		var scale := (ULT_ABNORMAL_POWER_TIER1 if tier == 1 else ULT_ABNORMAL_POWER_TIER2) if kind == "abnormal" else ((ULT_REDUCE_MAX_POWER_TIER1 if tier == 1 else ULT_REDUCE_MAX_POWER_TIER2) if kind == "reduceMax" else (ULT_HUGE_DAMAGE_POWER_TIER1 if tier == 1 else ULT_HUGE_DAMAGE_POWER_TIER2))
		var hit := player_attack(session, true, scale, float(ULT_HIT_BONUS.get(kind, 0.0)), power_bonus, label, false)
		if bool(hit.get("hit", false)):
			landed = 1
			total_damage = int(hit.damage)
			if kind == "abnormal" and randf() < (ULT_ABNORMAL_PARALYZE_CHANCE_TIER1 if tier == 1 else ULT_ABNORMAL_PARALYZE_CHANCE_TIER2):
				var turns := 1 if tier == 1 else randi_range(1, 2)
				add_status(session, "enemy", "paralysis", turns)
				session.log.append("%s麻痹，%d 回合无法出手。" % [session.enemy.get("displayName", "敌人"), turns])
			elif kind == "reduceMax" and int(session.enemy_hp) > 0:
				var old_max := maxi(1, int(session.enemy_max_hp))
				var reduce := maxi(1, int(floor(float(old_max) * (ULT_REDUCE_MAX_RATIO_TIER1 if tier == 1 else ULT_REDUCE_MAX_RATIO_TIER2))))
				var new_max := maxi(1, old_max - reduce)
				session.enemy_hp = maxi(0 if bool(session.get("lethal", true)) else 1, mini(new_max, int(floor(float(session.enemy_hp) * float(new_max) / float(old_max)))))
				session.enemy_max_hp = new_max
				session.log.append("%s气机受创，体力上限 −%d。" % [session.enemy.get("displayName", "敌人"), reduce])
	return {"ok": true, "damage": total_damage, "landed": landed, "ult": ult}

## 逃跑成功率恒定夹在 [10%, 90%] 之间：再悬殊的身法差距也留一线生机/风险。
func flee(session: Dictionary) -> bool:
	var self_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var rate := clampf(FLEE_BASE + (float(self_attributes.get("agility", 0)) - float(enemy_attributes.get("agility", 0))) * FLEE_PER_AGILITY, 0.10, 0.90)
	var escaped := randf() < rate
	session.log.append("你觑得空隙，抽身遁走！" if escaped else "逃跑不及，被拦了下来！")
	return escaped

func flee_action(session: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "player")
	if not turn_check.can_act:
		return {"escaped": false, "skipped": true, "message": turn_check.message}
	var escaped := flee(session)
	return {"escaped": escaped, "skipped": false, "message": str(session.log[-1])}

func _initiative(player: Dictionary, enemy: Dictionary) -> bool:
	return rules.initiative(player, enemy)

func _hp_max(attributes: Dictionary, mp_max: int) -> int:
	return rules.hp_max(attributes, mp_max)

func _player_hp_max() -> int:
	return rules.player_hp_max()

func _player_attack_power() -> float:
	return rules.player_attack_power()

func _player_name() -> String:
	return rules.player_name()

func _player_defense() -> float:
	return rules.player_defense()

func _enemy_attack_power(enemy: Dictionary) -> float:
	return rules.enemy_attack_power(enemy)

func _npc_best_combat_bonus(npc: Dictionary, key: String) -> float:
	return rules.npc_best_combat_bonus(npc, key)

func _npc_passive_parry(npc: Dictionary) -> float:
	return rules.npc_passive_parry(npc)

func _npc_inner_power(npc: Dictionary) -> int:
	return rules.npc_inner_power(npc)

func _npc_equipment_bonus(npc: Dictionary) -> Dictionary:
	return rules.npc_equipment_bonus(npc)
