extends RefCounted
## 无战斗流程状态的规则集合：会话初值、招式抽取、伤势判定与数值查询。

const SKILL_MAPS := preload("res://scripts/skills/skill_maps.gd")
const EQUIPMENT_MATH := preload("res://scripts/equipment_math.gd")

## 与参照项目 SectMoves.ts 共用：25% 基础率，每个已解锁招式 +4%，封顶 55%。
const MOVE_TRIGGER_BASE := 0.25
const MOVE_TRIGGER_PER_MOVE := 0.04
const MOVE_TRIGGER_CAP := 0.55
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
		"enemy_hp": hp_max(enemy_attributes, enemy_mp_max),
		"enemy_max_hp": hp_max(enemy_attributes, enemy_mp_max),
		"enemy_mp": enemy_mp_max,
		"enemy_mp_max": enemy_mp_max,
		"player_status": {},
		"enemy_status": {},
		"player_reached_zero": false,
		"player_near_death": false,
		"player_damage_taken": 0,
		"player_in_battle_injury": 0,
		"turn": "player" if initiative(player_attributes, enemy_attributes) else "enemy",
		"log": [],
	}

func npc_mp_max(npc: Dictionary) -> int:
	var attributes := npc_combat_attributes(npc)
	return maxi(0, int(floor(float(npc_inner_power(npc)) * 25.0 * GameState.meditation_modifier(float(attributes.get("constitution", 0))))))

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
				moves.append({"name": move.get("name", "招式"), "level": current, "unlock": int(move.get("unlockLevel", 0))})
	if moves.is_empty() or randf() >= minf(MOVE_TRIGGER_CAP, MOVE_TRIGGER_BASE + moves.size() * MOVE_TRIGGER_PER_MOVE):
		return {}
	return weighted_pick(moves)

func initiative(player: Dictionary, enemy: Dictionary) -> bool:
	if int(player.get("agility", 0)) != int(enemy.get("agility", 0)):
		return int(player.get("agility", 0)) > int(enemy.get("agility", 0))
	var player_roll := float(player.get("agility", 0)) * randf_range(0.9, 1.1)
	var enemy_roll := float(enemy.get("agility", 0)) * randf_range(0.9, 1.1)
	return player_roll >= enemy_roll

func hp_max(attributes: Dictionary, mp_max: int) -> int:
	return GameState.hp_max_with_mp_boost(float(attributes.get("constitution", 0)), mp_max)

func player_hp_max() -> int:
	return maxi(1, hp_max(player_combat_attributes(), GameState.player_mp_max()) - int(GameState.combat_state.get("injury", 0)))

func _attributes_with_bonus(base: Dictionary, bonus: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in ["strength", "agility", "constitution", "wisdom"]:
		result[key] = maxi(0, int(base.get(key, 0)) + int(bonus.get(key, 0)))
	return result

func player_combat_attributes() -> Dictionary:
	return _attributes_with_bonus(GameState.profile.get("attributes", {}), InventorySystem.equipment_attribute_bonus())

func npc_combat_attributes(npc: Dictionary) -> Dictionary:
	return _attributes_with_bonus(npc.get("attributes", {}), EQUIPMENT_MATH.sum_attribute_bonus(npc.get("equipment", [])))

func player_attack_power() -> float:
	var attributes := player_combat_attributes()
	return maxf(1.0, GameState.attack_base(float(attributes.get("strength", 0))) + float(InventorySystem.equipment_bonus().get("attack", 0)))

func player_name() -> String:
	return str(GameState.profile.get("name", "玩家"))

func player_defense() -> float:
	var attributes := player_combat_attributes()
	return GameState.defense_base(float(attributes.get("constitution", 0))) + SkillSystem.best_combat_bonus("defPerLv") + float(InventorySystem.equipment_bonus().get("defense", 0))

func enemy_attack_power(enemy: Dictionary) -> float:
	return maxf(1.0, GameState.attack_base(float(npc_combat_attributes(enemy).get("strength", 1))) + float(npc_equipment_bonus(enemy).get("attack", 0)))

func npc_best_combat_bonus(npc: Dictionary, key: String) -> float:
	var best := 0.0
	var levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition := DataRegistry.get_skill(str(skill_id))
		if str(definition.get("category", "")) != "sect":
			continue
		best = maxf(best, float(definition.get("combat", {}).get(key, 0.0)) * int(levels.get(str(skill_id), 0)))
	return best

func npc_passive_parry(npc: Dictionary) -> float:
	var total := 0.0
	var levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition := DataRegistry.get_skill(str(skill_id))
		total += float(definition.get("combat", {}).get("parryPerLv", 0.0)) * int(levels.get(str(skill_id), 0))
	return total

func npc_inner_power(npc: Dictionary) -> int:
	var levels: Dictionary = npc.get("skillLevels", {})
	var total := int(levels.get("basicConstitution", 0))
	for skill_id in npc.get("equippedSkillIds", []):
		var definition := DataRegistry.get_skill(str(skill_id))
		if str(definition.get("category", "")) == "sect" and str(definition.get("theme", "")) == "arch":
			total += int(levels.get(str(skill_id), 0)) * 2
	return maxi(0, total)

func npc_equipment_bonus(npc: Dictionary) -> Dictionary:
	return EQUIPMENT_MATH.sum_equipment_bonus(npc.get("equipment", []))
