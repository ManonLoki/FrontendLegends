extends Node

const SAVE_PATH := "user://frontend_legends_save_v1.json"
const SAVE_VERSION := 1

const SURVIVAL_TICK_SEC := 15.0
const AGE_TICK_SEC := 28800.0
const MIN_HIT_RATE := 0.28
const MAX_HIT_RATE := 0.95

var profile: Dictionary = {}
var game_time_sec := 0.0
var combat_state := _default_combat_state()
var inventory: Dictionary = {}
var equipment := _default_equipment()
var item_cooldowns: Dictionary = {}

func _ready() -> void:
	load_game()

func _default_combat_state(hp: int = 1) -> Dictionary:
	return {"hp": hp, "mp": 0, "injury": 0}

func _default_equipment() -> Dictionary:
	return {"weapon": "", "armor": "", "shoe": "", "accessory1": "", "accessory2": ""}

func has_profile() -> bool:
	return not str(profile.get("name", "")).strip_edges().is_empty()

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
		"vitals": {"food": capacity, "water": capacity, "money": 100000, "potential": 100000, "experience": 0, "age": 18, "appearance": appearance, "neigong": 0},
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

func save_game() -> void:
	if not has_profile():
		return
	# 对齐原项目：穿戴状态仅在本局内存中存在，不进入存档。
	var data := {"version": SAVE_VERSION, "profile": profile, "game_time_sec": game_time_sec, "combat_state": combat_state, "inventory": inventory, "item_cooldowns": item_cooldowns}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file else null
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != SAVE_VERSION:
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
		SkillSystem.refresh_derived_attributes()
	return has_profile()

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

func base_hp_max(constitution: float) -> int:
	return maxi(1, int(floor(140.0 * (1.0 + maxf(0.0, constitution) * 0.025))))

## 体力上限 = 基础体力 + 精力反哺（每点精力上限 +0.2 点体力上限）。
func hp_max_with_mp_boost(constitution: float, mp_max: int) -> int:
	return base_hp_max(constitution) + int(floor(maxf(0.0, float(mp_max)) * 0.2))

## 玩家精力上限即精力修为（neigong）本身。
func player_mp_max() -> int:
	return maxi(0, int(profile.get("vitals", {}).get("neigong", 0)))

func player_hp_max() -> int:
	var attributes: Dictionary = profile.get("attributes", {})
	return hp_max_with_mp_boost(float(attributes.get("constitution", 0)), player_mp_max())

func player_effective_hp_max() -> int:
	return maxi(1, player_hp_max() - int(combat_state.get("injury", 0)))

func _true_hp_max() -> int:
	return player_hp_max()

func _effective_hp_max() -> int:
	return player_effective_hp_max()

func combat_hit_rate(attacker: Dictionary, defender: Dictionary) -> float:
	return clampf(0.72 + (float(attacker.get("agility", 0)) - float(defender.get("agility", 0))) * 0.02, MIN_HIT_RATE, MAX_HIT_RATE)

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
