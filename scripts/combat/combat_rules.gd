extends RefCounted
## 无战斗流程状态的规则集合：会话初值、招式抽取、伤势判定与数值查询。

const MOVE_TRIGGER_BASE := 0.15
const MOVE_TRIGGER_PER_MOVE := 0.02
const MOVE_TRIGGER_CAP := 0.35
const ATTACK_MOVE_STATUS_TABLE := {10: "paralysis", 50: "weakness", 100: "poison"}

func create_session(enemy_id: String, lethal: bool = true) -> Dictionary:
	var enemy: Dictionary = NpcSystem.build_instance(enemy_id)
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var enemy_attributes: Dictionary = enemy.get("attributes", {})
	var enemy_mp_max := npc_mp_max(enemy)
	return {
		"enemy_id": enemy_id,
		"enemy": enemy,
		"player_hp": int(GameState.combat_state.get("hp", 1)),
		"lethal": lethal,
		"player_true_max_hp": GameState.player_hp_max(),
		"player_max_hp": GameState.player_effective_hp_max(),
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
	var total := maxi(0, int(npc.get("mp", 0)))
	var levels: Dictionary = npc.get("skillLevels", {})
	for skill_id in npc.get("equippedSkillIds", []):
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		total += int(definition.get("combat", {}).get("mpMaxPerLv", 0)) * int(levels.get(str(skill_id), 0))
	return total

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
		var theme_kind: String = str({"code": "attack", "tune": "dodge", "parry": "parry"}.get(str(definition.get("theme", "")), ""))
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
	return GameState.player_effective_hp_max()

func player_attack_power() -> float:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	return maxf(1.0, GameState.attack_base(float(attributes.get("strength", 0))) + float(InventorySystem.equipment_bonus().get("attack", 0)))

func player_name() -> String:
	return str(GameState.profile.get("name", "玩家"))

func player_defense() -> float:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	return GameState.defense_base(float(attributes.get("constitution", 0))) + SkillSystem.best_combat_bonus("defPerLv") + float(InventorySystem.equipment_bonus().get("defense", 0))

func enemy_attack_power(enemy: Dictionary) -> float:
	return maxf(1.0, GameState.attack_base(float(enemy.get("attributes", {}).get("strength", 1))) + float(npc_equipment_bonus(enemy).get("attack", 0)))

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
	var total := {"attack": 0, "defense": 0, "hit": 0, "dodge": 0, "crit": 0, "woundInflict": 0, "parry": 0}
	for item_id in npc.get("equipment", []):
		var bonus: Dictionary = DataRegistry.get_item(str(item_id)).get("equipmentBonus", {})
		for key in total:
			total[key] = int(total[key]) + int(bonus.get(key, 0))
	return total
