extends Node

const LEARNING_TICK_SECONDS := 1.0 / 30.0
const MEDITATION_TICK_SECONDS := 1.0 / 30.0
const PRACTICE_TICK_SECONDS := 1.0 / 6.0

const THEMES := ["code", "tune", "arch", "parry", "knowledge"]

func create_default_skills() -> Dictionary:
	return {"levels": {"basicStrength": 1, "basicAgility": 1, "basicConstitution": 1, "basicParry": 1, "literacy": 1}, "equipped_basic": {"code": "basicStrength", "tune": "basicAgility", "arch": "basicConstitution", "parry": "basicParry", "knowledge": "literacy"}, "equipped_special": {}, "progress": {}}

func ensure_skills() -> Dictionary:
	if not GameState.profile.has("skills") or GameState.profile.skills.is_empty():
		GameState.profile.skills = create_default_skills()
	var skills: Dictionary = GameState.profile.skills
	if not skills.has("levels"): skills.levels = {}
	if not skills.has("equipped_basic"):
		skills.equipped_basic = {}
		for theme in THEMES:
			var basic_id := str(THEME_BASIC_SKILL.get(theme, ""))
			if int(skills.levels.get(basic_id, 0)) > 0:
				skills.equipped_basic[theme] = basic_id
	if not skills.has("equipped_special"):
		skills.equipped_special = {}
		for theme in skills.get("equipped", {}):
			var old_id := str(skills.equipped[theme])
			if str(DataRegistry.get_skill(old_id).get("category", "")) == "sect":
				skills.equipped_special[theme] = old_id
	skills.erase("equipped")
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
		return {"ok": false, "message": "未拜入%s，学不得【%s】" % [requires.get("sect", ""), definition.get("name", skill_id)]}
	var current := level(skill_id)
	var max_level := int(definition.get("maxLevel", 100))
	if current >= max_level:
		return {"ok": false, "message": "此书只能将【%s】读到 %d 级。" % [definition.get("name", skill_id), max_level]}
	var before_attrs: Dictionary = GameState.profile.get("attributes", {}).duplicate()
	ensure_skills().levels[skill_id] = current + 1
	ensure_skills().get("learnProgress", {}).erase(skill_id)
	_refresh_derived_attributes()
	return {"ok": true, "message": "读罢秘籍，领悟【%s】至 %d 级%s。" % [definition.get("name", skill_id), current + 1, _attribute_growth_suffix(before_attrs)], "level": current + 1}

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
			var basic_id := str(THEME_BASIC_SKILL.get(str(definition.get("theme", "")), ""))
			if not basic_id.is_empty() and basic_id not in result:
				result.append(basic_id)
			if skill_id not in result:
				result.append(skill_id)
	return result

const JOIN_ATTR_LABELS := {"strength": "编码", "agility": "思维", "constitution": "架构", "wisdom": "灵感"}

## 师父造诣档位：以其收徒功法门槛总和衡量，门槛越高的师父能教得越深。
func _master_tier(npc: Dictionary) -> int:
	var requirements: Dictionary = npc.get("joinSkillRequirements", {})
	var total := 0
	for value in requirements.values():
		total += int(value)
	return total

## 菜单显隐用：未拜入该门派，或已拜入但此人造诣高于当前师父（可改投深造）。
func can_join(npc_id: String) -> bool:
	var npc := NpcSystem.build_instance(npc_id)
	var sect := str(npc.get("sect", ""))
	if sect.is_empty() or npc.get("joinSect", {}).is_empty():
		return false
	var current_sect := str(GameState.profile.get("sect", ""))
	var current_master := str(GameState.profile.get("master", ""))
	if current_sect.is_empty() or current_sect != sect:
		return true
	if current_master == npc_id:
		return false
	return _master_tier(npc) > _master_tier(NpcSystem.build_instance(current_master))

func join_npc(npc_id: String) -> Dictionary:
	var npc := NpcSystem.build_instance(npc_id)
	var sect := str(npc.get("sect", ""))
	var join_gate: Dictionary = npc.get("joinSect", {})
	if sect.is_empty() or join_gate.is_empty():
		return {"ok": false, "message": "此人不收徒。"}
	var current_sect := str(GameState.profile.get("sect", ""))
	var current_master := str(GameState.profile.get("master", ""))
	if not current_sect.is_empty() and current_sect != sect:
		return {"ok": false, "message": "你已拜入%s，不便改投他门。" % current_sect}
	var display_name := str(npc.get("display_name", npc_id))
	var upgrading := current_sect == sect and not current_master.is_empty()
	if upgrading:
		if current_master == npc_id:
			return {"ok": false, "message": "你已师从此人。"}
		var current_master_npc := NpcSystem.build_instance(current_master)
		if _master_tier(npc) <= _master_tier(current_master_npc):
			return {"ok": false, "message": "%s的造诣不及你现在的师父，无须改投。" % display_name}
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	var missing_attrs: Array[String] = []
	for key in join_gate:
		if int(attributes.get(key, 0)) < int(join_gate[key]):
			missing_attrs.append("%s ≥ %d" % [JOIN_ATTR_LABELS.get(str(key), str(key)), int(join_gate[key])])
	if not missing_attrs.is_empty():
		return {"ok": false, "message": "拜入%s门下需：%s。你资质未足，再来。" % [sect, "、".join(missing_attrs)]}
	var requirements: Dictionary = npc.get("joinSkillRequirements", {})
	var missing_skills: Array[String] = []
	for required_id in requirements:
		if level(str(required_id)) < int(requirements[required_id]):
			missing_skills.append("%s ≥ %d" % [DataRegistry.get_skill(str(required_id)).get("name", required_id), int(requirements[required_id])])
	if not missing_skills.is_empty():
		return {"ok": false, "message": "拜入%s门下需：%s。你功夫未足，再来。" % [sect, "、".join(missing_skills)]}
	GameState.profile.sect = sect
	GameState.profile.master = npc_id
	if upgrading:
		return {"ok": true, "message": "你已成功改拜%s为师，你恭恭敬敬的磕了几个响头，可学更高深的功夫了。" % display_name}
	return {"ok": true, "message": "你已成功拜%s为师，你恭恭敬敬的磕了几个响头。" % display_name}

func learn_tick(npc_id: String, skill_id: String) -> Dictionary:
	if skill_id not in learn_options_for_npc(npc_id):
		return {"ok": false, "message": "此人不传授这门功法", "reason": "requires"}
	var definition: Dictionary = DataRegistry.get_skill(skill_id)
	var current := level(skill_id)
	var cap := teach_cap(npc_id, skill_id)
	if current >= cap:
		return {"ok": false, "message": "【%s】已至此师父可授上限 %d 级。" % [definition.get("name", skill_id), cap], "reason": "maxLevel"}
	var requires: Dictionary = definition.get("requires", {})
	if not str(requires.get("sect", "")).is_empty() and str(GameState.profile.get("sect", "")) != str(requires.get("sect", "")):
		return {"ok": false, "message": "未拜入%s，学不得【%s】。" % [requires.get("sect", ""), definition.get("name", skill_id)], "reason": "requires"}
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	for key in requires.get("attrs", {}):
		if int(attributes.get(key, 0)) < int(requires.attrs[key]):
			return {"ok": false, "message": "你%s资质不足，学不得【%s】。" % [JOIN_ATTR_LABELS.get(str(key), str(key)), definition.get("name", skill_id)], "reason": "requires"}
	if requires.has("minSkillPower") and _skill_power() < int(requires.get("minSkillPower", 0)):
		return {"ok": false, "message": "你综合火候未到（需综合等级 %d），先精进再来。" % int(requires.get("minSkillPower", 0)), "reason": "requires"}
	if requires.has("minAvgSkill") and _average_skill_level() < float(requires.get("minAvgSkill", 0)):
		return {"ok": false, "message": "你各科尚不均衡（需均值 %d），先补齐短板。" % int(requires.get("minAvgSkill", 0)), "reason": "requires"}
	var prereq: Dictionary = requires.get("prereq", {})
	if not prereq.is_empty() and level(str(prereq.get("skillId", ""))) < int(prereq.get("level", 0)):
		var prereq_id := str(prereq.get("skillId", ""))
		return {"ok": false, "message": "须先将【%s】练到 %d 级。" % [DataRegistry.get_skill(prereq_id).get("name", prereq_id), int(prereq.get("level", 0))], "reason": "requires"}
	var progress: Dictionary = ensure_skills().get("learnProgress", {})
	var next_level := current + 1
	var rate := clampf(1.0 - (float(attributes.get("wisdom", 25)) - 25.0) * 0.02, 0.65, 1.25)
	var required := _learn_required(definition, next_level, rate)
	var current_progress := mini(required, int(progress.get(skill_id, 0)))
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var spent_potential := 0
	if current_progress < required:
		if int(vitals.get("potential", 0)) <= 0:
			return {"ok": false, "message": "潜能不足，学习进度 %d/%d。" % [current_progress, required], "reason": "potential"}
		vitals.potential = int(vitals.get("potential", 0)) - 1
		spent_potential = 1
		current_progress += 1
		progress[skill_id] = current_progress
		ensure_skills().learnProgress = progress
		GameState.profile.vitals = vitals
		if current_progress < required:
			return {"ok": false, "message": "研习【%s】，进度 %d/%d。" % [definition.get("name", skill_id), current_progress, required], "progress": current_progress, "required": required}
	var tuition := int(ceil(float(required) * 0.8))
	if int(vitals.get("money", 0)) < tuition:
		return {"ok": false, "message": "学习进度已满，Token 不足，学费 %d。" % tuition, "reason": "token"}
	vitals.money = int(vitals.get("money", 0)) - tuition
	progress[skill_id] = 0
	ensure_skills().learnProgress = progress
	ensure_skills().levels[skill_id] = next_level
	GameState.profile.vitals = vitals
	var before_attrs: Dictionary = attributes.duplicate()
	_refresh_derived_attributes()
	return {"ok": true, "message": "研习【%s】至 %d 级（耗潜能 %d、Token %d）%s。" % [definition.get("name", skill_id), next_level, spent_potential, tuition, _attribute_growth_suffix(before_attrs)], "level": next_level}

func _skill_power() -> int:
	var levels: Dictionary = ensure_skills().get("levels", {})
	var total := 0
	for basic_id in ["basicStrength", "basicAgility", "basicConstitution", "basicParry", "literacy"]:
		total += maxi(0, int(levels.get(basic_id, 0)))
	for skill_id in levels:
		if str(DataRegistry.get_skill(str(skill_id)).get("category", "")) == "sect":
			total += maxi(0, int(levels[skill_id])) * 2
	return total

func _average_skill_level() -> float:
	var values: Array[int] = []
	var levels: Dictionary = ensure_skills().get("levels", {})
	for basic_id in ["basicStrength", "basicAgility", "basicConstitution", "basicParry", "literacy"]:
		values.append(maxi(0, int(levels.get(basic_id, 0))))
	for skill_id in levels:
		if str(DataRegistry.get_skill(str(skill_id)).get("category", "")) == "sect":
			values.append(maxi(0, int(levels[skill_id])))
	var total := 0
	for value in values:
		total += value
	return float(total) / float(maxi(1, values.size()))

func teach_cap(npc_id: String, skill_id: String) -> int:
	var definition := DataRegistry.get_skill(skill_id)
	var cap := int(definition.get("maxLevel", 100))
	var category := str(definition.get("category", ""))
	var theme := str(definition.get("theme", ""))
	for entry in DataRegistry.get_teach_entries(npc_id):
		var taught_id := str(entry.get("skillId", ""))
		var taught_definition := DataRegistry.get_skill(taught_id)
		if taught_id == skill_id or (category == "basic" and str(taught_definition.get("theme", "")) == theme):
			cap = mini(cap, int(entry.get("maxTeachLevel", cap)))
	return cap

func learning_progress(skill_id: String) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"current": 0, "total": 1}
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	var next_level := level(skill_id) + 1
	var rate := clampf(1.0 - (float(attributes.get("wisdom", 25)) - 25.0) * 0.02, 0.65, 1.25)
	var required := _learn_required(definition, next_level, rate)
	return {
		"current": mini(required, int(ensure_skills().get("learnProgress", {}).get(skill_id, 0))),
		"total": required,
	}

## 学艺/读秘籍升级后，四维是否因基础功法等级提升而跟涨（見 _refresh_derived_attributes）。
func _attribute_growth_suffix(before: Dictionary) -> String:
	var after: Dictionary = GameState.profile.get("attributes", {})
	for key in after:
		if int(after.get(key, 0)) > int(before.get(key, 0)):
			return "，四维亦有精进"
	return ""

func _learn_required(definition: Dictionary, level_to_reach: int, rate: float) -> int:
	if level_to_reach <= 1:
		return 1
	var max_cost := maxi(20, int(ceil(float(definition.get("costBase", 100)) * float(definition.get("costFactor", 1.0)) * 20.0)))
	var denominator := maxi(1.0, float(int(definition.get("maxLevel", 100)) - 1))
	var t := clampf(float(level_to_reach - 1) / denominator, 0.0, 1.0)
	# 原项目严格顺序：基础曲线先 ceil → 乘悟性倍率 → ceil 到偶数。
	# 不能把倍率提前乘进基础曲线，否则高灵感档在部分等级会少 2 点潜能。
	var base_required := maxi(1, int(ceil(1.0 + float(max_cost - 1) * pow(t, 2.0))))
	var normalized_rate := clampf(rate, 0.65, 1.25)
	return maxi(2, int(ceil(float(base_required) * normalized_rate / 2.0)) * 2)

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

const THEME_BASIC_SKILL := {"code": "basicStrength", "tune": "basicAgility", "arch": "basicConstitution", "parry": "basicParry", "knowledge": "literacy"}

func equip(skill_id: String) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty() or level(skill_id) <= 0:
		return {"ok": false, "message": "尚未学会"}
	var theme := str(definition.get("theme", ""))
	if theme not in THEMES:
		return {"ok": false, "message": "无法装备"}
	var slot := "equipped_basic" if str(definition.get("category", "")) == "basic" else "equipped_special"
	ensure_skills()[slot][theme] = skill_id
	return {"ok": true, "message": "已装备【%s】" % definition.get("name", skill_id)}

## 基础与特殊功法使用独立槽，卸下其中一类不会影响另一类。
func unequip(skill_id: String) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"ok": false, "message": "未知功法"}
	var theme := str(definition.get("theme", ""))
	var slot := "equipped_basic" if str(definition.get("category", "")) == "basic" else "equipped_special"
	if str(ensure_skills()[slot].get(theme, "")) != skill_id:
		return {"ok": false, "message": "此功法尚未装备"}
	ensure_skills()[slot].erase(theme)
	return {"ok": true, "message": "已卸下【%s】" % definition.get("name", skill_id)}

func equipped_id(theme: String, category: String) -> String:
	var slot := "equipped_basic" if category == "basic" else "equipped_special"
	return str(ensure_skills().get(slot, {}).get(theme, ""))

func equipped_skill_ids() -> Array[String]:
	var result: Array[String] = []
	for slot in ["equipped_basic", "equipped_special"]:
		for skill_id in ensure_skills().get(slot, {}).values():
			if not str(skill_id).is_empty() and str(skill_id) not in result:
				result.append(str(skill_id))
	return result

## 装备招架功法的伤势减免（战后伤害转伤势的折扣，封顶 75%）。
func injury_reduce() -> float:
	var total := 0.0
	for skill_id in equipped_skill_ids():
		var definition := DataRegistry.get_skill(str(skill_id))
		var reduce_per_lv := float(definition.get("combat", {}).get("injuryReducePerLv", 0.0))
		if reduce_per_lv > 0.0:
			total += level(str(skill_id)) * reduce_per_lv * 0.01
	return minf(0.75, total)

## 本门架构（内力）功法等级合计（用于疗伤门槛）：装备与否均计入所有已学门派架构功法。
func _arch_sect_level_sum() -> int:
	var sum := 0
	for skill_id in ensure_skills().get("levels", {}):
		var definition := DataRegistry.get_skill(str(skill_id))
		if str(definition.get("category", "")) == "sect" and str(definition.get("theme", "")) == "arch":
			sum += level(str(skill_id))
	return sum

func combat_bonus() -> Dictionary:
	var result := {"attack": 0.0, "defense": 0.0, "hit": 0.0, "dodge": 0.0, "parry": 0.0, "mp_max": 0}
	for skill_id in equipped_skill_ids():
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
	return maxi(0, level("basicConstitution") + equipped_sect_skill_level("arch") * 2)

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
	for skill_id in equipped_skill_ids():
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
	var arch_id := equipped_id("arch", "sect")
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
	if not can_meditate():
		return {"ok": false, "message": "须装备基础架构与本门架构高级功法，方可冥想。"}
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var constitution := float(GameState.profile.get("attributes", {}).get("constitution", 0))
	var modifier := GameState.meditation_modifier(constitution)
	var inner_power := level("basicConstitution") + equipped_sect_skill_level("arch") * 2
	var cap := int(floor(float(inner_power) * 25.0 * modifier))
	var neigong := int(vitals.get("neigong", 0))
	var maximum := maxi(0, neigong)
	if neigong >= cap and int(GameState.combat_state.mp) >= maximum:
		return {"ok": false, "message": "冥想已满，无需继续冥想。"}
	GameState.combat_state.mp = mini(maximum, int(GameState.combat_state.mp) + maxi(1, int(floor(5.0 * modifier))))
	if int(GameState.combat_state.mp) >= maximum:
		if neigong < cap:
			GameState.combat_state.mp = 0
			vitals.neigong = mini(cap, neigong + 1)
			GameState.profile.vitals = vitals
			GameState.advance_time(MEDITATION_TICK_SECONDS)
			if vitals.neigong >= cap:
				return {"ok": true, "message": "冥想圆满，精力最大值提升至 %d，已达内功所限。" % vitals.neigong}
			return {"ok": true, "message": "冥想圆满，精力最大值提升至 %d。" % vitals.neigong}
		return {"ok": false, "message": "冥想已满，无需继续冥想。"}
	# 冥想以 30 Hz 推进；每个有效 tick 同步推进 1/30 秒游戏时钟。
	GameState.advance_time(MEDITATION_TICK_SECONDS)
	return {"ok": true, "message": "你凝神冥想，当前精力 %d / %d。" % [GameState.combat_state.mp, maximum]}

func meditation_progress() -> Dictionary:
	return {
		"current": maxi(0, int(GameState.combat_state.get("mp", 0))),
		"total": maxi(1, GameState.player_mp_max()),
	}

## 返回某主题当前装备的本门特殊功法等级；未装备则为 0。
func equipped_sect_skill_level(theme: String) -> int:
	var skill_id := equipped_id(theme, "sect")
	var definition := DataRegistry.get_skill(skill_id)
	if str(definition.get("category", "")) != "sect" or str(definition.get("theme", "")) != theme or str(definition.get("sect", "")) != str(GameState.profile.get("sect", "")):
		return 0
	return level(skill_id)

## 冥想须装备本门架构（内力）高级功法（不只是基础架构）方可进行。
func can_meditate() -> bool:
	return level("basicConstitution") > 0 and equipped_sect_skill_level("arch") > 0

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
	var current_progress := mini(required, maxi(0, int(progress.get(skill_id, 0))))
	var gain_per_tick := maxi(1, int(floor(float(GameState.profile.get("attributes", {}).get("wisdom", 1)) / 5.0)))
	var gain := mini(gain_per_tick, required - current_progress)
	var mp_cost := 2 if gain > 0 else 0
	var hp_cost := maxi(0, int(ceil(float(current_progress + gain) * 0.8)) - int(ceil(float(current_progress) * 0.8)))
	if int(GameState.combat_state.mp) < mp_cost:
		return {"ok": false, "message": "精力不足，练不动功。"}
	if int(GameState.combat_state.hp) - hp_cost < 1:
		return {"ok": false, "message": "体力不足，练不动功。"}
	GameState.combat_state.mp -= mp_cost
	GameState.combat_state.hp -= hp_cost
	# 练功以 6 Hz 推进；每个有效 tick 同步推进 1/6 秒游戏时钟。
	GameState.advance_time(PRACTICE_TICK_SECONDS)
	var next_progress := current_progress + gain
	if next_progress >= required:
		skills.levels[skill_id] = current + 1
		progress[skill_id] = 0
		_refresh_derived_attributes()
	else:
		progress[skill_id] = next_progress
	skills.practiceProgress = progress
	var shown_progress := int(progress.get(skill_id, 0))
	var shown_required := _cost(definition, level(skill_id))
	return {"ok": true, "message": "%s 练功进度 %d/%d" % [definition.get("name", skill_id), shown_progress, shown_required], "level": level(skill_id)}

func practice_progress(skill_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"current": 0, "total": 1, "level": 0}
	var current_level := level(skill_id)
	return {
		"current": int(ensure_skills().get("practiceProgress", {}).get(skill_id, 0)),
		"total": _cost(definition, current_level),
		"level": current_level,
	}

func channel_hp() -> Dictionary:
	var eff_max := GameState.player_effective_hp_max()
	var amount := mini(int(GameState.combat_state.mp), maxi(0, eff_max - int(GameState.combat_state.hp)))
	if amount <= 0:
		if int(GameState.combat_state.hp) >= eff_max:
			return {"ok": false, "message": "体力已满，不必摸鱼。"}
		return {"ok": false, "message": "精力不足，摸不了鱼。"}
	GameState.combat_state.mp -= amount
	GameState.combat_state.hp += amount
	GameState.advance_time(1.0)
	return {"ok": true, "message": "你偷偷摸了会鱼，消耗 %d 精力，恢复 %d 体力。" % [amount, amount]}

## 疗伤门槛：本门架构（内力）功法等级合计须超过此值。
const HEAL_INJURY_ARCH_LEVEL_GATE := 30
const HEAL_INJURY_MP_PER_POINT := 5

func heal_injury() -> Dictionary:
	var arch_sum := _arch_sect_level_sum()
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
	var eff_max := GameState.player_effective_hp_max()
	var suffix := "，余伤 %d 点" % GameState.combat_state.injury if GameState.combat_state.injury > 0 else "，伤势尽愈"
	return {"ok": true, "message": "你运转内息疗伤，消耗 %d 精力，愈合伤势 %d 点，体力上限恢复至 %d%s。" % [amount * HEAL_INJURY_MP_PER_POINT, amount, eff_max, suffix]}
