extends Node
const SKILL_TRAINING := preload("res://scripts/skills/skill_training.gd")
const SKILL_LOADOUT := preload("res://scripts/skills/skill_loadout.gd")
const SKILL_MEMBERSHIP := preload("res://scripts/skills/skill_membership.gd")
const SKILL_LEARNING := preload("res://scripts/skills/skill_learning.gd")
## 学习、冥想和练功分别采用独立的固定推进间隔。
const LEARNING_TICK_SECONDS := 1.0 / 30.0
const MEDITATION_TICK_SECONDS := 1.0 / 30.0
const PRACTICE_TICK_SECONDS := 1.0 / 5.0
const MEDITATION_INNER_POWER_UNIT := 25.0
const SKILL_MAPS := preload("res://scripts/skills/skill_maps.gd")
const THEMES := SKILL_MAPS.THEMES
const BASIC_SKILL_IDS := SKILL_MAPS.BASIC_SKILL_IDS

## 灵感（wisdom）对学习速率的软修正：以 25 为中性点，灵感越高研习越快。
const WISDOM_BASELINE := 25.0
const WISDOM_LEARN_RATE_PER_POINT := 0.02
const LEARN_RATE_MIN := 0.65
const LEARN_RATE_MAX := 1.25
## 满级单级成本跨度；由旧版 20 下调为 4，保留二次成长但缩短重复任务量。
const LEARN_COST_SPAN := 4.0

## 门派绝招按内力功法等级解锁：一档 30 级、二档 80 级。
const ULT_TIER1_ARCH_LEVEL := 30
const ULT_TIER2_ARCH_LEVEL := 80

@onready var training := SKILL_TRAINING.new(self)
@onready var loadout := SKILL_LOADOUT.new(self)
@onready var membership := SKILL_MEMBERSHIP.new(self)
@onready var learning := SKILL_LEARNING.new(self)

## 创建新角色的空技能、装备槽、进度和加力状态。
func create_default_skills() -> Dictionary:
	# 对齐参考项目：新角色不会任何技能，也不会自动装备基础功法。
	# 基础功法须经师父或秘籍学会，再由玩家在功法菜单中主动装备。
	## 持久化字段统一使用蛇形命名，避免存档同时出现两套命名风格。
	return {"levels": {}, "equipped_basic": {}, "equipped_special": {}, "progress": {}, "learn_progress": {}, "practice_progress": {}, "force_power": 0}

## 兼容旧存档：早期版本用单一 "equipped" 槽位混存基础/门派功法，这里一次性
## 迁移拆分为 equipped_basic/equipped_special 两个独立槽位后即删除旧字段。
func ensure_skills() -> Dictionary:
	if not GameState.profile.has("skills") or GameState.profile.skills.is_empty():
		GameState.profile.skills = create_default_skills()
	var skills: Dictionary = GameState.profile.skills
	## 第二版存档使用驼峰字段；读取后一次性迁移到标准字段。
	_migrate_saved_key(skills, "learnProgress", "learn_progress", {})
	_migrate_saved_key(skills, "practiceProgress", "practice_progress", {})
	_migrate_saved_key(skills, "forcePower", "force_power", 0)
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

## 新字段优先于旧字段，迁移不会覆盖已经写入的标准数据。
func _migrate_saved_key(skills: Dictionary, old_key: String, new_key: String, fallback: Variant) -> void:
	if not skills.has(new_key):
		skills[new_key] = skills.get(old_key, fallback)
	skills.erase(old_key)

## 返回指定技能当前等级，未学习时为零。
func level(skill_id: String) -> int:
	return int(ensure_skills().levels.get(skill_id, 0))

## 秘籍升级路径：即时生效，只消耗书本本身（消耗品逻辑见 InventorySystem.use_item），
## 与 learn_tick 的按 tick 消耗潜能/Token 不同，两者是互不干扰的两条升级来源。
func learn_from_book(skill_id: String, max_learn_level: int = -1) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"ok": false, "message": "未知功法"}
	var requires: Dictionary = definition.get("requires", {})
	if not str(requires.get("sect", "")).is_empty() and str(GameState.profile.get("sect", "")) != str(requires.get("sect", "")):
		return {"ok": false, "message": "未拜入%s，学不得【%s】" % [requires.get("sect", ""), definition.get("name", skill_id)]}
	var current := level(skill_id)
	var max_level := int(definition.get("maxLevel", 100))
	var book_cap := mini(max_level, maxi(0, max_learn_level)) if max_learn_level >= 0 else max_level
	if current >= book_cap:
		return {"ok": false, "message": "此书只能将【%s】读到 %d 级。" % [definition.get("name", skill_id), book_cap]}
	var before_attrs: Dictionary = GameState.profile.get("attributes", {}).duplicate()
	ensure_skills().levels[skill_id] = current + 1
	ensure_skills().get("learn_progress", {}).erase(skill_id)
	_refresh_derived_attributes()
	return {"ok": true, "message": "读罢秘籍，领悟【%s】至 %d 级%s。" % [definition.get("name", skill_id), current + 1, _attribute_growth_suffix(before_attrs)], "level": current + 1}

## 返回当前师承允许向指定人物学习的技能列表。
func learn_options_for_npc(npc_id: String) -> Array[String]:
	return membership.learn_options_for_npc(npc_id)

## 菜单显隐用：未拜入该门派，或已拜入但此人造诣高于当前师父（可改投深造）。
func can_join(npc_id: String) -> bool:
	return membership.can_join(npc_id)

## 验证资格并尝试拜指定人物为师。
func join_npc(npc_id: String) -> Dictionary:
	return membership.join_npc(npc_id)

## 研习为两阶段消耗：先按 tick 花潜能推进进度条到 required，进度满后一次性
## 支付 Token 学费（80% 曲线成本）才真正升级——潜能只买“进度”，Token 买“结果”。
func learn_tick(npc_id: String, skill_id: String) -> Dictionary:
	return learning.learn_tick(npc_id, skill_id)

## 综合火候门槛用：门派功法按 2 倍计入，鼓励深耕本门而非只堆基础功法。
func _skill_power() -> int:
	var levels: Dictionary = ensure_skills().get("levels", {})
	var total := 0
	for basic_id in BASIC_SKILL_IDS:
		total += maxi(0, int(levels.get(basic_id, 0)))
	for skill_id in levels:
		if str(DataRegistry.get_skill(str(skill_id)).get("category", "")) == "sect":
			total += maxi(0, int(levels[skill_id])) * 2
	return total

## 均衡度门槛用：与 _skill_power 不同，这里不加权——只看各科是否都有练到，
## 防止玩家靠单科堆权重刷过均衡门槛。
func _average_skill_level() -> float:
	var values: Array[int] = []
	var levels: Dictionary = ensure_skills().get("levels", {})
	for basic_id in BASIC_SKILL_IDS:
		values.append(maxi(0, int(levels.get(basic_id, 0))))
	for skill_id in levels:
		if str(DataRegistry.get_skill(str(skill_id)).get("category", "")) == "sect":
			values.append(maxi(0, int(levels[skill_id])))
	var total := 0
	for value in values:
		total += value
	return float(total) / float(maxi(1, values.size()))

## 返回人物对指定技能或同主题基础技能的教学上限。
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

## 返回指定技能当前学习进度与下一级所需总量。
func learning_progress(skill_id: String) -> Dictionary:
	var definition := DataRegistry.get_skill(skill_id)
	if definition.is_empty():
		return {"current": 0, "total": 1}
	var next_level := level(skill_id) + 1
	var required := _learn_required(definition, next_level, _learning_cost_rate())
	return {
		"current": mini(required, int(ensure_skills().get("learn_progress", {}).get(skill_id, 0))),
		"total": required,
	}

## 学艺/读秘籍升级后，四维是否因基础功法等级提升而跟涨（見 _refresh_derived_attributes）。
func _attribute_growth_suffix(before: Dictionary) -> String:
	var after: Dictionary = GameState.profile.get("attributes", {})
	for key in after:
		if int(after.get(key, 0)) > int(before.get(key, 0)):
			return "，四维亦有精进"
	return ""

## 按技能曲线、目标等级和灵感倍率计算学习需求。
func _learn_required(definition: Dictionary, level_to_reach: int, rate: float) -> int:
	if level_to_reach <= 1:
		return 1
	var max_cost := maxi(20, int(ceil(float(definition.get("costBase", 100)) * float(definition.get("costFactor", 1.0)) * LEARN_COST_SPAN)))
	var denominator := maxi(1.0, float(int(definition.get("maxLevel", 100)) - 1))
	var t := clampf(float(level_to_reach - 1) / denominator, 0.0, 1.0)
	# 原项目严格顺序：基础曲线先 ceil → 乘悟性倍率 → ceil 到偶数。
	# 不能把倍率提前乘进基础曲线，否则高灵感档在部分等级会少 2 点潜能。
	var base_required := maxi(1, int(ceil(1.0 + float(max_cost - 1) * pow(t, 2.0))))
	var normalized_rate := clampf(rate, 0.65, 1.25)
	return maxi(2, int(ceil(float(base_required) * normalized_rate / 2.0)) * 2)

## 将角色灵感转换为学习成本倍率。
func _learning_cost_rate() -> float:
	var wisdom := float(GameState.profile.get("attributes", {}).get("wisdom", 25))
	return clampf(1.0 - (wisdom - WISDOM_BASELINE) * WISDOM_LEARN_RATE_PER_POINT, LEARN_RATE_MIN, LEARN_RATE_MAX)

## 学艺与练功必须共用同一条技能经验曲线；公开此查询供 HUD 和回归测试使用。
func skill_exp_required(skill_id: String, level_to_reach: int) -> int:
	var definition := DataRegistry.get_skill(skill_id)
	return 1 if definition.is_empty() else _learn_required(definition, level_to_reach, _learning_cost_rate())

## 基础功法练至每 10 级为对应属性 +1（封顶 50），映射表见 skill_maps.gd，
## 与存档规范化（GameState._normalize_base_attributes）互为逆运算。
func _refresh_derived_attributes() -> void:
	var base: Dictionary = GameState.profile.get("base_attributes", GameState.profile.get("attributes", {}))
	var levels: Dictionary = ensure_skills().get("levels", {})
	var attributes := base.duplicate(true)
	var nudges := {"strength": 0, "agility": 0, "constitution": 0, "wisdom": 0}
	for skill_id in BASIC_SKILL_IDS:
		var key: String = str(SKILL_MAPS.BASIC_SKILL_ATTRIBUTE.get(skill_id, ""))
		if not str(key).is_empty():
			nudges[key] = int(nudges.get(key, 0)) + int(floor(float(levels.get(skill_id, 0)) / 10.0))
	for key in nudges:
		attributes[key] = mini(50, int(base.get(key, 0)) + int(nudges[key]))
	GameState.profile.attributes = attributes

## 公开重算基础功法反哺四维的稳定入口。
func refresh_derived_attributes() -> void:
	_refresh_derived_attributes()

const THEME_BASIC_SKILL := SKILL_MAPS.THEME_BASIC_SKILL

## 基础与特殊功法使用独立槽（见 unequip），装备时按 category 分流到对应槽位。
## 对齐参考项目 SaveManager.ts：其余状态（生存 tick、消耗品、商贩交易）只改内存缓存，
## 须玩家 ESC→保存才落盘；唯独功法装备立即写盘，避免退出菜单后丢失当前选择。
func equip(skill_id: String) -> Dictionary:
	return loadout.equip(skill_id)

## 基础与特殊功法使用独立槽，卸下其中一类不会影响另一类。同 equip() 立即落盘。
func unequip(skill_id: String) -> Dictionary:
	return loadout.unequip(skill_id)

## 查询指定主题和类别当前装备的功法 ID。
func equipped_id(theme: String, category: String) -> String:
	return loadout.equipped_id(theme, category)

## 返回去重后的全部已装备功法 ID。
func equipped_skill_ids() -> Array[String]:
	return loadout.equipped_skill_ids()

## 装备招架功法的伤势减免（战后伤害转伤势的折扣，封顶 75%）。
func injury_reduce() -> float:
	return loadout.injury_reduce()

## 本门架构（内力）功法等级合计（用于疗伤门槛）：装备与否均计入所有已学门派架构功法。
func _arch_sect_level_sum() -> int:
	return loadout.arch_sect_level_sum()

## 返回所有已学本门架构功法的等级合计。
func arch_sect_level_sum() -> int:
	return _arch_sect_level_sum()

## 汇总已装备功法提供的全部战斗加成。
func combat_bonus() -> Dictionary:
	return loadout.combat_bonus()

## “加力”是玩家可调节的精力换伤害挡位（见 combat_system.player_attack）：
## 设得越高，攻击时消耗的精力越多、伤害加成越高，上限由架构功法等级决定。
func force_power_cap() -> int:
	return loadout.force_power_cap()

## 返回按当前内功上限钳制后的加力档位。
func force_power() -> int:
	return loadout.force_power()

## 设置并返回新的玩家加力档位。
func set_force_power(value: int) -> Dictionary:
	return loadout.set_force_power(value)

## 返回已装备功法当前解锁的攻击、闪避和招架招式。
func unlocked_moves() -> Array:
	return loadout.unlocked_moves()

## 返回当前架构功法已经解锁的门派绝招。
func unlocked_ults() -> Array:
	return loadout.unlocked_ults()

## 为旧测试和调用方保留绝招字典构建入口。
func _make_ult(config: Dictionary, tier: int, inner_power: int) -> Dictionary:
	return loadout._make_ult(config, tier, inner_power)

## 冥想先填充当前精力，满值后转化为一点精力修为并清空当前精力。
## 理论上限只由已装备的架构功法和架构属性决定，赛博空间传送也使用该上限。
func meditation_cap() -> int:
	return training.meditation_cap()

## 按明确输入计算冥想修为上限，供测试与预览使用。
func meditation_cap_from_values(constitution: float, basic_arch_level: int, advanced_arch_level: int) -> int:
	return training.meditation_cap_from_values(constitution, basic_arch_level, advanced_arch_level)

## 返回理论修为终点对应的最大精力上限。
func meditation_max_mp_cap() -> int:
	return training.meditation_max_mp_cap()

## 推进一次固定时间片的冥想。
func meditate_tick() -> Dictionary:
	return training.meditate_tick()

## 返回当前精力填充阶段的冥想进度。
func meditation_progress() -> Dictionary:
	return training.meditation_progress()

## 返回指定主题已装备本门功法的有效等级。
func equipped_sect_skill_level(theme: String) -> int:
	return training.equipped_sect_skill_level(theme)

## 判断基础与门派架构功法是否满足冥想条件。
func can_meditate() -> bool:
	return training.can_meditate()

## 返回指定门派功法当前练功等级上限。
func practice_cap(skill_id: String) -> int:
	return training.practice_cap(skill_id)

## 推进一次固定时间片的自主练功。
func practice_tick(skill_id: String) -> Dictionary:
	return training.practice_tick(skill_id)

## 返回指定功法当前练功进度和等级。
func practice_progress(skill_id: String) -> Dictionary:
	return training.practice_progress(skill_id)

## 在非战斗训练入口以精力换取等量体力。
func channel_hp() -> Dictionary:
	return training.channel_hp()

## 消耗精力按本门架构功法门槛治疗伤势。
func heal_injury() -> Dictionary:
	return training.heal_injury()
