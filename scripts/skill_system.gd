extends Node

const THEMES := ["code", "tune", "arch", "parry", "knowledge"]

func create_default_skills() -> Dictionary:
	return {"levels": {"basicStrength": 1, "basicAgility": 1, "basicConstitution": 1, "basicParry": 1, "literacy": 1}, "equipped": {"code": "basicStrength", "tune": "basicAgility", "arch": "basicConstitution", "parry": "basicParry", "knowledge": "literacy"}, "progress": {}}

func ensure_skills() -> Dictionary:
	if not GameState.profile.has("skills") or GameState.profile.skills.is_empty():
		GameState.profile.skills = create_default_skills()
	var skills: Dictionary = GameState.profile.skills
	if not skills.has("levels"): skills.levels = {}
	if not skills.has("equipped"): skills.equipped = {}
	if not skills.has("progress"): skills.progress = {}
	return skills

func level(skill_id: String) -> int:
	return int(ensure_skills().levels.get(skill_id, 0))

func learn(skill_id: String) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"ok": false, "message": "未知功法"}
	var skills := ensure_skills()
	var required_sect := str(definition.get("requires", {}).get("sect", definition.get("sect", "")))
	if not required_sect.is_empty() and str(GameState.profile.get("sect", "")) != required_sect:
		return {"ok": false, "message": "未拜入%s，学不得【%s】" % [required_sect, definition.get("name", skill_id)]}
	var current := level(skill_id)
	var max_level := int(definition.get("maxLevel", 100))
	if current >= max_level:
		return {"ok": false, "message": "已达上限"}
	var cost := _cost(definition, current)
	var vitals: Dictionary = GameState.profile.vitals
	if int(vitals.get("potential", 0)) < cost:
		return {"ok": false, "message": "潜能不足，需要 %d" % cost}
	vitals.potential = int(vitals.get("potential", 0)) - cost
	skills.levels[skill_id] = current + 1
	_refresh_derived_attributes()
	GameState.profile.vitals = vitals
	GameState.profile.skills = skills
	return {"ok": true, "message": "%s 提升至 %d 级" % [definition.get("name", skill_id), current + 1], "cost": cost}

func learn_from_book(skill_id: String) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"ok": false, "message": "未知功法"}
	var requires: Dictionary = definition.get("requires", {})
	if not str(requires.get("sect", "")).is_empty() and str(GameState.profile.get("sect", "")) != str(requires.get("sect", "")):
		return {"ok": false, "message": "未拜入%s，无法读懂此秘籍" % requires.get("sect", "")}
	var current := level(skill_id)
	var max_level := int(definition.get("maxLevel", 100))
	if current >= max_level:
		return {"ok": false, "message": "此秘籍最多只能提升到%d级" % max_level}
	ensure_skills().levels[skill_id] = current + 1
	ensure_skills().get("learnProgress", {}).erase(skill_id)
	_refresh_derived_attributes()
	return {"ok": true, "message": "读罢秘籍，%s 提升至%d级" % [definition.get("name", skill_id), current + 1], "level": current + 1}

func learn_options_for_npc(npc_id: String) -> Array[String]:
	var result: Array[String] = []
	var npc := NpcSystem.build_instance(npc_id)
	var entries := DataRegistry.get_teach_entries(npc_id)
	if entries.is_empty():
		return result
	if not DataRegistry.is_independent_tutor(npc_id) and str(GameState.profile.get("master", "")) != npc_id:
		return result
	for entry in entries:
		var skill_id := str(entry.get("skillId", ""))
		var definition := DataRegistry.get_skill(skill_id)
		if definition.is_empty():
			continue
		if DataRegistry.is_independent_tutor(npc_id) or str(definition.get("sect", "")) == str(npc.get("sect", "")) or str(definition.get("category", "")) == "basic":
			if skill_id not in result:
				result.append(skill_id)
	return result

func join_npc(npc_id: String) -> Dictionary:
	var npc := NpcSystem.build_instance(npc_id)
	var sect := str(npc.get("sect", ""))
	var join_gate: Dictionary = npc.get("joinSect", {})
	if sect.is_empty() or join_gate.is_empty():
		return {"ok": false, "message": "此人不收徒"}
	var current_sect := str(GameState.profile.get("sect", ""))
	if not current_sect.is_empty() and current_sect != sect:
		return {"ok": false, "message": "你已拜入%s，不能改投他门" % current_sect}
	if current_sect == sect and str(GameState.profile.get("master", "")) == npc_id:
		return {"ok": false, "message": "你已经拜此人为师"}
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	for key in join_gate:
		if int(attributes.get(key, 0)) < int(join_gate[key]):
			return {"ok": false, "message": "拜师要求%s达到%d" % [key, int(join_gate[key])]}
	var requirements: Dictionary = npc.get("joinSkillRequirements", {})
	for required_id in requirements:
		if level(str(required_id)) < int(requirements[required_id]):
			return {"ok": false, "message": "需先将%s练到%d级" % [DataRegistry.get_skill(str(required_id)).get("name", required_id), int(requirements[required_id])]}
	GameState.profile.sect = sect
	GameState.profile.master = npc_id
	return {"ok": true, "message": "已拜入%s门下，师父：%s" % [sect, npc.get("display_name", npc_id)]}

func learn_tick(npc_id: String, skill_id: String) -> Dictionary:
	if skill_id not in learn_options_for_npc(npc_id):
		return {"ok": false, "message": "此人不传授这门功法", "reason": "requires"}
	var definition: Dictionary = DataRegistry.get_skill(skill_id)
	var current := level(skill_id)
	var cap := int(definition.get("maxLevel", 100))
	for entry in DataRegistry.get_teach_entries(npc_id):
		if str(entry.get("skillId", "")) == skill_id:
			cap = mini(cap, int(entry.get("maxTeachLevel", cap)))
	if current >= cap:
		return {"ok": false, "message": "%s 已达此师父授艺上限 %d 级" % [definition.get("name", skill_id), cap], "reason": "maxLevel"}
	var requires: Dictionary = definition.get("requires", {})
	if not str(requires.get("sect", "")).is_empty() and str(GameState.profile.get("sect", "")) != str(requires.get("sect", "")):
		return {"ok": false, "message": "未拜入%s" % requires.get("sect", ""), "reason": "requires"}
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	for key in requires.get("attrs", {}):
		if int(attributes.get(key, 0)) < int(requires.attrs[key]):
			return {"ok": false, "message": "%s资质不足" % key, "reason": "requires"}
	var progress: Dictionary = ensure_skills().get("learnProgress", {})
	var next_level := current + 1
	var rate := clampf(1.0 - (float(attributes.get("wisdom", 25)) - 25.0) * 0.02, 0.65, 1.25)
	var required := _learn_required(definition, next_level, rate)
	var current_progress := mini(required, int(progress.get(skill_id, 0)))
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	if current_progress < required:
		if int(vitals.get("potential", 0)) <= 0:
			return {"ok": false, "message": "潜能不足，学习进度 %d/%d" % [current_progress, required], "reason": "potential"}
		vitals.potential = int(vitals.get("potential", 0)) - 1
		progress[skill_id] = current_progress + 1
		ensure_skills().learnProgress = progress
		GameState.profile.vitals = vitals
		return {"ok": false, "message": "研习%s，进度 %d/%d" % [definition.get("name", skill_id), current_progress + 1, required], "progress": current_progress + 1, "required": required}
	var tuition := int(ceil(float(required) * 0.8))
	if int(vitals.get("money", 0)) < tuition:
		return {"ok": false, "message": "学习进度已满，但 Token 不足，需要%d" % tuition, "reason": "token"}
	vitals.money = int(vitals.get("money", 0)) - tuition
	progress[skill_id] = 0
	ensure_skills().learnProgress = progress
	ensure_skills().levels[skill_id] = next_level
	GameState.profile.vitals = vitals
	_refresh_derived_attributes()
	return {"ok": true, "message": "%s 提升至%d级（Token -%d）" % [definition.get("name", skill_id), next_level, tuition], "level": next_level}

func _learn_required(definition: Dictionary, level_to_reach: int, rate: float) -> int:
	if level_to_reach <= 1:
		return 1
	var max_cost := maxi(20, int(ceil(float(definition.get("costBase", 100)) * float(definition.get("costFactor", 1.0)) * 20.0)))
	var denominator := maxi(1.0, float(int(definition.get("maxLevel", 100)) - 1))
	var t := clampf(float(level_to_reach - 1) / denominator, 0.0, 1.0)
	return maxi(2, int(ceil((1.0 + float(max_cost - 1) * pow(t, 2.0)) * rate / 2.0)) * 2)

func _refresh_derived_attributes() -> void:
	var base: Dictionary = GameState.profile.get("base_attributes", GameState.profile.get("attributes", {}))
	var levels: Dictionary = ensure_skills().get("levels", {})
	var attributes := base.duplicate(true)
	for skill_id in ["basicStrength", "basicAgility", "basicConstitution", "basicParry", "literacy"]:
		var key: String = str({"basicStrength": "strength", "basicAgility": "agility", "basicConstitution": "constitution", "basicParry": "strength", "literacy": "wisdom"}.get(skill_id, ""))
		if not str(key).is_empty():
			attributes[key] = mini(50, int(base.get(key, 0)) + int(floor(float(levels.get(skill_id, 0)) / 10.0)))
	GameState.profile.attributes = attributes

func refresh_derived_attributes() -> void:
	_refresh_derived_attributes()

func equip(skill_id: String) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty() or level(skill_id) <= 0:
		return {"ok": false, "message": "尚未学会"}
	var theme := str(definition.get("theme", ""))
	if theme not in THEMES:
		return {"ok": false, "message": "无法装备"}
	ensure_skills().equipped[theme] = skill_id
	return {"ok": true, "message": "已装备 %s" % definition.get("name", skill_id)}

func combat_bonus() -> Dictionary:
	var result := {"attack": 0.0, "defense": 0.0, "hit": 0.0, "dodge": 0.0, "parry": 0.0, "mp_max": 0}
	for skill_id in ensure_skills().equipped.values():
		var definition := DataRegistry.get_skill(skill_id)
		var combat: Dictionary = definition.get("combat", {})
		var lv := level(skill_id)
		result.attack += float(combat.get("atkPerLv", 0.0)) * lv
		result.defense += float(combat.get("defPerLv", 0.0)) * lv
		result.hit += float(combat.get("hitPerLv", 0.0)) * lv
		result.dodge += float(combat.get("dodgePerLv", 0.0)) * lv
		result.parry += float(combat.get("parryPerLv", 0.0)) * lv
		result.mp_max += int(combat.get("mpMaxPerLv", 0)) * lv
	return result

func force_power_cap() -> int:
	var skills := ensure_skills()
	var arch_id := str(skills.equipped.get("arch", ""))
	return maxi(0, level("basicConstitution") + level(arch_id) * 2)

func force_power() -> int:
	var skills := ensure_skills()
	var value := mini(force_power_cap(), maxi(0, int(skills.get("forcePower", 0))))
	skills.forcePower = value
	return value

func set_force_power(value: int) -> Dictionary:
	var cap := force_power_cap()
	var next := clampi(value, 0, cap)
	ensure_skills().forcePower = next
	return {"ok": true, "value": next, "cap": cap, "message": "加力设为 %d / %d" % [next, cap]}

func unlocked_moves() -> Array:
	var result: Array = []
	var skills := ensure_skills()
	for skill_id in skills.get("equipped", {}).values():
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		if str(definition.get("category", "")) != "sect":
			continue
		var kind: String = str({"code": "attack", "tune": "dodge", "parry": "parry"}.get(str(definition.get("theme", "")), ""))
		if str(kind).is_empty():
			continue
		var current := level(str(skill_id))
		for move in definition.get("moves", []):
			var unlock := int(move.get("unlockLevel", 0))
			if current >= unlock:
				result.append({"skill_id": str(skill_id), "name": move.get("name", "招式"), "kind": kind, "unlock": unlock, "level": current})
	return result

func unlocked_ults() -> Array:
	var result: Array = []
	var arch_id := str(ensure_skills().equipped.get("arch", ""))
	var definition: Dictionary = DataRegistry.get_skill(arch_id)
	var ult: Dictionary = definition.get("ult", {})
	if ult.is_empty():
		return result
	var arch_level := level(arch_id)
	var inner_power := level("basicConstitution") + arch_level * 2
	if arch_level >= 30:
		result.append(_make_ult(ult, 1, inner_power))
	if arch_level >= 80:
		result.append(_make_ult(ult, 2, inner_power))
	return result

func _make_ult(config: Dictionary, tier: int, inner_power: int) -> Dictionary:
	var costs := {"multi": [25, 45], "abnormal": [30, 50], "reduceMax": [35, 60], "hugeDamage": [40, 70]}
	var kind := str(config.get("kind", "hugeDamage"))
	return {"id": "ult:%s:%d" % [config.get("key", "sect"), 30 if tier == 1 else 80], "name": config.get("names", ["绝招", "绝招"])[tier - 1], "kind": kind, "tier": tier, "inner_power": inner_power, "mp_cost": costs.get(kind, [40, 70])[tier - 1]}

func _cost(definition: Dictionary, level_before: int) -> int:
	return maxi(1, int(round(float(definition.get("costBase", 100)) * pow(float(definition.get("costFactor", 1.0)), level_before))))

func meditate_tick() -> Dictionary:
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var neigong := int(vitals.get("neigong", 0))
	var cap := (level("basicConstitution") + level(str(ensure_skills().equipped.get("arch", ""))) * 2) * 25
	if neigong >= cap and int(GameState.combat_state.mp) >= maxi(1, neigong):
		return {"ok": false, "message": "内功修为已达当前上限"}
	var maximum := maxi(1, neigong)
	GameState.combat_state.mp += 5
	if GameState.combat_state.mp >= maximum:
		GameState.combat_state.mp = 0
		vitals.neigong = neigong + 1
		GameState.profile.vitals = vitals
		return {"ok": true, "message": "冥想突破，内功修为提升至 %d" % (neigong + 1)}
	return {"ok": true, "message": "冥想进度 %d/%d" % [GameState.combat_state.mp, maximum]}

func practice_tick(skill_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_skill(skill_id)
	if definition.is_empty() or str(definition.get("category", "")) != "sect" or str(definition.get("theme", "")) == "arch":
		return {"ok": false, "message": "这门功法不能通过练功提升"}
	if str(definition.get("sect", "")) != str(GameState.profile.get("sect", "")) or level(skill_id) <= 0:
		return {"ok": false, "message": "尚未学会本门功法"}
	var skills := ensure_skills()
	var basic_id: String = str({"code": "basicStrength", "tune": "basicAgility", "parry": "basicParry", "knowledge": "literacy"}.get(str(definition.get("theme", "")), ""))
	var cap := mini(int(definition.get("maxLevel", 100)), level(str(basic_id)))
	cap = mini(cap, int(GameState.profile.get("vitals", {}).get("neigong", 0)))
	var current := level(skill_id)
	if current >= cap:
		return {"ok": false, "message": "已达当前练功上限 %d 级" % cap}
	var progress: Dictionary = skills.get("practiceProgress", {})
	var required := _cost(definition, current)
	var gain := maxi(1, int(floor(float(GameState.profile.get("attributes", {}).get("wisdom", 1)) / 5.0)))
	var mp_cost := 2
	var hp_cost := maxi(0, int(ceil(float(progress.get(skill_id, 0) + gain) * 0.1)) - int(ceil(float(progress.get(skill_id, 0)) * 0.1)))
	if int(GameState.combat_state.mp) < mp_cost or int(GameState.combat_state.hp) - hp_cost < 1:
		return {"ok": false, "message": "精力或体力不足，练不动功"}
	GameState.combat_state.mp -= mp_cost
	GameState.combat_state.hp -= hp_cost
	var next_progress := mini(required, int(progress.get(skill_id, 0)) + gain)
	if next_progress >= required:
		skills.levels[skill_id] = current + 1
		progress[skill_id] = 0
		_refresh_derived_attributes()
	else:
		progress[skill_id] = next_progress
	skills.practiceProgress = progress
	return {"ok": true, "message": "%s 练功进度 %d/%d" % [definition.get("name", skill_id), next_progress, required], "level": level(skill_id)}

func channel_hp() -> Dictionary:
	var amount := mini(int(GameState.combat_state.mp), maxi(0, _hp_max() - int(GameState.combat_state.hp)))
	if amount <= 0:
		return {"ok": false, "message": "没有可运功恢复的体力"}
	GameState.combat_state.mp -= amount
	GameState.combat_state.hp += amount
	return {"ok": true, "message": "运功恢复 %d 点体力" % amount}

func heal_injury() -> Dictionary:
	var injury := int(GameState.combat_state.injury)
	var amount := mini(injury, int(GameState.combat_state.mp) / 5)
	if amount <= 0:
		return {"ok": false, "message": "精力不足或没有伤势"}
	GameState.combat_state.mp -= amount * 5
	GameState.combat_state.injury -= amount
	return {"ok": true, "message": "疗伤恢复 %d 点伤势" % amount}

func _hp_max() -> int:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	return maxi(1, int(floor(140.0 * (1.0 + float(attributes.get("constitution", 0)) * 0.025))) - int(GameState.combat_state.get("injury", 0)))
