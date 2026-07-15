extends Node

const SAVE_PATH := "user://frontend_legends_save_v2.json"
const SAVE_VERSION := 3
const COMPATIBLE_SAVE_VERSIONS: Array[int] = [2, SAVE_VERSION]

const SURVIVAL_TICK_SEC := 15.0
const AGE_TICK_SEC := 28800.0
const MIN_HIT_RATE := 0.28
const MAX_HIT_RATE := 0.95
## 每点精力修为增加的精力上限。
const MP_PER_CULTIVATION := 1

var profile: Dictionary = {}
var game_time_sec := 0.0
var combat_state := _default_combat_state()
var inventory: Dictionary = {}
var equipment := _default_equipment()
var item_cooldowns: Dictionary = {}

## 自动加载单例就绪时尝试读取现有存档。
func _ready() -> void:
	load_game()

## 创建体力、精力和伤势的默认战斗状态。
func _default_combat_state(hp: int = 1) -> Dictionary:
	return {"hp": hp, "mp": 0, "injury": 0}

## 创建五个装备槽位均为空的本局装备状态。
func _default_equipment() -> Dictionary:
	return {"weapon": "", "armor": "", "shoe": "", "accessory1": "", "accessory2": ""}

## 判断当前资料是否已经包含有效角色姓名。
func has_profile() -> bool:
	return not str(profile.get("name", "")).strip_edges().is_empty()

## 按创角输入建立完整角色资料并立即写入存档。
func create_profile(player_name: String, custom_attributes: Dictionary = {}, gender := "male") -> void:
	var clean_name := player_name.strip_edges()
	var attributes: Dictionary = custom_attributes if not custom_attributes.is_empty() else {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25}
	var capacity := 200 + int(attributes.get("strength", 25)) * 10
	var appearance := clampi(int(attributes.get("constitution", 25)) * 2 - 10, 0, 100)
	var peak := 0
	for value in attributes.values(): peak = maxi(peak, int(value))
	if int(attributes.get("strength", 0)) >= 40 and int(attributes.get("strength", 0)) >= peak:
		appearance = maxi(0, appearance - 10)
	profile = {
		"name": clean_name,
		"gender": gender,
		"base_attributes": attributes.duplicate(true),
		"attributes": attributes.duplicate(true),
		"vitals": {"food": capacity, "water": capacity, "money": 50, "potential": 0, "experience": 0, "age": 18, "appearance": appearance, "cultivation": 0},
		"sect": "",
		"master": "",
		"skills": SkillSystem.create_default_skills(),
		"money": 0
	}
	combat_state = _default_combat_state(_true_hp_max())
	game_time_sec = 0.0
	inventory = {}
	equipment = _default_equipment()
	item_cooldowns = {}
	save_game()

## 用“跨越了多少个 tick 边界”而非直接除以增量，防止单次 advance_time 跨越
## 多个 tick 时漏算（如批量快进）；食物/饮水按对子消耗，两者中较少的一项封顶。
func advance_time(seconds: float) -> void:
	var previous := game_time_sec
	game_time_sec = maxf(0.0, game_time_sec + maxf(0.0, seconds))
	var previous_survival_tick := int(floor(previous / SURVIVAL_TICK_SEC))
	var current_survival_tick := int(floor(game_time_sec / SURVIVAL_TICK_SEC))
	var ticks := current_survival_tick - previous_survival_tick
	var vitals: Dictionary = profile.get("vitals", {})
	var pairs := mini(ticks, mini(int(vitals.get("food", 0)), int(vitals.get("water", 0))))
	if pairs > 0:
		vitals.food = int(vitals.get("food", 0)) - pairs
		vitals.water = int(vitals.get("water", 0)) - pairs
		combat_state.injury = maxi(0, int(combat_state.get("injury", 0)) - pairs * 2)
		combat_state.hp = mini(_effective_hp_max(), int(combat_state.get("hp", 0)) + pairs * 3)
	var previous_age_tick := int(floor(previous / AGE_TICK_SEC))
	var current_age_tick := int(floor(game_time_sec / AGE_TICK_SEC))
	vitals.age = int(vitals.get("age", 18)) + current_age_tick - previous_age_tick
	profile.vitals = vitals

## 剥离运行时派生属性和本局装备后写出 v3 存档。
func save_game() -> void:
	if not has_profile():
		return
	# 对齐原项目：穿戴状态仅在本局内存中存在，不进入存档。
	# attributes 是由 base_attributes + 基础功法反哺生成的运行时派生值，保存时剥离，
	# 读档统一重算，避免冗余字段成为第二个互相冲突的数据源。
	var saved_profile := profile.duplicate(true)
	saved_profile.erase("attributes")
	var data := {"version": SAVE_VERSION, "profile": saved_profile, "game_time_sec": game_time_sec, "combat_state": combat_state, "inventory": inventory, "item_cooldowns": item_cooldowns}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

## 读取兼容版本存档，迁移字段并重建派生状态。
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	if typeof(parsed) != TYPE_DICTIONARY or not COMPATIBLE_SAVE_VERSIONS.has(int(parsed.get("version", 0))):
		return false
	profile = parsed.get("profile", {})
	game_time_sec = float(parsed.get("game_time_sec", 0.0))
	combat_state = parsed.get("combat_state", _default_combat_state())
	inventory = parsed.get("inventory", {})
	# 旧档可能带 equipment；按原设定读档后一律空手，不恢复该字段。
	equipment = _default_equipment()
	item_cooldowns = parsed.get("item_cooldowns", {})
	if profile.has("skills"):
		SkillSystem.ensure_skills()
		_normalize_base_attributes()
		SkillSystem.refresh_derived_attributes()
	_normalize_loaded_profile()
	normalize_combat_state()
	return has_profile()

## 裁剪角色资料、钳制资源并清理未知物品记录。
func _normalize_loaded_profile() -> void:
	profile.name = str(profile.get("name", "")).strip_edges().substr(0, 10)
	var attributes: Dictionary = profile.get("attributes", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	var vitals: Dictionary = profile.get("vitals", {})
	var capacity := 200 + int(attributes.get("strength", 25)) * 10
	vitals.food = clampi(int(vitals.get("food", 0)), 0, capacity)
	vitals.water = clampi(int(vitals.get("water", 0)), 0, capacity)
	for key in ["money", "potential", "experience", "cultivation"]:
		vitals[key] = maxi(0, int(vitals.get(key, 0)))
	profile.vitals = vitals
	if not str(profile.get("sect", "")).is_empty() and str(profile.get("master", "")).is_empty():
		profile.master = _entry_master_for_sect(str(profile.sect))
	var item_catalog: Dictionary = _load_data_document("items.json").get("items", {})
	inventory = _normalize_item_map(inventory, item_catalog, true)
	item_cooldowns = _normalize_item_map(item_cooldowns, item_catalog, false)

## 由旧档当前属性扣除技能反哺，重建基础四维。
func _normalize_base_attributes() -> void:
	var current: Dictionary = profile.get("attributes", {})
	var base: Dictionary = profile.get("base_attributes", {})
	var levels: Dictionary = profile.get("skills", {}).get("levels", {})
	var nudges := {"strength": 0, "agility": 0, "constitution": 0, "wisdom": 0}
	var mapping := {
		"basicStrength": "strength", "basicAgility": "agility",
		"basicConstitution": "constitution", "basicParry": "strength", "literacy": "wisdom",
	}
	for skill_id in mapping:
		var key: String = mapping[skill_id]
		nudges[key] = int(nudges[key]) + int(floor(float(levels.get(skill_id, 0)) / 10.0))
	for key in nudges:
		var fallback := int(current.get(key, 25)) - int(nudges[key])
		base[key] = maxi(5, int(floor(float(base.get(key, fallback)))))
	profile.base_attributes = base

## 清理物品数量或冷却映射中的未知、空值和负数项。
func _normalize_item_map(raw: Dictionary, known_items: Dictionary, counts: bool) -> Dictionary:
	var result: Dictionary = {}
	for raw_id in raw:
		var item_id := str(raw_id).strip_edges()
		if item_id.is_empty() or not known_items.has(item_id):
			continue
		if counts:
			var amount := maxi(0, int(raw[raw_id]))
			if amount > 0:
				result[item_id] = amount
		else:
			result[item_id] = maxf(0.0, float(raw[raw_id]))
	return result

## 从教学上限最低的人物中推断旧档缺失的入门师父。
func _entry_master_for_sect(sect_name: String) -> String:
	var npc_catalog: Dictionary = _load_data_document("npcs.json").get("npcs", {})
	var teach_stock: Dictionary = _load_data_document("skills.json").get("teachStock", {})
	var best_id := ""
	var best_cap := 2147483647
	for npc_id in npc_catalog:
		var npc: Dictionary = npc_catalog[npc_id]
		if not npc.has("joinSect") or str(npc.get("sect", "")) != sect_name:
			continue
		var cap := 0
		for entry in teach_stock.get(npc_id, []):
			if entry is Dictionary:
				cap = maxi(cap, int(entry.get("maxTeachLevel", 0)))
		if cap < best_cap:
			best_id = str(npc_id)
			best_cap = cap
	return best_id

## 读取一份静态 JSON 数据文档，失败时返回空字典。
func _load_data_document(file_name: String) -> Dictionary:
	var file := FileAccess.open("res://assets/Data/" + file_name, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	return parsed if parsed is Dictionary else {}

## 清空全部本局状态并删除正式存档文件。
func delete_save() -> void:
	QuestSystem.reset_runtime()
	profile = {}
	combat_state = _default_combat_state()
	game_time_sec = 0.0
	inventory = {}
	equipment = _default_equipment()
	item_cooldowns = {}
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

## 四维以 25 为中性点的统一软修正（对齐参考项目 AttributeFormulas.ts）。
const ATTRIBUTE_NEUTRAL := 25.0

## 以 25 为中性点计算带上下界的属性软修正。
func centered_scale(value: float, per_point: float, lo: float, hi: float) -> float:
	return clampf(1.0 + (maxf(0.0, floor(value)) - ATTRIBUTE_NEUTRAL) * per_point, lo, hi)

## 编码 → 基础攻击：编码本值 × 专精修正。
func attack_base(strength: float) -> float:
	var s := maxf(0.0, floor(strength))
	return maxf(1.0, floor(s * centered_scale(s, 0.006, 0.85, 1.15)))

## 架构 → 防御：原架构×2 保持中性点，再按架构做软修正。
func defense_base(constitution: float) -> float:
	var c := maxf(0.0, floor(constitution))
	return maxf(0.0, floor(c * 2.0 * centered_scale(c, 0.004, 0.90, 1.12)))

## 架构 → 冥想速度/内力上限修正。
func meditation_modifier(constitution: float) -> float:
	return centered_scale(constitution, 0.02, 0.60, 1.60)

## 仅按架构属性计算不含精力反哺的基础体力上限。
func base_hp_max(constitution: float) -> int:
	return maxi(1, int(floor(140.0 * (1.0 + maxf(0.0, constitution) * 0.025))))

## 体力上限 = 基础体力 + 精力反哺（每点精力上限 +0.2 点体力上限）。
func hp_max_with_mp_boost(constitution: float, mp_max: int) -> int:
	return base_hp_max(constitution) + int(floor(maxf(0.0, float(mp_max)) * 0.2))

## 精力上限与精力修为 1:1，对齐参照项目 PlayerCombatState.getMpMax。
func player_mp_max() -> int:
	return maxi(0, int(profile.get("vitals", {}).get("cultivation", 0)))

## 返回包含精力反哺的玩家真实体力上限。
func player_hp_max() -> int:
	var attributes: Dictionary = profile.get("attributes", {})
	return hp_max_with_mp_boost(float(attributes.get("constitution", 0)), player_mp_max())

## 从真实体力上限扣除伤势，得到当前有效上限。
func player_effective_hp_max() -> int:
	var true_max := player_hp_max()
	var injury := clampi(int(combat_state.get("injury", 0)), 0, true_max - 1)
	return maxi(1, true_max - injury)

## 返回有效体力上限占真实上限的整数百分比。
func player_effective_hp_percent() -> int:
	return clampi(int(round(float(player_effective_hp_max()) / float(maxi(1, player_hp_max())) * 100.0)), 1, 100)

## 按最新属性、修为和伤势钳制当前战斗资源。
func normalize_combat_state() -> void:
	var true_max := player_hp_max()
	combat_state.injury = clampi(int(combat_state.get("injury", 0)), 0, true_max - 1)
	combat_state.hp = clampi(int(combat_state.get("hp", player_effective_hp_max())), 0, player_effective_hp_max())
	combat_state.mp = clampi(int(combat_state.get("mp", player_mp_max())), 0, player_mp_max())

## 为旧调用方保留真实体力上限兼容入口。
func _true_hp_max() -> int:
	return player_hp_max()

## 为旧调用方保留有效体力上限兼容入口。
func _effective_hp_max() -> int:
	return player_effective_hp_max()

## 按双方思维差计算并钳制基础命中率。
func combat_hit_rate(attacker: Dictionary, defender: Dictionary) -> float:
	return clampf(0.72 + (float(attacker.get("agility", 0)) - float(defender.get("agility", 0))) * 0.02, MIN_HIT_RATE, MAX_HIT_RATE)

## 将非负防御转换为递减收益的伤害减免率。
func mitigation(defense: float) -> float:
	var value := maxf(0.0, defense)
	return value / (value + 80.0)

## 攻击结算顺序固定：命中判定 → 招架判定 → 暴击判定 → 伤害随机浮动，
## 后续步骤只在命中成立后才滚动，与参考项目的判定顺序保持一致。
func resolve_attack(attack_power: float, attacker: Dictionary, defender: Dictionary, defense: float, hit_bonus := 0.0, dodge_bonus := 0.0, parry_bonus := 0.0, crit_bonus := 0.0) -> Dictionary:
	var hit_rate := clampf(combat_hit_rate(attacker, defender) + float(hit_bonus) - float(dodge_bonus), MIN_HIT_RATE, MAX_HIT_RATE)
	if randf() >= hit_rate:
		return {"hit": false, "parried": false, "crit": false, "damage": 0}
	var parry := clampf(float(defender.get("strength", 0)) * 0.01 - 0.05 + float(parry_bonus), 0.0, 0.65)
	var is_parried := randf() < parry
	var is_crit := randf() < clampf(CombatSystem.CRIT_BASE + float(attacker.get("constitution", 0)) * CombatSystem.CRIT_PER_CONSTITUTION + float(crit_bonus), 0.02, 0.25)
	var variance := 0.9 + randf() * 0.2
	var damage := maxi(1, int(floor(attack_power * (1.0 - mitigation(defense)) * (0.5 if is_parried else 1.0) * (1.5 if is_crit else 1.0) * variance)))
	return {"hit": true, "parried": is_parried, "crit": is_crit, "damage": damage}
