extends RefCounted
## 技能训练与内息恢复领域服务。只通过 SkillSystem 的窄接口访问技能状态。

const MEDITATION_TICK_SECONDS := 1.0 / 30.0
const PRACTICE_TICK_SECONDS := 1.0 / 5.0
const MEDITATION_INNER_POWER_UNIT := 25.0
const HEAL_INJURY_ARCH_LEVEL_GATE := 30
const HEAL_INJURY_MP_PER_POINT := 5

var skills: Node

func _init(skill_system: Node) -> void:
	skills = skill_system

func meditation_cap() -> int:
	var constitution := float(GameState.profile.get("attributes", {}).get("constitution", 0))
	return meditation_cap_from_values(constitution, skills.level("basicConstitution"), equipped_sect_skill_level("arch"))

func meditation_cap_from_values(constitution: float, basic_arch_level: int, advanced_arch_level: int) -> int:
	var modifier := GameState.meditation_modifier(constitution)
	var inner_power := maxi(0, basic_arch_level) + maxi(0, advanced_arch_level) * 2
	return maxi(0, int(floor(float(inner_power) * MEDITATION_INNER_POWER_UNIT * modifier)))

func meditation_max_mp_cap() -> int:
	return meditation_cap() * GameState.MP_PER_CULTIVATION

func meditate_tick() -> Dictionary:
	if not can_meditate():
		return {"ok": false, "message": "须装备基础架构与本门架构高级功法，方可冥想。"}
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var constitution := float(GameState.profile.get("attributes", {}).get("constitution", 0))
	var modifier := GameState.meditation_modifier(constitution)
	var cap := meditation_cap()
	var cultivation := int(vitals.get("cultivation", 0))
	var maximum := GameState.player_mp_max()
	if cultivation >= cap and int(GameState.combat_state.mp) >= maximum:
		return {"ok": false, "message": "冥想已满，无需继续冥想。"}
	GameState.combat_state.mp = mini(maximum, int(GameState.combat_state.mp) + maxi(1, int(floor(5.0 * modifier))))
	if int(GameState.combat_state.mp) >= maximum:
		if cultivation < cap:
			GameState.combat_state.mp = 0
			vitals.cultivation = mini(cap, cultivation + 1)
			GameState.profile.vitals = vitals
			GameState.advance_time(MEDITATION_TICK_SECONDS)
			if vitals.cultivation >= cap:
				return {"ok": true, "message": "冥想圆满，精力最大值提升至 %d，已达内功所限。" % vitals.cultivation}
			return {"ok": true, "message": "冥想圆满，精力最大值提升至 %d。" % vitals.cultivation}
		return {"ok": false, "message": "冥想已满，无需继续冥想。"}
	GameState.advance_time(MEDITATION_TICK_SECONDS)
	return {"ok": true, "message": "你凝神冥想，当前精力 %d / %d。" % [GameState.combat_state.mp, maximum]}

func meditation_progress() -> Dictionary:
	return {
		"current": maxi(0, int(GameState.combat_state.get("mp", 0))),
		"total": maxi(1, GameState.player_mp_max()),
	}

func equipped_sect_skill_level(theme: String) -> int:
	var skill_id: String = skills.equipped_id(theme, "sect")
	var definition := DataRegistry.get_skill(skill_id)
	if str(definition.get("category", "")) != "sect" or str(definition.get("theme", "")) != theme or str(definition.get("sect", "")) != str(GameState.profile.get("sect", "")):
		return 0
	return skills.level(skill_id)

func can_meditate() -> bool:
	var basic_arch_id: String = skills.equipped_id("arch", "basic")
	return basic_arch_id == "basicConstitution" and skills.level(basic_arch_id) > 0 and equipped_sect_skill_level("arch") > 0

func practice_cap(skill_id: String) -> int:
	var definition: Dictionary = DataRegistry.get_skill(skill_id)
	if definition.is_empty() or str(definition.get("category", "")) != "sect" or str(definition.get("theme", "")) == "arch":
		return 0
	var basic_id: String = str({"code": "basicStrength", "tune": "basicAgility", "parry": "basicParry", "knowledge": "literacy"}.get(str(definition.get("theme", "")), ""))
	return mini(int(definition.get("maxLevel", 100)), mini(skills.level(basic_id), GameState.player_mp_max()))

func practice_tick(skill_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_skill(skill_id)
	if definition.is_empty() or str(definition.get("category", "")) != "sect" or str(definition.get("theme", "")) == "arch":
		return {"ok": false, "message": "这门功法不能这样练。", "reason": "invalid"}
	if str(definition.get("sect", "")) != str(GameState.profile.get("sect", "")) or skills.level(skill_id) <= 0:
		return {"ok": false, "message": "尚未学会本门这门功法。", "reason": "invalid"}
	var skill_state: Dictionary = skills.ensure_skills()
	var basic_id: String = str({"code": "basicStrength", "tune": "basicAgility", "parry": "basicParry", "knowledge": "literacy"}.get(str(definition.get("theme", "")), ""))
	var cap := practice_cap(skill_id)
	var current: int = skills.level(skill_id)
	if current >= cap:
		var basic_level: int = skills.level(basic_id)
		var mp_max := GameState.player_mp_max()
		var cap_reason := "精力修为不足，须多冥想积累内力。" if cap >= mp_max and cap < basic_level else "须提升基础功法等级。"
		return {"ok": false, "message": "【%s】已到当前上限 %d 级，%s" % [definition.get("name", skill_id), cap, cap_reason], "reason": "cap"}
	var progress: Dictionary = skill_state.get("practiceProgress", {})
	var required: int = skills.skill_exp_required(skill_id, current + 1)
	var current_progress := mini(required, maxi(0, int(progress.get(skill_id, 0))))
	var gain_per_tick := maxi(1, int(floor(float(GameState.profile.get("attributes", {}).get("wisdom", 1)) / 5.0)))
	var gain := mini(gain_per_tick, required - current_progress)
	var mp_cost := 2 if gain > 0 else 0
	var hp_cost := maxi(0, int(ceil(float(current_progress + gain) * 0.8)) - int(ceil(float(current_progress) * 0.8)))
	if int(GameState.combat_state.mp) < mp_cost:
		return {"ok": false, "message": "精力不足，练不动功。", "reason": "resource"}
	if int(GameState.combat_state.hp) - hp_cost < 1:
		return {"ok": false, "message": "体力不足，练不动功。", "reason": "resource"}
	GameState.combat_state.mp -= mp_cost
	GameState.combat_state.hp -= hp_cost
	GameState.advance_time(PRACTICE_TICK_SECONDS)
	var next_progress := current_progress + gain
	var gained_level := false
	if next_progress >= required:
		skill_state.levels[skill_id] = current + 1
		progress[skill_id] = 0
		skills.refresh_derived_attributes()
		gained_level = true
	else:
		progress[skill_id] = next_progress
	skill_state.practiceProgress = progress
	var shown_progress := int(progress.get(skill_id, 0))
	var shown_required: int = skills.skill_exp_required(skill_id, skills.level(skill_id) + 1)
	var suffix := "，已达当前上限 %d 级" % cap if skills.level(skill_id) >= cap else "，进度 %d / %d" % [shown_progress, shown_required]
	var message := "你苦练【%s】，提升至 %d 级%s。" % [definition.get("name", skill_id), skills.level(skill_id), suffix] if gained_level else "你苦练【%s】%s。" % [definition.get("name", skill_id), suffix]
	return {"ok": true, "message": message, "level": skills.level(skill_id)}

func practice_progress(skill_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"current": 0, "total": 1, "level": 0}
	var current_level: int = skills.level(skill_id)
	return {
		"current": int(skills.ensure_skills().get("practiceProgress", {}).get(skill_id, 0)),
		"total": skills.skill_exp_required(skill_id, current_level + 1),
		"level": current_level,
	}

func channel_hp() -> Dictionary:
	var effective_max := GameState.player_effective_hp_max()
	var amount := mini(int(GameState.combat_state.mp), maxi(0, effective_max - int(GameState.combat_state.hp)))
	if amount <= 0:
		if int(GameState.combat_state.hp) >= effective_max:
			return {"ok": false, "message": "体力已满，不必摸鱼。"}
		return {"ok": false, "message": "精力不足，摸不了鱼。"}
	GameState.combat_state.mp -= amount
	GameState.combat_state.hp += amount
	GameState.advance_time(1.0)
	return {"ok": true, "message": "你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount]}

func heal_injury() -> Dictionary:
	var arch_sum: int = skills.arch_sect_level_sum()
	if arch_sum <= HEAL_INJURY_ARCH_LEVEL_GATE:
		return {"ok": false, "message": "内力尚浅（本门架构功法合计 %d 级，须超过 %d 级），无法疗伤。" % [arch_sum, HEAL_INJURY_ARCH_LEVEL_GATE]}
	var injury := int(GameState.combat_state.injury)
	if injury <= 0:
		return {"ok": false, "message": "并无伤势，无需疗伤。"}
	var amount := mini(injury, int(GameState.combat_state.mp) / HEAL_INJURY_MP_PER_POINT)
	if amount <= 0:
		return {"ok": false, "message": "精力不足（每 %d 精力愈合 1 点伤势），无法疗伤。" % HEAL_INJURY_MP_PER_POINT}
	GameState.combat_state.mp -= amount * HEAL_INJURY_MP_PER_POINT
	GameState.combat_state.injury -= amount
	GameState.advance_time(1.0)
	var effective_max := GameState.player_effective_hp_max()
	var suffix := "，余伤 %d 点" % GameState.combat_state.injury if GameState.combat_state.injury > 0 else "，伤势尽愈"
	return {"ok": true, "message": "你运转内息疗伤，消耗 %d 精力，愈合伤势 %d 点，体力上限恢复至 %d%s。" % [amount * HEAL_INJURY_MP_PER_POINT, amount, effective_max, suffix]}
