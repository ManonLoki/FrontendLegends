extends Node

const PRODUCTION_SAVE_PATH := "user://frontend_legends_save_v5.json"
const SAVE_VERSION := 5

var active_save_path := PRODUCTION_SAVE_PATH

const SURVIVAL_TICK_SEC := 15.0
const AGE_TICK_SEC := 28800.0
const MIN_HIT_RATE := 0.45
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

## 将测试切换到独立存档；正式存档路径和备份绝不会被测试删除或覆盖。
func use_test_save_path(suite_name: String) -> void:
	var safe_name := suite_name.validate_filename().to_lower()
	active_save_path = OS.get_temp_dir().path_join("frontend_legends_test_saves/%s.json" % (safe_name if not safe_name.is_empty() else "unnamed"))

## 返回当前实际读写路径，供测试和诊断使用。
func current_save_path() -> String:
	return active_save_path

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
	var capacity := vitals_capacity(attributes)
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
	combat_state = _default_combat_state(player_hp_max())
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
		combat_state.hp = mini(player_effective_hp_max(), int(combat_state.get("hp", 0)) + pairs * 3)
	var previous_age_tick := int(floor(previous / AGE_TICK_SEC))
	var current_age_tick := int(floor(game_time_sec / AGE_TICK_SEC))
	vitals.age = int(vitals.get("age", 18)) + current_age_tick - previous_age_tick
	profile.vitals = vitals

## 剥离运行时派生属性和本局装备后，以临时文件和备份轮换安全写出 v5 存档。
func save_game() -> bool:
	if not has_profile():
		return false
	# 对齐原项目：穿戴状态仅在本局内存中存在，不进入存档。
	# attributes 是由 base_attributes + 基础功法反哺生成的运行时派生值，保存时剥离，
	# 读档统一重算，避免冗余字段成为第二个互相冲突的数据源。
	var saved_profile := profile.duplicate(true)
	saved_profile.erase("attributes")
	var data := {"version": SAVE_VERSION, "profile": saved_profile, "game_time_sec": game_time_sec, "combat_state": combat_state, "inventory": inventory, "item_cooldowns": item_cooldowns}
	return _write_save_document(data)

## 只读取当前 v5 存档；更早结构已因稳定 UUID 切换而明确失效。
func load_game() -> bool:
	var parsed := _read_save_document(active_save_path)
	if parsed.is_empty():
		var backup_path := active_save_path + ".bak"
		parsed = _read_save_document(backup_path)
		if parsed.is_empty():
			return false
		# 主文件损坏或缺失时从已验证备份恢复，避免下一次保存覆盖唯一可用副本。
		_restore_backup(backup_path, active_save_path)
	if int(parsed.get("version", 0)) != SAVE_VERSION:
		return false
	profile = parsed.get("profile", {})
	game_time_sec = float(parsed.get("game_time_sec", 0.0))
	combat_state = parsed.get("combat_state", _default_combat_state())
	inventory = parsed.get("inventory", {})
	# 装备按原设定只存在于本局内存；读档后一律空手。
	equipment = _default_equipment()
	item_cooldowns = parsed.get("item_cooldowns", {})
	if profile.has("skills"):
		SkillSystem.ensure_skills()
		SkillSystem.refresh_derived_attributes()
	_normalize_loaded_profile()
	normalize_combat_state()
	return has_profile()

## 读取并校验存档文档；无效 JSON、版本或角色资料统一视为不可用。
func _read_save_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var parsed = parser.data
	if not parsed is Dictionary:
		return {}
	if int(parsed.get("version", 0)) != SAVE_VERSION:
		return {}
	if not parsed.get("profile", {}) is Dictionary or str(parsed.get("profile", {}).get("name", "")).strip_edges().is_empty():
		return {}
	return parsed

## 先完整写入临时文件，再轮换旧档为备份并替换主文件，任何一步失败都保留可恢复副本。
func _write_save_document(data: Dictionary) -> bool:
	var target := ProjectSettings.globalize_path(active_save_path)
	var temporary := target + ".tmp"
	var backup := target + ".bak"
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	file = null
	if _read_save_document(temporary).is_empty():
		DirAccess.remove_absolute(temporary)
		return false
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(target) and DirAccess.rename_absolute(target, backup) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	if DirAccess.rename_absolute(temporary, target) == OK:
		return true
	if FileAccess.file_exists(backup) and not FileAccess.file_exists(target):
		DirAccess.rename_absolute(backup, target)
	return false

## 将验证通过的备份复制回主文件，同时保留原备份以便再次恢复。
func _restore_backup(backup_path: String, target_path: String) -> void:
	var backup := ProjectSettings.globalize_path(backup_path)
	var target := ProjectSettings.globalize_path(target_path)
	var recovery := target + ".recover"
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if FileAccess.file_exists(recovery):
		DirAccess.remove_absolute(recovery)
	if DirAccess.copy_absolute(backup, recovery) != OK:
		return
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(recovery, target) != OK:
		DirAccess.copy_absolute(backup, target)

## 裁剪角色资料、钳制资源并清理未知物品记录。
func _normalize_loaded_profile() -> void:
	profile.name = str(profile.get("name", "")).strip_edges().substr(0, 10)
	var attributes: Dictionary = profile.get("attributes", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})
	var vitals: Dictionary = profile.get("vitals", {})
	var capacity := vitals_capacity(attributes)
	vitals.food = clampi(int(vitals.get("food", 0)), 0, capacity)
	vitals.water = clampi(int(vitals.get("water", 0)), 0, capacity)
	for key in ["money", "potential", "experience", "cultivation"]:
		vitals[key] = maxi(0, int(vitals.get(key, 0)))
	profile.vitals = vitals
	var item_catalog: Dictionary = _load_data_document("items.json").get("items", {})
	inventory = _normalize_item_map(inventory, item_catalog, true)
	item_cooldowns = _normalize_item_map(item_cooldowns, item_catalog, false)

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
	for suffix in ["", ".bak", ".tmp", ".recover"]:
		var path := ProjectSettings.globalize_path(active_save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

## 四维软修正共用的中性点。
const ATTRIBUTE_NEUTRAL := 25.0

## 以 25 为中性点计算带上下界的属性软修正；保留小数，使 NPC 的细微资质差异真实生效。
func centered_scale(value: float, per_point: float, lo: float, hi: float) -> float:
	return clampf(1.0 + (maxf(0.0, value) - ATTRIBUTE_NEUTRAL) * per_point, lo, hi)

## 编码 → 基础攻击：保留主输出定位，但下调斜率，避免同时拥有攻击、携带和招架后过强。
func attack_base(strength: float) -> float:
	var s := maxf(0.0, strength)
	return maxf(1.0, 12.0 + s * 1.50 * centered_scale(s, 0.003, 0.94, 1.08))

## 架构 → 防御：与生命、冥想分摊收益，继续交给递减公式换算减伤。
func defense_base(constitution: float) -> float:
	var c := maxf(0.0, constitution)
	return maxf(0.0, c * 0.95 * centered_scale(c, 0.0025, 0.94, 1.07))

## 架构 → 冥想速度/内力上限修正。
func meditation_modifier(constitution: float) -> float:
	return centered_scale(constitution, 0.02, 0.60, 1.60)

## 基础体力以同配点镜像战 8–12 回合为标尺；非战斗 NPC 再由阶位系数单独压缩。
func base_hp_max(constitution: float) -> int:
	return maxi(1, int(floor(190.0 + maxf(0.0, constitution) * 5.2)))

## 精力按平方根反哺体力；系数用于维持各功法等级的同配点镜像战在 8–12 回合。
func hp_max_with_mp_boost(constitution: float, mp_max: int) -> int:
	return base_hp_max(constitution) + int(floor(sqrt(maxf(0.0, float(mp_max))) * 3.0))

## 食物/饮水携带上限 = 基础 200 + 每点编码（strength）6，全仓唯一公式来源。
const VITALS_BASE_CAPACITY := 200
const VITALS_CAPACITY_PER_STRENGTH := 6

func vitals_capacity(attributes: Dictionary = {}) -> int:
	var source: Dictionary = attributes if not attributes.is_empty() else profile.get("attributes", {})
	return VITALS_BASE_CAPACITY + int(source.get("strength", 25)) * VITALS_CAPACITY_PER_STRENGTH

## 精力上限 = 精力修为 + 当前装备架构功法的上限加成；功法数据中的 mpMaxPerLv 不再是空字段。
func player_mp_max() -> int:
	var cultivation := maxi(0, int(profile.get("vitals", {}).get("cultivation", 0)))
	var skill_system := get_node_or_null("/root/SkillSystem")
	var skill_bonus := 0
	if skill_system != null and skill_system.get("loadout") != null:
		skill_bonus = int(skill_system.combat_bonus().get("mp_max", 0))
	return cultivation + maxi(0, skill_bonus)

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

## 命中、暴击、招架与伤害结算的核心平衡系数；调参时与 docs/balance_design.md
## 和 tests/combat/mirror_round_benchmark.gd 的 8–12 回合基准保持同步。
const HIT_RATE_BASE := 0.78
const HIT_RATE_PER_AGILITY := 0.009
const CRIT_BASE := 0.03
const CRIT_PER_AGILITY := 0.0
const CRIT_PER_WISDOM := 0.003
const CRIT_MIN := 0.02
const CRIT_MAX := 0.30
const PARRY_BASE := 0.04
const PARRY_PER_STRENGTH := 0.0025
const PARRY_CAP := 0.55
const PARRY_DAMAGE_MULT := 0.60
const CRIT_DAMAGE_MULT := 1.5
const DAMAGE_VARIANCE := 0.2

## 按双方思维差计算并钳制基础命中率；同档命中率提高到 78%，减少连续空过回合。
func combat_hit_rate(attacker: Dictionary, defender: Dictionary) -> float:
	return clampf(HIT_RATE_BASE + (float(attacker.get("agility", 0)) - float(defender.get("agility", 0))) * HIT_RATE_PER_AGILITY, MIN_HIT_RATE, MAX_HIT_RATE)

## 将非负防御转换为递减收益的伤害减免率。
func mitigation(defense: float) -> float:
	var value := maxf(0.0, defense)
	return value / (value + 100.0)

## 暴击集中由灵感决定；思维专注命中与先手，避免一项属性包办全部进攻判定。
func combat_crit_rate(attacker: Dictionary, bonus := 0.0) -> float:
	return clampf(CRIT_BASE + float(attacker.get("agility", 0)) * CRIT_PER_AGILITY + float(attacker.get("wisdom", 0)) * CRIT_PER_WISDOM + float(bonus), CRIT_MIN, CRIT_MAX)

## 基础招架由编码提供少量概率，功法与装备在此基础上叠加并统一封顶。
func combat_parry_rate(defender: Dictionary, bonus := 0.0) -> float:
	return clampf(PARRY_BASE + float(defender.get("strength", 0)) * PARRY_PER_STRENGTH + float(bonus), 0.0, PARRY_CAP)

## 已命中的普通攻击只在此处结算招架、暴击、减伤和浮动；镜像基准复用本函数，
## 使“忽略闪避”的校准口径不会复制一份容易漂移的伤害公式。
func resolve_landed_attack(attack_power: float, attacker: Dictionary, defender: Dictionary, defense: float, parry_bonus := 0.0, crit_bonus := 0.0) -> Dictionary:
	var is_parried := randf() < combat_parry_rate(defender, parry_bonus)
	var is_crit := randf() < combat_crit_rate(attacker, crit_bonus)
	var variance := 1.0 - DAMAGE_VARIANCE / 2.0 + randf() * DAMAGE_VARIANCE
	var damage := maxi(1, int(floor(attack_power * (1.0 - mitigation(defense)) * (PARRY_DAMAGE_MULT if is_parried else 1.0) * (CRIT_DAMAGE_MULT if is_crit else 1.0) * variance)))
	return {"hit": true, "parried": is_parried, "crit": is_crit, "damage": damage}

## 攻击结算顺序固定：命中判定 → 招架判定 → 暴击判定 → 伤害随机浮动，
## 后续步骤只在命中成立后才滚动，与参考项目的判定顺序保持一致。
func resolve_attack(attack_power: float, attacker: Dictionary, defender: Dictionary, defense: float, hit_bonus := 0.0, dodge_bonus := 0.0, parry_bonus := 0.0, crit_bonus := 0.0, guaranteed_hit := false) -> Dictionary:
	var hit_rate := clampf(combat_hit_rate(attacker, defender) + float(hit_bonus) - float(dodge_bonus), MIN_HIT_RATE, MAX_HIT_RATE)
	if not bool(guaranteed_hit) and randf() >= hit_rate:
		return {"hit": false, "parried": false, "crit": false, "damage": 0}
	return resolve_landed_attack(attack_power, attacker, defender, defense, parry_bonus, crit_bonus)
