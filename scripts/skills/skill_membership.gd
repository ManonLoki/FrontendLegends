extends RefCounted
## 师承与门派领域服务；负责教学列表、拜师资格和同门改投规则。

const THEME_BASIC_SKILL := {"code": "basicStrength", "tune": "basicAgility", "arch": "basicConstitution", "parry": "basicParry", "knowledge": "literacy"}
const ATTRIBUTE_LABELS := {"strength": "编码", "agility": "思维", "constitution": "架构", "wisdom": "灵感"}

var skills: Node

## 绑定技能系统协调器。
func _init(skill_system: Node) -> void:
	skills = skill_system

## 返回当前师承允许向指定人物学习的基础与门派功法列表。
func learn_options_for_npc(npc_id: String) -> Array[String]:
	var result: Array[String] = []
	var npc := NpcSystem.build_instance(npc_id)
	var entries := DataRegistry.get_teach_entries(npc_id)
	if entries.is_empty():
		return result
	## 独立导师无需拜师，门派导师只教授自己的正式弟子。
	if not DataRegistry.is_independent_tutor(npc_id) and str(GameState.profile.get("master", "")) != npc_id:
		return result
	for entry in entries:
		var skill_id := str(entry.get("skillId", ""))
		var definition := DataRegistry.get_skill(skill_id)
		if definition.is_empty():
			continue
		var belongs_to_teacher := str(definition.get("sect", "")) == str(npc.get("sect", ""))
		var is_basic := str(definition.get("category", "")) == "basic"
		if DataRegistry.is_independent_tutor(npc_id) or belongs_to_teacher or is_basic:
			var basic_id := str(THEME_BASIC_SKILL.get(str(definition.get("theme", "")), ""))
			if not basic_id.is_empty() and basic_id not in result:
				result.append(basic_id)
			if skill_id not in result:
				result.append(skill_id)
	return result

## 读取人物教学表中明确声明的最高教学等级；旧字符串格式视为零级。
func master_teach_cap(npc_id: String) -> int:
	var cap := 0
	for entry in DataRegistry.get_teach_entries(npc_id):
		cap = maxi(cap, int(entry.get("maxTeachLevel", 0)))
	return cap

## 判断人物是否可成为新师父或造诣更高的同门师父。
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
	return master_teach_cap(npc_id) > master_teach_cap(current_master)

## 验证门派、师父造诣、四维与技能门槛，通过后更新角色师承。
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
		## 同门改投只允许严格升级，不允许同档平替或降低师承。
		if master_teach_cap(npc_id) <= master_teach_cap(current_master):
			return {"ok": false, "message": "%s的造诣不及你现在的师父，无须改投。" % display_name}
	var missing_attributes := _missing_attributes(join_gate)
	if not missing_attributes.is_empty():
		return {"ok": false, "message": "拜入%s门下需：%s。你资质未足，再来。" % [sect, "、".join(missing_attributes)]}
	var missing_skills := _missing_skills(npc.get("joinSkillRequirements", {}))
	if not missing_skills.is_empty():
		return {"ok": false, "message": "拜入%s门下需：%s。你功夫未足，再来。" % [sect, "、".join(missing_skills)]}
	GameState.profile.sect = sect
	GameState.profile.master = npc_id
	if upgrading:
		return {"ok": true, "message": "你已成功改拜%s为师，你恭恭敬敬的磕了几个响头，可学更高深的功夫了。" % display_name}
	return {"ok": true, "message": "你已成功拜%s为师，你恭恭敬敬的磕了几个响头。" % display_name}

## 返回尚未达到的人物属性门槛文本。
func _missing_attributes(join_gate: Dictionary) -> Array[String]:
	var attributes: Dictionary = GameState.profile.get("attributes", {})
	var missing: Array[String] = []
	for key in join_gate:
		if int(attributes.get(key, 0)) < int(join_gate[key]):
			missing.append("%s ≥ %d" % [ATTRIBUTE_LABELS.get(str(key), str(key)), int(join_gate[key])])
	return missing

## 返回尚未达到的前置功法等级文本。
func _missing_skills(requirements: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for skill_id in requirements:
		if skills.level(str(skill_id)) < int(requirements[skill_id]):
			var name: String = str(DataRegistry.get_skill(str(skill_id)).get("name", skill_id))
			missing.append("%s ≥ %d" % [name, int(requirements[skill_id])])
	return missing
