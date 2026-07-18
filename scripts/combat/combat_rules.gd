extends RefCounted
## 无战斗流程状态的规则集合：会话初值、招式抽取、伤势判定与数值查询。

const SKILL_MAPS := preload("res://scripts/skills/skill_maps.gd")
const EQUIPMENT_MATH := preload("res://scripts/equipment_math.gd")

## 未标注 combatRank 的人物一律按 veteran 结算生命与奖励缩放。
const DEFAULT_COMBAT_RANK := "veteran"
const RANK_NONCOMBATANT := "noncombatant"
## 普通战斗奖励 = 武学评级 ×（经验/潜能系数、Token 按 sqrt(评级)）× 阶位系数。
const COMBAT_REWARD_EXP_COEF := 0.45
const COMBAT_REWARD_POT_COEF := 0.15
const COMBAT_REWARD_MONEY_COEF := 1.60
## 加力增伤上限比例与递减软化常数（force/(force+softening)）。
const FORCE_DAMAGE_CAP := 0.75
const FORCE_SOFTENING := 100.0
const INNER_POWER_ATK_COEF := 4.0

## 进攻、闪避和招架招式使用不同触发曲线，避免命中后再次高概率完全落空。
const MOVE_TRIGGER_RULES := {
	"attack": {"base": 0.22, "per_move": 0.025, "cap": 0.45},
	"dodge": {"base": 0.12, "per_move": 0.015, "cap": 0.27},
	"parry": {"base": 0.18, "per_move": 0.020, "cap": 0.35},
}
const NPC_RANK_HP_SCALE := {
	"noncombatant": 0.50,
	"novice": 0.78,
	"trained": 0.92,
	"veteran": 1.00,
	"elite": 1.10,
	"master": 1.20,
	"legendary": 1.30,
}
const NPC_RANK_REWARD_SCALE := {
	"noncombatant": 0.15,
	"novice": 0.50,
	"trained": 0.75,
	"veteran": 1.00,
	"elite": 1.20,
	"master": 1.50,
	"legendary": 2.00,
}
## 十个招式档位中六个可附带异常；10/30/60/100 保持为纯伤害招式。
const ATTACK_MOVE_STATUS_TABLE := {
	20: "paralysis", 40: "weakness", 50: "poison",
	70: "paralysis", 80: "weakness", 90: "poison",
}

func create_session(enemy_id: String, lethal: bool = true) -> Dictionary:
	var enemy: Dictionary = NpcSystem.build_instance(enemy_id)
	var player_attributes := player_combat_attributes()
	var enemy_attributes := npc_combat_attributes(enemy)
	var enemy_mp_max := npc_mp_max(enemy)
	var enemy_hp_max := npc_hp_max(enemy, enemy_attributes, enemy_mp_max)
	var player_true_max_hp := hp_max(player_attributes, GameState.player_mp_max())
	var player_effective_max_hp := maxi(1, player_true_max_hp - int(GameState.combat_state.get("injury", 0)))
	return {
		"enemy_id": enemy_id,
		"enemy": enemy,
		"player_hp": int(GameState.combat_state.get("hp", 1)),
		"lethal": lethal,
		"player_true_max_hp": player_true_max_hp,
		"player_max_hp": player_effective_max_hp,
		"initial_player_hp": int(GameState.combat_state.get("hp", 1)),
		"player_mp": int(GameState.combat_state.get("mp", 0)),
		"enemy_hp": enemy_hp_max,
		"enemy_max_hp": enemy_hp_max,
		"enemy_mp": enemy_mp_max,
		"enemy_mp_max": enemy_mp_max,
		"player_status": {},
		"enemy_status": {},
		"player_reached_zero": false,
		"player_near_death": false,
		"player_in_battle_injury": 0,
		"turn": "player" if initiative(player_attributes, enemy_attributes) else "enemy",
		"log": [],
	}

func npc_mp_max(npc: Dictionary) -> int:
	var attributes := npc_combat_attributes(npc)
	var trained_mp := int(floor(float(npc_inner_power(npc)) * SkillSystem.MEDITATION_INNER_POWER_UNIT * GameState.meditation_modifier(float(attributes.get("constitution", 0)))))
	return maxi(0, trained_mp + int(npc_combat_bonus(npc).get("mp_max", 0)))

## NPC 等阶只缩放生命池，攻击、防御与命中仍由显式四维、功法和装备决定。
func npc_hp_max(npc: Dictionary, attributes: Dictionary = {}, mp_max := -1) -> int:
	var combat_attributes := attributes if not attributes.is_empty() else npc_combat_attributes(npc)
	var resolved_mp := npc_mp_max(npc) if mp_max < 0 else mp_max
	var rank := str(npc.get("combatRank", DEFAULT_COMBAT_RANK))
	var scale := float(NPC_RANK_HP_SCALE.get(rank, NPC_RANK_HP_SCALE[DEFAULT_COMBAT_RANK]))
	return maxi(1, int(round(float(hp_max(combat_attributes, resolved_mp)) * scale)))

func maybe_apply_in_battle_injury(session: Dictionary, result: Dictionary) -> String:
	if not bool(session.get("lethal", true)):
		return ""
	var damage := maxi(0, int(result.get("damage", 0)))
	var maximum := maxi(1, int(session.get("player_max_hp", player_hp_max())))
	var severity := float(damage) / float(maximum)
	if severity < 0.25:
		return ""
	var probability := minf(1.0, (severity - 0.25) / 0.25)
	if randf() >= probability:
		return ""
	var injury_delta := maxi(1, int(ceil(float(damage) * 0.30 * (1.0 - SkillSystem.injury_reduce()))))
	result.damage = maxi(1, int(floor(float(damage) * 0.85)))
	session.player_in_battle_injury = int(session.get("player_in_battle_injury", 0)) + injury_delta
	session.player_max_hp = maxi(1, maximum - injury_delta)
	GameState.combat_state.hp = mini(int(GameState.combat_state.hp), int(session.player_max_hp))
	return "（你受了伤，体力上限 −%d）" % injury_delta

func weight_of(move: Dictionary) -> int:
	return maxi(1, int(move.get("level", 0)) - int(move.get("unlock", 0)) + 1)

func weighted_pick(moves: Array) -> Dictionary:
	var total := 0
	for move in moves:
		total += weight_of(move)
	var roll := randi() % maxi(1, total)
	for move in moves:
		roll -= weight_of(move)
		if roll < 0:
			return move
	return moves[moves.size() - 1]

## 返回指定招式类型和已解锁数量对应的触发概率。
func move_trigger_rate(kind: String, move_count: int) -> float:
	var rule: Dictionary = MOVE_TRIGGER_RULES.get(kind, MOVE_TRIGGER_RULES.attack)
	return minf(float(rule.cap), float(rule.base) + maxi(0, move_count) * float(rule.per_move))

func roll_attack_move_status(move: Dictionary) -> Dictionary:
	var unlock := int(move.get("unlock", 0))
	if not ATTACK_MOVE_STATUS_TABLE.has(unlock):
		return {}
	var chance := 0.10 + float(maxi(0, unlock - 10)) / 90.0 * 0.20
	return {} if randf() >= chance else {"kind": ATTACK_MOVE_STATUS_TABLE[unlock]}

func status_name(kind: String) -> String:
	return str({"paralysis": "麻痹", "weakness": "虚弱", "poison": "中毒"}.get(kind, kind))

func npc_move(npc: Dictionary, kind: String) -> Dictionary:
	var moves: Array = []
	var skill_levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		var theme_kind: String = str(SKILL_MAPS.THEME_COMBAT_KIND.get(str(definition.get("theme", "")), ""))
		if theme_kind != kind:
			continue
		var current := int(skill_levels.get(str(skill_id), 0))
		for move in definition.get("moves", []):
			if current >= int(move.get("unlockLevel", 0)):
				moves.append({"name": move.get("name", "招式"), "level": current, "unlock": int(move.get("unlockLevel", 0)), "combat_effects": move.get("combatEffects", {})})
	if moves.is_empty() or randf() >= move_trigger_rate(kind, moves.size()):
		return {}
	return weighted_pick(moves)

func initiative(player: Dictionary, enemy: Dictionary) -> bool:
	var difference := float(player.get("agility", 0)) - float(enemy.get("agility", 0))
	var player_first_rate := clampf(0.50 + difference * 0.015, 0.20, 0.80)
	return randf() < player_first_rate

func hp_max(attributes: Dictionary, mp_max: int) -> int:
	return GameState.hp_max_with_mp_boost(float(attributes.get("constitution", 0)), mp_max)

func player_hp_max() -> int:
	return maxi(1, hp_max(player_combat_attributes(), GameState.player_mp_max()) - int(GameState.combat_state.get("injury", 0)))

func _attributes_with_bonus(base: Dictionary, bonus: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in ["strength", "agility", "constitution", "wisdom"]:
		result[key] = maxf(0.0, float(base.get(key, 0)) + float(bonus.get(key, 0)))
	return result

func player_combat_attributes() -> Dictionary:
	return _attributes_with_bonus(GameState.profile.get("attributes", {}), InventorySystem.equipment_attribute_bonus())

func npc_combat_attributes(npc: Dictionary) -> Dictionary:
	return _attributes_with_bonus(npc.get("attributes", {}), EQUIPMENT_MATH.sum_attribute_bonus(npc.get("equipment", [])))

func player_attack_power() -> float:
	var attributes := player_combat_attributes()
	return maxf(1.0, GameState.attack_base(float(attributes.get("strength", 0))) + float(SkillSystem.combat_bonus().get("attack", 0)) + float(InventorySystem.equipment_bonus().get("attack", 0)))

func player_name() -> String:
	return str(GameState.profile.get("name", "玩家"))

func player_defense() -> float:
	var attributes := player_combat_attributes()
	return GameState.defense_base(float(attributes.get("constitution", 0))) + float(SkillSystem.combat_bonus().get("defense", 0)) + float(InventorySystem.equipment_bonus().get("defense", 0))

func enemy_attack_power(enemy: Dictionary) -> float:
	return maxf(1.0, GameState.attack_base(float(npc_combat_attributes(enemy).get("strength", 1))) + float(npc_combat_bonus(enemy).get("attack", 0)) + float(npc_equipment_bonus(enemy).get("attack", 0)))

## 汇总 NPC 当前装备功法的全部战斗加成，与玩家 SkillSystem.combat_bonus 口径对称。
func npc_combat_bonus(npc: Dictionary) -> Dictionary:
	var result := {"attack": 0.0, "defense": 0.0, "hit": 0.0, "dodge": 0.0, "parry": 0.0, "mp_max": 0}
	var levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition := DataRegistry.get_skill(str(skill_id))
		var combat: Dictionary = definition.get("combat", {})
		var level := int(levels.get(str(skill_id), 0))
		result.attack += float(combat.get("atkPerLv", 0.0)) * level
		result.defense += float(combat.get("defPerLv", 0.0)) * level
		result.hit += float(combat.get("hitPerLv", 0.0)) * level
		result.dodge += float(combat.get("dodgePerLv", 0.0)) * level
		result.parry += float(combat.get("parryPerLv", 0.0)) * level
		result.mp_max += int(combat.get("mpMaxPerLv", 0)) * level
	return result

## 加力把本次已结算伤害按递减收益放大，最高额外增加 75%，不再线性叠加数百点。
func force_damage_bonus(damage: int, force: int) -> int:
	if damage <= 0 or force <= 0:
		return 0
	var ratio := minf(FORCE_DAMAGE_CAP, float(force) / (float(force) + FORCE_SOFTENING))
	return maxi(1, int(floor(float(damage) * ratio * randf_range(0.90, 1.10))))

## 绝招把内功值转换为平方根攻击加成，保留高阶优势并抑制一击溢出。
func inner_power_attack_bonus(inner_power: int) -> float:
	return floor(sqrt(float(maxi(0, inner_power))) * INNER_POWER_ATK_COEF)

func npc_inner_power(npc: Dictionary) -> int:
	var levels: Dictionary = npc.get("skillLevels", {})
	var total := int(levels.get("dcebef7e-09b8-5a69-8e3d-159cb2b0c355", 0))
	for skill_id in npc.get("equippedSkillIds", []):
		var definition := DataRegistry.get_skill(str(skill_id))
		if str(definition.get("category", "")) == "sect" and str(definition.get("theme", "")) == "arch":
			total += int(levels.get(str(skill_id), 0)) * 2
	return maxi(0, total)

func npc_equipment_bonus(npc: Dictionary) -> Dictionary:
	return EQUIPMENT_MATH.sum_equipment_bonus(npc.get("equipment", []))
