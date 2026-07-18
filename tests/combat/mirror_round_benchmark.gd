extends RefCounted
## 同属性同功法的标准镜像战：忽略闪避、装备、道具、加力与主动招式，
## 每回合双方至多各命中一次普通攻击；保留暴击、招架、减伤和伤害浮动。

const BASIC := ["2224675d-63f2-50e8-a2c6-064acd5c5623", "af088f07-4c52-5a8c-aa16-df96e6b3e056", "dcebef7e-09b8-5a69-8e3d-159cb2b0c355", "74903f7d-7f7f-52c2-a6da-b3f4b12b97f2"]
const SECT_LOADOUTS := {
	"NG": {
		"sect": "NG神教",
		"skills": ["bcb538e2-4d6a-52ae-990d-20377e27ab64", "4d75539d-7873-5039-a596-d3dacc29c4d1", "9287473e-59a9-5dc8-a914-324ec57ffc14", "394fdd1b-c49d-52fc-a31b-41adf88a32d6"],
		"seed_offset": 0,
	},
	"React": {
		"sect": "量子仙宗",
		"skills": ["31cae377-72c7-5210-affd-b738c917c6d4", "ba00f74e-8309-5097-a096-a6145dc5fb6e", "d6bd0498-0551-54de-b5bf-1ededfe9aa06", "6e43fafa-2f44-58c1-ad30-1e8bd86b2a14"],
		"seed_offset": 1,
	},
	"Vue": {
		"sect": "鱿鱼山庄",
		"skills": ["bf405613-2fce-5cdd-9106-6936c89b036f", "59972225-62ad-5180-844f-17e05b24b55c", "f135d54a-b891-5b4e-a7b2-bbd3c3d824fc", "67ba1dea-3c4a-5bf2-ada5-57c98551e9c2"],
		"seed_offset": 2,
	},
	"Vanilla": {
		"sect": "香草派",
		"skills": ["b9814e27-ea44-5a59-83fb-d452b79ee0f1", "0bd48657-0a35-5ec5-9068-adc9762736d8", "bf770011-a135-56d5-8537-ee85f77df325", "d2f9550c-9725-56a5-8929-363aed058324"],
		"seed_offset": 3,
	},
}

static func run(root: Node, levels: Array[int], trials: int) -> Dictionary:
	var results: Dictionary = {}
	for sect_key in SECT_LOADOUTS:
		var sect_results: Dictionary = {}
		for level in levels:
			sect_results[level] = _run_level(root, str(sect_key), SECT_LOADOUTS[sect_key], level, trials)
		results[sect_key] = sect_results
	return results

static func _run_level(root: Node, sect_key: String, loadout: Dictionary, level: int, trials: int) -> Dictionary:
	var state = root.get_node("GameState")
	var combat = root.get_node("CombatSystem")
	var npc_system = root.get_node("NpcSystem")
	var skills = root.get_node("SkillSystem")
	state.delete_save()
	state.create_profile("镜像测试", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	state.profile.sect = str(loadout.sect)
	var special_skills: Array = loadout.skills
	var all_skills: Array = BASIC + special_skills
	var skill_state: Dictionary = skills.ensure_skills()
	if level > 0:
		for skill_id in all_skills:
			skill_state.levels[skill_id] = level
		skill_state.equipped_basic = {
			"code": "2224675d-63f2-50e8-a2c6-064acd5c5623", "tune": "af088f07-4c52-5a8c-aa16-df96e6b3e056",
			"arch": "dcebef7e-09b8-5a69-8e3d-159cb2b0c355", "parry": "74903f7d-7f7f-52c2-a6da-b3f4b12b97f2",
		}
		skill_state.equipped_special = {
			"code": special_skills[0], "tune": special_skills[1],
			"arch": special_skills[2], "parry": special_skills[3],
		}
		skills.refresh_derived_attributes()
	var attributes: Dictionary = state.profile.attributes.duplicate(true)
	var inner_power := level * 3
	state.profile.vitals.cultivation = int(floor(float(inner_power) * skills.MEDITATION_INNER_POWER_UNIT * state.meditation_modifier(float(attributes.constitution))))
	state.combat_state.injury = 0
	state.combat_state.mp = state.player_mp_max()
	state.combat_state.hp = state.player_hp_max()
	var mirror_id := "__mirror_round_%s_%d" % [sect_key.to_lower(), level]
	var npc_levels: Dictionary = {}
	for skill_id in all_skills:
		if level > 0:
			npc_levels[skill_id] = level
	npc_system.register_runtime(mirror_id, {
		"displayName": "镜像",
		"age": 18,
		"roles": ["civilian"],
		"combatRank": "veteran",
		"combatRole": "balanced",
		"attributes": attributes.duplicate(true),
		"skillLevels": npc_levels,
		"equippedSkillIds": all_skills.duplicate() if level > 0 else [],
		"equipment": [],
		"ai": {"restCharges": 0, "forceUseRate": 0.0},
	})
	var enemy: Dictionary = npc_system.build_instance(mirror_id)
	var player_bonus: Dictionary = skills.combat_bonus()
	var enemy_bonus: Dictionary = combat.rules.npc_combat_bonus(enemy)
	var hp_max: int = int(state.player_hp_max())
	var enemy_hp_max: int = int(combat.rules.npc_hp_max(enemy))
	var player := {
		"hp": hp_max,
		"attack": state.attack_base(float(attributes.strength)) + float(player_bonus.get("attack", 0)),
		"defense": state.defense_base(float(attributes.constitution)) + float(player_bonus.get("defense", 0)),
		"parry_bonus": float(player_bonus.get("parry", 0)) * 0.01,
	}
	var enemy_stats := {
		"hp": enemy_hp_max,
		"attack": state.attack_base(float(attributes.strength)) + float(enemy_bonus.get("attack", 0)),
		"defense": state.defense_base(float(attributes.constitution)) + float(enemy_bonus.get("defense", 0)),
		"parry_bonus": float(enemy_bonus.get("parry", 0)) * 0.01,
	}
	var rounds: Array[int] = []
	for trial in trials:
		seed(900000 + int(loadout.seed_offset) * 100000 + level * 1000 + trial)
		rounds.append(_duel_rounds(state, player, enemy_stats, attributes))
	rounds.sort()
	npc_system.unregister_runtime(mirror_id)
	return {"p10": _percentile(rounds, 0.10), "median": _percentile(rounds, 0.50), "p90": _percentile(rounds, 0.90), "player_hp": hp_max, "enemy_hp": enemy_hp_max}

static func _duel_rounds(state: Node, player: Dictionary, enemy: Dictionary, attributes: Dictionary) -> int:
	var player_hp := int(player.hp)
	var enemy_hp := int(enemy.hp)
	var count := 0
	while player_hp > 0 and enemy_hp > 0 and count < 100:
		count += 1
		enemy_hp -= _landed_damage(state, player, enemy, attributes)
		if enemy_hp <= 0:
			break
		player_hp -= _landed_damage(state, enemy, player, attributes)
	return count

static func _landed_damage(state: Node, attacker: Dictionary, defender: Dictionary, attributes: Dictionary) -> int:
	return int(state.resolve_landed_attack(float(attacker.attack), attributes, attributes, float(defender.defense), float(defender.parry_bonus)).damage)

static func _percentile(values: Array[int], ratio: float) -> int:
	var index := clampi(int(ceil(float(values.size()) * ratio)) - 1, 0, values.size() - 1)
	return values[index]
