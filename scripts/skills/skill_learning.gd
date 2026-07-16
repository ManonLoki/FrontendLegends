extends RefCounted
## 师父研习领域服务；负责资格检查、逐步消耗潜能和完成时支付 Token。

const SKILL_MAPS := preload("res://scripts/skills/skill_maps.gd")
const ATTRIBUTE_LABELS := SKILL_MAPS.ATTRIBUTE_LABELS

var skills: Node

## 绑定技能系统协调器。
func _init(skill_system: Node) -> void:
	skills = skill_system

## 推进一次向师父学习的固定时间片，并在进度满时完成升级。
func learn_tick(npc_id: String, skill_id: String) -> Dictionary:
	if skill_id not in skills.learn_options_for_npc(npc_id):
		return {"ok": false, "message": "此人不传授这门功法", "reason": "requires"}
	var definition: Dictionary = DataRegistry.get_skill(skill_id)
	var current: int = skills.level(skill_id)
	var cap: int = skills.teach_cap(npc_id, skill_id)
	if current >= cap:
		return {"ok": false, "message": "【%s】已至此师父可授上限 %d 级。" % [definition.get("name", skill_id), cap], "reason": "maxLevel"}
	var requirement_failure := _requirement_failure(definition)
	if not requirement_failure.is_empty():
		return requirement_failure
	var progress: Dictionary = skills.ensure_skills().get("learn_progress", {})
	var next_level := current + 1
	var required: int = skills._learn_required(definition, next_level, skills._learning_cost_rate())
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
		skills.ensure_skills().learn_progress = progress
		GameState.profile.vitals = vitals
		if current_progress < required:
			return {"ok": false, "message": "研习【%s】，进度 %d/%d。" % [definition.get("name", skill_id), current_progress, required], "progress": current_progress, "required": required}
	var tuition := int(ceil(float(required) * 0.8))
	if int(vitals.get("money", 0)) < tuition:
		return {"ok": false, "message": "学习进度已满，Token 不足，学费 %d。" % tuition, "reason": "token"}
	vitals.money = int(vitals.get("money", 0)) - tuition
	progress[skill_id] = 0
	skills.ensure_skills().learn_progress = progress
	skills.ensure_skills().levels[skill_id] = next_level
	GameState.profile.vitals = vitals
	var before_attributes: Dictionary = GameState.profile.get("attributes", {}).duplicate()
	skills.refresh_derived_attributes()
	var growth_suffix: String = skills._attribute_growth_suffix(before_attributes)
	return {"ok": true, "message": "研习【%s】至 %d 级（耗潜能 %d、Token %d）%s。" % [definition.get("name", skill_id), next_level, spent_potential, tuition, growth_suffix], "level": next_level}

## 按门派、四维、综合火候、均衡度和前置功法顺序返回首个失败原因。
func _requirement_failure(definition: Dictionary) -> Dictionary:
	var requirements: Dictionary = definition.get("requires", {})
	var skill_name := str(definition.get("name", "功法"))
	var required_sect := str(requirements.get("sect", ""))
	if not required_sect.is_empty() and str(GameState.profile.get("sect", "")) != required_sect:
		return {"ok": false, "message": "未拜入%s，学不得【%s】。" % [required_sect, skill_name], "reason": "requires"}
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	for key in requirements.get("attrs", {}):
		if int(attributes.get(key, 0)) < int(requirements.attrs[key]):
			return {"ok": false, "message": "你%s资质不足，学不得【%s】。" % [ATTRIBUTE_LABELS.get(str(key), str(key)), skill_name], "reason": "requires"}
	if requirements.has("minSkillPower") and skills._skill_power() < int(requirements.get("minSkillPower", 0)):
		return {"ok": false, "message": "你综合火候未到（需综合等级 %d），先精进再来。" % int(requirements.get("minSkillPower", 0)), "reason": "requires"}
	if requirements.has("minAvgSkill") and skills._average_skill_level() < float(requirements.get("minAvgSkill", 0)):
		return {"ok": false, "message": "你各科尚不均衡（需均值 %d），先补齐短板。" % int(requirements.get("minAvgSkill", 0)), "reason": "requires"}
	var prerequisite: Dictionary = requirements.get("prereq", {})
	var prerequisite_id := str(prerequisite.get("skillId", ""))
	if not prerequisite.is_empty() and skills.level(prerequisite_id) < int(prerequisite.get("level", 0)):
		var prerequisite_name: String = str(DataRegistry.get_skill(prerequisite_id).get("name", prerequisite_id))
		return {"ok": false, "message": "须先将【%s】练到 %d 级。" % [prerequisite_name, int(prerequisite.get("level", 0))], "reason": "requires"}
	return {}
