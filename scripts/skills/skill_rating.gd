extends RefCounted
## 武学称号规则；对齐参照项目 SkillRating.ts。

const EARLY_TITLES: Array[String] = [
	"不堪一击", "略知一二", "初学乍练", "懂得皮毛", "粗通门径",
	"渐有所悟", "略通武艺", "出入茅庐", "初窥门径", "渐入门径",
	"心领神会", "略有小成", "融会贯通", "豁然贯通", "出类拔萃",
	"小有名气", "技艺精湛", "略有大成", "炉火纯青", "登堂入室",
]
const HIGH_TITLES: Array[String] = [
	"登峰造极", "出神入化", "神乎其技", "技艺超绝", "一代宗师",
	"威震八方", "精深奥妙", "神功盖世", "独步江湖", "傲视群雄",
	"神功傲世", "独步天下", "天下无敌", "无与伦比", "旷古绝伦",
	"举世无双", "震古烁今", "超凡入圣", "天人合一",
]

static func title(score_value: float) -> String:
	var score := maxi(0, int(floor(score_value)))
	if score == 0:
		return "未学武功"
	if score >= 300:
		return "返璞归真"
	if score >= 291:
		return "已臻化境"
	if score <= 100:
		return EARLY_TITLES[mini(EARLY_TITLES.size() - 1, int(floor(float(score - 1) / 5.0)))]
	return HIGH_TITLES[mini(HIGH_TITLES.size() - 1, int(floor(float(score - 101) / 10.0)))]

static func equipped_average(levels: Dictionary, equipped_ids: Array) -> float:
	var total := 0.0
	var count := 0
	for skill_id_value in equipped_ids:
		var skill_id := str(skill_id_value)
		if str(DataRegistry.get_skill(skill_id).get("theme", "")) == "knowledge":
			continue
		total += maxi(0, int(levels.get(skill_id, 0)))
		count += 1
	return total / float(count) if count > 0 else 0.0

static func player_equipped_ids(skills: Dictionary) -> Array:
	var result: Array = []
	for group_name in ["equipped_basic", "equipped_special"]:
		var group: Dictionary = skills.get(group_name, {})
		for skill_id in group.values():
			if not str(skill_id).is_empty() and skill_id not in result:
				result.append(skill_id)
	return result
