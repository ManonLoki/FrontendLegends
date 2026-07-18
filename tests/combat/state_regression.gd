extends RefCounted
## 战败降级与毒发后的恢复行动：派生四维与体力/精力上限必须在保存/结算前同步归一化。

static func post_start_recovery_result(root: Node) -> Dictionary:
	var state = root.get_node("GameState")
	var combat = root.get_node("CombatSystem")
	state.create_profile("恢复行动归一化", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	state.combat_state.hp = 95
	state.combat_state.mp = 50
	var session: Dictionary = combat.create_session("ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1", true)
	session.player_max_hp = 100
	session.player_hp = 95
	session.player_status = {"poison": 1}
	var result: Dictionary = combat.rest(session)
	return {
		"skipped": bool(result.get("skipped", false)),
		"message": str(result.get("message", "")),
		"status_empty": session.player_status.is_empty(),
		"mp": int(state.combat_state.mp),
	}

static func defeat_downgrade_result(root: Node) -> Dictionary:
	var state = root.get_node("GameState")
	var skills = root.get_node("SkillSystem")
	var resolver = root.get_node("BattleResolve")
	state.create_profile("降级归一化", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	var skill_state: Dictionary = skills.ensure_skills()
	skill_state.levels = {"dcebef7e-09b8-5a69-8e3d-159cb2b0c355": 10}
	skill_state.equipped_basic = {"arch": "dcebef7e-09b8-5a69-8e3d-159cb2b0c355"}
	skill_state.equipped_special = {}
	skills.refresh_derived_attributes()
	state.profile.vitals.cultivation = 0
	state.profile.vitals.money = 100
	state.profile.vitals.potential = 100
	state.profile.vitals.experience = 100
	state.combat_state.injury = 0
	state.combat_state.mp = state.player_mp_max()
	var initial_hp: int = state.player_effective_hp_max()
	state.combat_state.hp = 0
	seed(2)
	resolver.resolve_defeat({"initial_player_hp": initial_hp, "player_in_battle_injury": 0}, true)
	return {
		"level": int(skills.level("dcebef7e-09b8-5a69-8e3d-159cb2b0c355")),
		"constitution": int(state.profile.attributes.constitution),
		"mp": int(state.combat_state.mp),
		"mp_max": int(state.player_mp_max()),
		"hp": int(state.combat_state.hp),
		"hp_max": int(state.player_effective_hp_max()),
	}
