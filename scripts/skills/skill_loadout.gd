extends RefCounted
## 功法装备与战斗能力领域服务；只通过 SkillSystem 的窄接口访问技能状态。

const SKILL_MAPS := preload("res://scripts/skills/skill_maps.gd")
const THEMES := SKILL_MAPS.THEMES
const ULT_TIER1_ARCH_LEVEL := 30
const ULT_TIER2_ARCH_LEVEL := 80
## 绝招精力消耗表：玩家侧（_make_ult）与 NPC 侧（enemy_ai.npc_ults）共用。
const ULT_MP_COSTS := {"multi": [25, 45], "abnormal": [30, 50], "reduceMax": [35, 60], "hugeDamage": [40, 70]}

var skills: Node

## 绑定技能系统协调器。
func _init(skill_system: Node) -> void:
	skills = skill_system

## 将已学功法放入对应主题的基础或门派槽，并立即保存装备状态。
func equip(skill_id: String) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"ok": false, "message": "没有这门功法。"}
	if str(definition.get("category", "")) == "sect" and str(definition.get("sect", "")) != str(GameState.profile.get("sect", "")):
		return {"ok": false, "message": "非本门功法，不能装备。"}
	if skills.level(skill_id) <= 0:
		return {"ok": false, "message": "尚未学会【%s】。" % definition.get("name", skill_id)}
	var theme := str(definition.get("theme", ""))
	if theme not in THEMES:
		return {"ok": false, "message": "无法装备。"}
	var slot := "equipped_basic" if str(definition.get("category", "")) == "basic" else "equipped_special"
	skills.ensure_skills()[slot][theme] = skill_id
	GameState.save_game()
	return {"ok": true, "message": "已装备【%s】。" % definition.get("name", skill_id)}

## 从对应槽位卸下功法并立即保存，不影响另一类槽位。
func unequip(skill_id: String) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"ok": false, "message": "未知功法"}
	var theme := str(definition.get("theme", ""))
	var slot := "equipped_basic" if str(definition.get("category", "")) == "basic" else "equipped_special"
	if str(skills.ensure_skills()[slot].get(theme, "")) != skill_id:
		return {"ok": false, "message": "此功法尚未装备"}
	skills.ensure_skills()[slot].erase(theme)
	GameState.save_game()
	return {"ok": true, "message": "已卸下【%s】" % definition.get("name", skill_id)}

## 查询指定主题和类别当前装备的功法 ID。
func equipped_id(theme: String, category: String) -> String:
	var slot := "equipped_basic" if category == "basic" else "equipped_special"
	return str(skills.ensure_skills().get(slot, {}).get(theme, ""))

## 返回去重后的全部已装备功法 ID。
func equipped_skill_ids() -> Array[String]:
	var result: Array[String] = []
	for slot in ["equipped_basic", "equipped_special"]:
		for skill_id in skills.ensure_skills().get(slot, {}).values():
			if not str(skill_id).is_empty() and str(skill_id) not in result:
				result.append(str(skill_id))
	return result

## 累加已装备功法的伤势减免，并限制在 75% 以内。
func injury_reduce() -> float:
	var total := 0.0
	for skill_id in equipped_skill_ids():
		var definition := DataRegistry.get_skill(str(skill_id))
		var reduce_per_level := float(definition.get("combat", {}).get("injuryReducePerLv", 0.0))
		if reduce_per_level > 0.0:
			total += skills.level(str(skill_id)) * reduce_per_level * 0.01
	return minf(0.75, total)

## 合计所有已学本门架构功法等级，装备与否均计入疗伤门槛。
func arch_sect_level_sum() -> int:
	var total := 0
	for skill_id in skills.ensure_skills().get("levels", {}):
		var definition := DataRegistry.get_skill(str(skill_id))
		if str(definition.get("category", "")) == "sect" and str(definition.get("theme", "")) == "arch":
			total += skills.level(str(skill_id))
	return total

## 累加全部已装备功法的攻击、防御、命中、闪避、招架和精力上限加成。
func combat_bonus() -> Dictionary:
	var result := {"attack": 0.0, "defense": 0.0, "hit": 0.0, "dodge": 0.0, "parry": 0.0, "mp_max": 0}
	for skill_id in equipped_skill_ids():
		var definition := DataRegistry.get_skill(skill_id)
		var combat: Dictionary = definition.get("combat", {})
		var level: int = skills.level(skill_id)
		result.attack += float(combat.get("atkPerLv", 0.0)) * level
		result.defense += float(combat.get("defPerLv", 0.0)) * level
		result.hit += float(combat.get("hitPerLv", 0.0)) * level
		result.dodge += float(combat.get("dodgePerLv", 0.0)) * level
		result.parry += float(combat.get("parryPerLv", 0.0)) * level
		result.mp_max += int(combat.get("mpMaxPerLv", 0)) * level
	return result

## 从已装备门派功法中取指定战斗字段的最高加成，不跨功法累加。
func best_combat_bonus(key: String) -> float:
	var best := 0.0
	for skill_id in equipped_skill_ids():
		var definition := DataRegistry.get_skill(skill_id)
		if str(definition.get("category", "")) != "sect":
			continue
		best = maxf(best, float(definition.get("combat", {}).get(key, 0.0)) * skills.level(skill_id))
	return best

## 加力上限等于基础架构等级加本门架构功法等级的两倍。
func force_power_cap() -> int:
	return maxi(0, skills.level("basicConstitution") + skills.equipped_sect_skill_level("arch") * 2)

## 读取加力档位，并按当前上限钳制旧存档或降级后的值。
func force_power() -> int:
	var state: Dictionary = skills.ensure_skills()
	var value := mini(force_power_cap(), maxi(0, int(state.get("force_power", 0))))
	state.force_power = value
	return value

## 写入玩家选择的加力档位。
func set_force_power(value: int) -> Dictionary:
	var cap := force_power_cap()
	var next := clampi(value, 0, cap)
	skills.ensure_skills().force_power = next
	return {"ok": true, "value": next, "cap": cap, "message": "加力设为 %d / %d" % [next, cap]}

## 收集已装备门派功法中达到等级门槛的攻击、闪避和招架招式。
func unlocked_moves() -> Array:
	var result: Array = []
	for skill_id in equipped_skill_ids():
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		if str(definition.get("category", "")) != "sect":
			continue
		var kind: String = str(SKILL_MAPS.THEME_COMBAT_KIND.get(str(definition.get("theme", "")), ""))
		if kind.is_empty():
			continue
		var current_level: int = skills.level(str(skill_id))
		for move in definition.get("moves", []):
			var unlock_level := int(move.get("unlockLevel", 0))
			if current_level >= unlock_level:
				result.append({"skill_id": str(skill_id), "name": move.get("name", "招式"), "kind": kind, "unlock": unlock_level, "level": current_level})
	return result

## 按门派架构功法等级解锁 30 级和 80 级两档绝招。
func unlocked_ults() -> Array:
	var result: Array = []
	var arch_id := equipped_id("arch", "sect")
	var definition: Dictionary = DataRegistry.get_skill(arch_id)
	var ult: Dictionary = definition.get("ult", {})
	if ult.is_empty():
		return result
	var arch_level: int = skills.level(arch_id)
	var inner_power: int = skills.level("basicConstitution") + arch_level * 2
	if arch_level >= ULT_TIER1_ARCH_LEVEL:
		result.append(_make_ult(ult, 1, inner_power))
	if arch_level >= ULT_TIER2_ARCH_LEVEL:
		result.append(_make_ult(ult, 2, inner_power))
	return result

## 把绝招配置与档位转换为战斗系统使用的标准字典。
func _make_ult(config: Dictionary, tier: int, inner_power: int) -> Dictionary:
	var kind := str(config.get("kind", "hugeDamage"))
	var unlock_level := ULT_TIER1_ARCH_LEVEL if tier == 1 else ULT_TIER2_ARCH_LEVEL
	return {"id": "ult:%s:%d" % [config.get("key", "sect"), unlock_level], "name": config.get("names", ["绝招", "绝招"])[tier - 1], "kind": kind, "tier": tier, "inner_power": inner_power, "mp_cost": ULT_MP_COSTS.get(kind, [40, 70])[tier - 1]}
