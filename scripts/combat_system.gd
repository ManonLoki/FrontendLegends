extends Node

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
func create_session(enemy_id: String) -> Dictionary:
	var enemy: Dictionary = NpcSystem.build_instance(enemy_id)
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_attributes: Dictionary = enemy.get("attributes", {})
	var enemy_mp_max := _npc_mp_max(enemy)
	return {
		"enemy_id": enemy_id,
		"enemy": enemy,
		"player_hp": int(GameState.combat_state.get("hp", 1)),
		"player_max_hp": _hp_max(player_attributes, GameState.player_mp_max()),
		"initial_player_hp": int(GameState.combat_state.get("hp", 1)),
		"player_mp": int(GameState.combat_state.get("mp", 0)),
		"enemy_hp": _hp_max(enemy_attributes, enemy_mp_max),
		"enemy_max_hp": _hp_max(enemy_attributes, enemy_mp_max),
		"enemy_mp": enemy_mp_max,
		"enemy_mp_max": enemy_mp_max,
		"player_status": {},
		"enemy_status": {},
		"player_reached_zero": false,
		"player_near_death": false,
		"turn": "player" if _initiative(player_attributes, enemy_attributes) else "enemy",
		"log": []
	}

func _npc_mp_max(npc: Dictionary) -> int:
	var total := maxi(0, int(npc.get("mp", 0)))
	var levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		total += int(definition.get("combat", {}).get("mpMaxPerLv", 0)) * int(levels.get(str(skill_id), 0))
	return total

func player_attack(session: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "player")
	if not turn_check.can_act:
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var bonuses: Dictionary = SkillSystem.combat_bonus()
	var attack_moves: Array = SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "attack")
	var attack_move: Dictionary = {}
	if not attack_moves.is_empty() and randf() < minf(MOVE_TRIGGER_CAP, MOVE_TRIGGER_BASE + attack_moves.size() * MOVE_TRIGGER_PER_MOVE):
		attack_move = _weighted_pick(attack_moves)
	var move_hit_bonus := 0.12 if not attack_move.is_empty() else 0.0
	var enemy_equipment := _npc_equipment_bonus(session.enemy)
	var defense := GameState.defense_base(float(enemy_attributes.get("constitution", 0))) + float(enemy_equipment.get("defense", 0))
	var result: Dictionary = GameState.resolve_attack(_player_attack_power(), GameState.profile.get("attributes", {}), enemy_attributes, defense, (float(bonuses.get("hit", 0.0)) + float(InventorySystem.equipment_bonus().get("hit", 0))) * 0.01 + move_hit_bonus, float(enemy_equipment.get("dodge", 0)) * 0.01, 0.0, float(InventorySystem.equipment_bonus().get("crit", 0)) * 0.01)
	if not result.hit:
		session.log.append("你的攻击未命中")
		return result
	var enemy_dodge_move := _npc_move(session.enemy, "dodge")
	if not enemy_dodge_move.is_empty():
		session.log.append("你出招，%s 危急间使出【%s】，身形一晃避开了。" % [session.enemy.get("displayName", "敌人"), enemy_dodge_move.get("name", "身法")])
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "dodged": true}
	var enemy_parry := _npc_move(session.enemy, "parry")
	if not enemy_parry.is_empty():
		result.damage = int(floor(float(result.damage) * (1.0 - minf(PARRY_REDUCE_CAP, PARRY_REDUCE_BASE + maxi(0, int(enemy_parry.get("level", 0)) - int(enemy_parry.get("unlock", 0))) * PARRY_REDUCE_PER_LEVEL))))
	if int(session.get("enemy_status", {}).get("weakness", 0)) > 0:
		result.damage = int(ceil(float(result.damage) * WEAKNESS_DAMAGE_MULT))
	_apply_player_force_power(result)
	if not attack_move.is_empty():
		var status := _roll_attack_move_status(attack_move)
		var extra := int(floor(8.0 + maxi(0, int(attack_move.get("level", 0)) - int(attack_move.get("unlock", 0))) * 0.6))
		if not status.is_empty():
			extra = int(floor(float(extra) * 0.5))
		result.damage += extra
		if not status.is_empty():
			add_status(session, "enemy", str(status.kind), randi_range(1, 3))
	var wound := int(InventorySystem.equipment_bonus().get("woundInflict", 0))
	if wound > 0 and int(session.enemy_hp) > 0:
		session.enemy_max_hp = maxi(1, int(session.enemy_max_hp) - wound)
		session.enemy_hp = mini(int(session.enemy_hp), int(session.enemy_max_hp))
	session.enemy_hp = maxi(0, int(session.enemy_hp) - int(result.damage))
	session.log.append("你造成 %d 点%s伤害" % [result.damage, "暴击" if result.crit else ""])
	return result

## 严格对齐参考项目：只有当前精力足以支付完整加力档位时才生效，不允许用
## 剩余精力做“部分加力”；额外伤害按加力面板口径在 0～档位×2 间取整。
func _apply_player_force_power(result: Dictionary) -> int:
	var force := SkillSystem.force_power()
	if force <= 0 or int(GameState.combat_state.mp) < force:
		return 0
	GameState.combat_state.mp -= force
	var extra := randi_range(0, force * 2)
	result.damage = int(result.get("damage", 0)) + extra
	return extra

## 与 player_attack 结构对称，但敌方没有“加力”（force_power）步骤——
## 加力是玩家专属的精力换伤害机制，NPC 不消耗精力做等价操作。
func enemy_attack(session: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "skipped": true, "message": turn_check.message}
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_equipment := _npc_equipment_bonus(session.enemy)
	var equipment := InventorySystem.equipment_bonus()
	var attack_move := _npc_move(session.enemy, "attack")
	var move_hit_bonus := 0.12 if not attack_move.is_empty() else 0.0
	var result: Dictionary = GameState.resolve_attack(_enemy_attack_power(session.enemy), enemy_attributes, player_attributes, _player_defense(), float(enemy_equipment.get("hit", 0)) * 0.01 + move_hit_bonus, (float(SkillSystem.combat_bonus().get("dodge", 0.0)) + float(equipment.get("dodge", 0))) * 0.01, float(equipment.get("parry", 0)) * 0.01, float(enemy_equipment.get("crit", 0)) * 0.01)
	if not result.hit:
		session.log.append("%s 出招未能命中" % session.enemy.get("displayName", "敌人"))
		return result
	var player_dodge_moves: Array = SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "dodge")
	if not player_dodge_moves.is_empty() and randf() < minf(MOVE_TRIGGER_CAP, MOVE_TRIGGER_BASE + player_dodge_moves.size() * MOVE_TRIGGER_PER_MOVE):
		var dodge_move: Dictionary = _weighted_pick(player_dodge_moves)
		session.log.append("%s 出招，你危急间使出【%s】，身形一晃避开了。" % [session.enemy.get("displayName", "敌人"), dodge_move.get("name", "身法")])
		return {"hit": false, "parried": false, "crit": false, "damage": 0, "dodged": true, "message": "你成功闪避"}
	var player_parry := SkillSystem.unlocked_moves().filter(func(move): return move.get("kind", "") == "parry")
	if not player_parry.is_empty() and randf() < minf(MOVE_TRIGGER_CAP, MOVE_TRIGGER_BASE + player_parry.size() * MOVE_TRIGGER_PER_MOVE):
		var parry_move: Dictionary = _weighted_pick(player_parry)
		result.damage = int(floor(float(result.damage) * (1.0 - minf(PARRY_REDUCE_CAP, PARRY_REDUCE_BASE + maxi(0, int(parry_move.get("level", 0)) - int(parry_move.get("unlock", 0))) * PARRY_REDUCE_PER_LEVEL))))
	if int(session.get("player_status", {}).get("weakness", 0)) > 0:
		result.damage = int(ceil(float(result.damage) * WEAKNESS_DAMAGE_MULT))
	if not attack_move.is_empty():
		var status := _roll_attack_move_status(attack_move)
		var extra := int(floor(8.0 + maxi(0, int(attack_move.get("level", 0)) - int(attack_move.get("unlock", 0))) * 0.6))
		if not status.is_empty():
			extra = int(floor(float(extra) * 0.5))
		result.damage += extra
		if not status.is_empty():
			add_status(session, "player", str(status.kind), randi_range(1, 3))
	var wound := int(enemy_equipment.get("woundInflict", 0))
	if wound > 0 and int(GameState.combat_state.hp) > 0:
		var reduced_max := maxi(1, int(session.get("player_max_hp", _player_hp_max())) - wound)
		session.player_max_hp = reduced_max
		GameState.combat_state.hp = mini(int(GameState.combat_state.hp), reduced_max)
	GameState.combat_state.hp = maxi(0, int(GameState.combat_state.hp) - int(result.damage))
	session.player_hp = GameState.combat_state.hp
	_track_player_state(session)
	session.log.append("%s 造成 %d 点伤害" % [session.enemy.get("displayName", "敌人"), result.damage])
	return result

## 招式权重 = level − unlockLevel + 1（越熟的招权重越高，至少 1）；轮盘加权随机 1 个。
func _weight_of(move: Dictionary) -> int:
	return maxi(1, int(move.get("level", 0)) - int(move.get("unlock", 0)) + 1)

func _weighted_pick(moves: Array) -> Dictionary:
	var total := 0
	for move in moves:
		total += _weight_of(move)
	var roll := randi() % maxi(1, total)
	for move in moves:
		roll -= _weight_of(move)
		if roll < 0:
			return move
	return moves[moves.size() - 1]

## 该招式在 100 级量表下的附带状态触发率（10%~30%）；仅登记在表中的招式槽位有效。
func _roll_attack_move_status(move: Dictionary) -> Dictionary:
	var unlock := int(move.get("unlock", 0))
	if not ATTACK_MOVE_STATUS_TABLE.has(unlock):
		return {}
	var chance := 0.10 + float(maxi(0, unlock - 10)) / 90.0 * 0.20
	if randf() >= chance:
		return {}
	return {"kind": ATTACK_MOVE_STATUS_TABLE[unlock]}

## NPC 版“已解锁招式”：theme→kind 映射与触发概率须与玩家侧
## SkillSystem.unlocked_moves()/player_attack 保持一致，否则双方招式手感会不对称。
func _npc_move(npc: Dictionary, kind: String) -> Dictionary:
	var moves: Array = []
	var skill_levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		var theme_kind: String = str({"code": "attack", "tune": "dodge", "parry": "parry"}.get(str(definition.get("theme", "")), ""))
		if theme_kind != kind:
			continue
		var current := int(skill_levels.get(str(skill_id), 0))
		for move in definition.get("moves", []):
			if current >= int(move.get("unlockLevel", 0)):
				moves.append({"name": move.get("name", "招式"), "level": current, "unlock": int(move.get("unlockLevel", 0))})
	if moves.is_empty() or randf() >= minf(MOVE_TRIGGER_CAP, MOVE_TRIGGER_BASE + moves.size() * MOVE_TRIGGER_PER_MOVE):
		return {}
	return _weighted_pick(moves)

func enemy_action(session: Dictionary) -> Dictionary:
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
		return _enemy_use_ult(session, affordable[0])

	return enemy_attack(session)

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

func _enemy_use_ult(session: Dictionary, ult: Dictionary) -> Dictionary:
	var turn_check := start_turn(session, "enemy")
	if not turn_check.can_act:
		return {"ok": false, "skipped": true, "damage": 0, "message": turn_check.message}
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var cost := int(ult.get("mp_cost", 0))
	if int(session.enemy_mp) < cost:
		return enemy_attack(session)
	session.enemy_mp = int(session.enemy_mp) - cost
	var base_power := _enemy_attack_power(session.enemy)
	var kind := str(ult.get("kind", "hugeDamage"))
	var tier := int(ult.get("tier", 1))
	var hit_bonus := float(ULT_HIT_BONUS.get(kind, 0.0))
	var total_damage := 0
	var landed := 0
	var defense := _player_defense()
	if kind == "multi":
		var hits := ULT_MULTI_HITS_TIER1 if tier == 1 else ULT_MULTI_HITS_TIER2
		for _index in hits:
			var hit := GameState.resolve_attack(base_power * (ULT_MULTI_POWER_TIER1 if tier == 1 else ULT_MULTI_POWER_TIER2), enemy_attributes, player_attributes, defense, hit_bonus)
			if hit.hit:
				landed += 1
				total_damage += int(hit.damage)
	elif kind == "abnormal":
		var abnormal := GameState.resolve_attack(base_power * (ULT_ABNORMAL_POWER_TIER1 if tier == 1 else ULT_ABNORMAL_POWER_TIER2), enemy_attributes, player_attributes, defense, hit_bonus)
		if abnormal.hit:
			landed = 1
			total_damage = int(abnormal.damage)
			if randf() < (ULT_ABNORMAL_PARALYZE_CHANCE_TIER1 if tier == 1 else ULT_ABNORMAL_PARALYZE_CHANCE_TIER2):
				add_status(session, "player", "paralysis", 1 if tier == 1 else randi_range(1, 2))
	elif kind == "reduceMax":
		var reduced := GameState.resolve_attack(base_power * (ULT_REDUCE_MAX_POWER_TIER1 if tier == 1 else ULT_REDUCE_MAX_POWER_TIER2), enemy_attributes, player_attributes, defense, hit_bonus)
		if reduced.hit:
			landed = 1
			total_damage = int(reduced.damage)
			var ratio := ULT_REDUCE_MAX_RATIO_TIER1 if tier == 1 else ULT_REDUCE_MAX_RATIO_TIER2
			session.player_max_hp = maxi(1, int(floor(float(session.get("player_max_hp", _player_hp_max())) * (1.0 - ratio))))
			session.player_hp = mini(int(session.player_hp), int(session.player_max_hp))
	else:
		var huge := GameState.resolve_attack(base_power * (ULT_HUGE_DAMAGE_POWER_TIER1 if tier == 1 else ULT_HUGE_DAMAGE_POWER_TIER2), enemy_attributes, player_attributes, defense, hit_bonus)
		if huge.hit:
			landed = 1
			total_damage = int(huge.damage)
	GameState.combat_state.hp = maxi(0, int(GameState.combat_state.hp) - total_damage)
	session.player_hp = GameState.combat_state.hp
	_track_player_state(session)
	session.log.append("%s：%d 伤害" % [ult.get("name", "敌方绝招"), total_damage])
	return {"ok": true, "damage": total_damage, "landed": landed, "ult": ult}

func use_item(session: Dictionary, item_id: String) -> Dictionary:
	var result: Dictionary = InventorySystem.use_item(item_id)
	if result.ok:
		session.player_hp = GameState.combat_state.hp
		session.log.append(result.message)
	return result

func rest(session: Dictionary) -> Dictionary:
	var amount := mini(int(GameState.combat_state.mp), maxi(0, _player_hp_max() - int(GameState.combat_state.hp)))
	if amount <= 0:
		return {"ok": false, "message": "没有可用于摸鱼的精力"}
	GameState.combat_state.mp -= amount
	GameState.combat_state.hp += amount
	session.player_hp = GameState.combat_state.hp
	session.log.append("你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount])
	return {"ok": true, "message": "你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount], "amount": amount}

func start_turn(session: Dictionary, side: String) -> Dictionary:
	var status_key := "player_status" if side == "player" else "enemy_status"
	var statuses: Dictionary = session.get(status_key, {})
	var message := ""
	if int(statuses.get("poison", 0)) > 0:
		# 中毒按当前体力上限的比例扣减上限本身（不直接伤及体力/伤势），与参考项目一致。
		if side == "player":
			var player_max := maxi(1, int(session.get("player_max_hp", _player_hp_max())))
			var drain := maxi(1, int(floor(float(player_max) * 0.10)))
			session.player_max_hp = maxi(1, player_max - drain)
			GameState.combat_state.hp = mini(int(GameState.combat_state.hp), int(session.player_max_hp))
			session.player_hp = GameState.combat_state.hp
			message = "中毒发作，体力上限 -%d" % drain
		else:
			var enemy_max := maxi(1, int(session.get("enemy_max_hp", session.get("enemy_hp", 1))))
			var enemy_drain := maxi(1, int(floor(float(enemy_max) * 0.10)))
			session.enemy_max_hp = maxi(1, enemy_max - enemy_drain)
			session.enemy_hp = mini(int(session.enemy_hp), int(session.enemy_max_hp))
			message = "中毒发作，体力上限 -%d" % enemy_drain
	# 是否跳过本回合取值须在倒计时递减前读取，否则麻痹只剩 1 回合时会在本回合
	# 就被清空而不生效——先判定跳过，再统一递减/清除各状态的剩余回合。
	var skipped := int(statuses.get("paralysis", 0)) > 0
	for status in statuses.keys():
		statuses[status] = int(statuses[status]) - 1
		if int(statuses[status]) <= 0:
			statuses.erase(status)
	session[status_key] = statuses
	if skipped:
		return {"can_act": false, "message": (message + "，" if not message.is_empty() else "") + "麻痹无法行动"}
	return {"can_act": true, "message": message}

func add_status(session: Dictionary, side: String, status: String, turns: int) -> void:
	var key := "player_status" if side == "player" else "enemy_status"
	var statuses: Dictionary = session.get(key, {})
	statuses[status] = maxi(int(statuses.get(status, 0)), turns)
	session[key] = statuses

func _track_player_state(session: Dictionary) -> void:
	var hp := int(GameState.combat_state.hp)
	var maximum := maxi(1, int(session.get("player_max_hp", _player_hp_max())))
	if hp <= 0:
		session.player_reached_zero = true
	elif hp <= int(floor(float(maximum) * 0.15)):
		session.player_near_death = true

func use_ult(session: Dictionary, ult_index: int = 0) -> Dictionary:
	var ults: Array = SkillSystem.unlocked_ults()
	if ult_index < 0 or ult_index >= ults.size():
		return {"ok": false, "message": "没有可用绝招"}
	var ult: Dictionary = ults[ult_index]
	var cost := int(ult.get("mp_cost", 0))
	if int(GameState.combat_state.get("mp", 0)) < cost:
		return {"ok": false, "message": "精力不足"}
	GameState.combat_state.mp = int(GameState.combat_state.mp) - cost
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var enemy_equipment := _npc_equipment_bonus(session.enemy)
	var defense := GameState.defense_base(float(enemy_attributes.get("constitution", 0))) + float(enemy_equipment.get("defense", 0))
	var base_power := _player_attack_power()
	var kind := str(ult.get("kind", "hugeDamage"))
	var hit_bonus := float(ULT_HIT_BONUS.get(kind, 0.0))
	var total_damage := 0
	var landed := 0
	if kind == "multi":
		var hits := ULT_MULTI_HITS_TIER1 if int(ult.tier) == 1 else ULT_MULTI_HITS_TIER2
		for _index in hits:
			var hit: Dictionary = GameState.resolve_attack(base_power * (ULT_MULTI_POWER_TIER1 if int(ult.tier) == 1 else ULT_MULTI_POWER_TIER2), GameState.profile.get("attributes", {}), enemy_attributes, defense, hit_bonus)
			if hit.hit:
				landed += 1
				total_damage += int(hit.damage)
	elif kind == "abnormal":
		var abnormal: Dictionary = GameState.resolve_attack(base_power * (ULT_ABNORMAL_POWER_TIER1 if int(ult.tier) == 1 else ULT_ABNORMAL_POWER_TIER2), GameState.profile.get("attributes", {}), enemy_attributes, defense, hit_bonus)
		if abnormal.hit:
			landed = 1
			total_damage = int(abnormal.damage)
			if randf() < (ULT_ABNORMAL_PARALYZE_CHANCE_TIER1 if int(ult.tier) == 1 else ULT_ABNORMAL_PARALYZE_CHANCE_TIER2): session.enemy_status.paralysis = 1 if int(ult.tier) == 1 else randi_range(1, 2)
	elif kind == "reduceMax":
		var reduced: Dictionary = GameState.resolve_attack(base_power * (ULT_REDUCE_MAX_POWER_TIER1 if int(ult.tier) == 1 else ULT_REDUCE_MAX_POWER_TIER2), GameState.profile.get("attributes", {}), enemy_attributes, defense, hit_bonus)
		if reduced.hit:
			landed = 1
			total_damage = int(reduced.damage)
			var ratio := ULT_REDUCE_MAX_RATIO_TIER1 if int(ult.tier) == 1 else ULT_REDUCE_MAX_RATIO_TIER2
			session.enemy_max_hp = maxi(1, int(floor(float(session.enemy_max_hp) * (1.0 - ratio))))
			session.enemy_hp = mini(session.enemy_hp, session.enemy_max_hp)
	else:
		var huge: Dictionary = GameState.resolve_attack(base_power * (ULT_HUGE_DAMAGE_POWER_TIER1 if int(ult.tier) == 1 else ULT_HUGE_DAMAGE_POWER_TIER2), GameState.profile.get("attributes", {}), enemy_attributes, defense, hit_bonus)
		if huge.hit:
			landed = 1
			total_damage = int(huge.damage)
	session.enemy_hp = maxi(0, int(session.enemy_hp) - total_damage)
	var log_line := "%s：%d 伤害" % [ult.get("name", "绝招"), total_damage]
	if kind == "multi": log_line += "（%d 击命中）" % landed
	session.log.append(log_line)
	return {"ok": true, "damage": total_damage, "landed": landed, "ult": ult}

## 逃跑成功率恒定夹在 [10%, 90%] 之间：再悬殊的身法差距也留一线生机/风险。
func flee(session: Dictionary) -> bool:
	var self_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_attributes: Dictionary = session.enemy.get("attributes", {})
	var rate := clampf(FLEE_BASE + (float(self_attributes.get("agility", 0)) - float(enemy_attributes.get("agility", 0))) * FLEE_PER_AGILITY, 0.10, 0.90)
	return randf() < rate

func _initiative(player: Dictionary, enemy: Dictionary) -> bool:
	if int(player.get("agility", 0)) != int(enemy.get("agility", 0)):
		return int(player.get("agility", 0)) > int(enemy.get("agility", 0))
	return randf() >= 0.5

func _hp_max(attributes: Dictionary, mp_max: int) -> int:
	return GameState.hp_max_with_mp_boost(float(attributes.get("constitution", 0)), mp_max)

func _player_hp_max() -> int:
	return GameState.player_effective_hp_max()

func _player_attack_power() -> float:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	var bonus: Dictionary = SkillSystem.combat_bonus()
	return maxf(1.0, GameState.attack_base(float(attributes.get("strength", 0))) + float(bonus.get("attack", 0.0)) + float(InventorySystem.equipment_bonus().get("attack", 0)))

func _player_defense() -> float:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	return GameState.defense_base(float(attributes.get("constitution", 0))) + float(SkillSystem.combat_bonus().get("defense", 0.0)) + float(InventorySystem.equipment_bonus().get("defense", 0))

func _enemy_attack_power(enemy: Dictionary) -> float:
	return maxf(1.0, GameState.attack_base(float(enemy.get("attributes", {}).get("strength", 1))) + float(_npc_equipment_bonus(enemy).get("attack", 0)))

func _npc_equipment_bonus(npc: Dictionary) -> Dictionary:
	var total := {"attack": 0, "defense": 0, "hit": 0, "dodge": 0, "crit": 0, "woundInflict": 0, "parry": 0}
	for item_id in npc.get("equipment", []):
		var bonus: Dictionary = DataRegistry.get_item(str(item_id)).get("equipmentBonus", {})
		for key in total:
			total[key] = int(total[key]) + int(bonus.get(key, 0))
	return total
