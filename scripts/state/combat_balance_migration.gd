extends RefCounted
## 把 v2/v3 存档中的旧生命池、伤势和当前体力按比例迁移到 v4 数值体系。

static func migrate(profile: Dictionary, combat_state: Dictionary, source_version: int, new_true_max: int) -> Dictionary:
	if source_version >= 4:
		return combat_state
	var result := combat_state.duplicate(true)
	var constitution := maxf(0.0, float(profile.get("attributes", {}).get("constitution", 0)))
	var cultivation := maxi(0, int(profile.get("vitals", {}).get("cultivation", 0)))
	var mp_multiplier := _legacy_mp_multiplier(result, source_version, constitution, cultivation)
	var old_mp_max := cultivation * mp_multiplier
	var old_true_max := _legacy_hp_max(constitution, old_mp_max)
	var old_injury := clampi(int(result.get("injury", 0)), 0, old_true_max - 1)
	var old_effective_max := maxi(1, old_true_max - old_injury)
	var injury_ratio := float(old_injury) / float(old_true_max)
	var new_injury := clampi(int(round(injury_ratio * float(new_true_max))), 0, new_true_max - 1)
	var new_effective_max := maxi(1, new_true_max - new_injury)
	var old_hp := clampi(int(result.get("hp", old_effective_max)), 0, old_effective_max)
	result.injury = new_injury
	result.hp = 0 if old_hp <= 0 else clampi(int(round(float(old_hp) / float(old_effective_max) * float(new_effective_max))), 1, new_effective_max)
	if source_version == 2 and mp_multiplier == 2:
		result.mp = int(round(float(maxi(0, int(result.get("mp", 0)))) * 0.5))
	return result

## v2 中途曾把精力倍率从 2 改为 1 却未提升存档版本；只有存档数值能证明来自早期公式时才减半。
static func _legacy_mp_multiplier(state: Dictionary, source_version: int, constitution: float, cultivation: int) -> int:
	if source_version != 2 or cultivation <= 0:
		return 1
	if int(state.get("mp", 0)) > cultivation:
		return 2
	var one_x_max := _legacy_hp_max(constitution, cultivation)
	var injury := maxi(0, int(state.get("injury", 0)))
	var one_x_effective := maxi(1, one_x_max - mini(injury, one_x_max - 1))
	return 2 if injury >= one_x_max or int(state.get("hp", 0)) > one_x_effective else 1

static func _legacy_hp_max(constitution: float, mp_max: int) -> int:
	return maxi(1, int(floor(140.0 * (1.0 + constitution * 0.025))) + int(floor(float(mp_max) * 0.2)))
