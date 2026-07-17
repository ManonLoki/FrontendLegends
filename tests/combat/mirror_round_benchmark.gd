extends RefCounted
## 同属性同功法的标准镜像战：忽略闪避、装备、道具、加力与主动招式，
## 每回合双方至多各命中一次普通攻击；保留暴击、招架、减伤和伤害浮动。

const BASIC := ["basicStrength", "basicAgility", "basicConstitution", "basicParry"]
const SECT_LOADOUTS := {
	"NG": {
		"sect": "NG神教",
		"skills": ["ng_code_decorator", "ng_tune_rx_step", "ng_arch_zone", "ng_parry_interceptor"],
		"seed_offset": 0,
	},
	"React": {
		"sect": "量子仙宗",
		"skills": ["react_code_jsx", "react_tune_virtual", "react_arch_state", "react_parry_boundary"],
		"seed_offset": 1,
	},
	"Vue": {
		"sect": "鱿鱼山庄",
		"skills": ["vue_code_template", "vue_tune_router", "vue_arch_reactive", "vue_parry_keepalive"],
		"seed_offset": 2,
	},
	"Vanilla": {
		"sect": "香草派",
		"skills": ["vanilla_code_dom", "vanilla_tune_event_loop", "vanilla_arch_closure", "vanilla_parry_prevent"],
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
			"code": "basicStrength", "tune": "basicAgility",
			"arch": "basicConstitution", "parry": "basicParry",
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
