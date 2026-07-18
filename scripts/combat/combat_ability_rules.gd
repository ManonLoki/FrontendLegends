extends RefCounted
## 组合式绝招与普通招式共用的纯数值规则。

const MIN_INNER_LEVEL := 30
const MAX_INNER_LEVEL := 100

static func progress(inner_level: int) -> float:
	return clampf(float(inner_level - MIN_INNER_LEVEL) / float(MAX_INNER_LEVEL - MIN_INNER_LEVEL), 0.0, 1.0)

static func multi_hits(inner_level: int) -> int:
	if inner_level >= 100: return 6
	if inner_level >= 75: return 5
	if inner_level >= 50: return 4
	return 3

static func multi_power(inner_level: int) -> float:
	return {3: 0.65, 4: 0.60, 5: 0.55, 6: 0.50}[multi_hits(inner_level)]

static func abnormal_count(inner_level: int) -> int:
	return 2 if inner_level >= 80 else 1

static func guaranteed_damage_scale(inner_level: int) -> float:
	return 1.5 + progress(inner_level) * 0.5

static func drain_hp_ratio(inner_level: int) -> float:
	return 0.20 + progress(inner_level) * 0.15

static func drain_mp_ratio(inner_level: int) -> float:
	return 0.08 + progress(inner_level) * 0.07

static func attack_effects(ult: Dictionary) -> Dictionary:
	var abilities: Array = ult.get("abilities", [])
	var level := int(ult.get("inner_level", MIN_INNER_LEVEL))
	var result := {}
	if "guaranteed_hit" in abilities:
		result.guaranteedHit = true
		result.damageScale = guaranteed_damage_scale(level)
	if "drain_hp" in abilities: result.drainHpRatio = drain_hp_ratio(level)
	if "drain_mp" in abilities: result.drainMpMaxRatio = drain_mp_ratio(level)
	return result

## 从同一组运行时曲线生成绝招菜单说明。
static func format_ult_label(ult: Dictionary) -> String:
	var name_cost := "%s（耗精力 %d）" % [ult.get("name", "绝招"), int(ult.get("mp_cost", 0))]
	var abilities: Array = ult.get("abilities", [])
	var level := int(ult.get("inner_level", MIN_INNER_LEVEL))
	var details: Array[String] = []
	if "multi" in abilities:
		details.append("连击%d击（每击%d%%伤）" % [multi_hits(level), int(round(multi_power(level) * 100.0))])
	if "abnormal" in abilities:
		details.append("必定附加%d种异常（各2回合）" % abnormal_count(level))
	if "guaranteed_hit" in abilities:
		details.append("必中，%d%%倍率伤害" % int(round(guaranteed_damage_scale(level) * 100.0)))
	if "drain_hp" in abilities:
		details.append("吸取实际伤害的%d%%体力" % int(round(drain_hp_ratio(level) * 100.0)))
	if "drain_mp" in abilities:
		details.append("吸取目标最大精力的%d%%" % int(round(drain_mp_ratio(level) * 100.0)))
	return name_cost if details.is_empty() else "%s  %s" % [name_cost, "；".join(details)]
