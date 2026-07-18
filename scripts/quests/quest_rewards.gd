extends RefCounted
## 任务奖励计算与击杀环结算服务；集中维护成长、浮动和发放规则。

const COMBAT_RULES := preload("res://scripts/combat/combat_rules.gd")

var quests: Node

## 绑定任务系统协调器。
func _init(quest_system: Node) -> void:
	quests = quest_system

## 优先使用完整奖励表，否则由奖励基数生成经验、潜能和 Token。
func base_reward(definition: Dictionary) -> Dictionary:
	var reward: Dictionary = definition.get("reward", {})
	if not reward.is_empty():
		return reward.duplicate(true)
	var base := int(definition.get("rewardBase", 0))
	if base > 0:
		return {"experience": base * 2, "potential": base * 3, "money": int(ceil(float(base) * 3.0 * 0.8))}
	return {}

## 导师项目的难度只改变体力成本，三种项目始终使用任务表中的固定奖励。
func novice_reward(definition: Dictionary, _variant: Dictionary) -> Dictionary:
	return base_reward(definition)

## 按目标四维总和和平均技能等级计算生死簿奖励。
func kill_ring_reward(definition: Dictionary, target_id: String) -> Dictionary:
	var target: Dictionary = DataRegistry.get_npc(target_id)
	var attributes: Dictionary = target.get("attributes", {})
	var skill_levels: Dictionary = target.get("skillLevels", {})
	var attribute_score := 0.0
	for key in ["strength", "agility", "constitution", "wisdom"]:
		attribute_score += float(attributes.get(key, 1))
	var skill_score := 0.0
	for skill_id in skill_levels:
		skill_score += float(skill_levels[skill_id])
	var average_skill := skill_score / float(maxi(1, skill_levels.size()))
	var rank := str(target.get("combatRank", COMBAT_RULES.DEFAULT_COMBAT_RANK))
	var rank_scale := float(COMBAT_RULES.NPC_RANK_REWARD_SCALE.get(rank, COMBAT_RULES.NPC_RANK_REWARD_SCALE[COMBAT_RULES.DEFAULT_COMBAT_RANK]))
	var raw := (attribute_score * 1.5 + average_skill * 4.0) * rank_scale * float(definition.get("rewardPotentialScale", 1.0))
	var potential := clampi(int(round(raw)), int(definition.get("rewardPotentialMin", 0)), int(definition.get("rewardPotentialMax", 999999)))
	return {"experience": potential, "potential": potential, "money": int(ceil(float(potential) * 0.8))}

## 按环数线性增长并设置封顶，避免长期环任务的复利奖励摧毁经济。
func scaled_reward(definition: Dictionary, reward: Dictionary, round_index: int) -> Dictionary:
	var result := reward.duplicate(true)
	var growth := 1.0
	if definition.has("ringGrowth"):
		growth = 1.0 + float(definition.get("ringGrowth", 0.0)) * maxi(0, round_index - 1)
	elif definition.has("rewardGrowthMin"):
		var growth_rate := randf_range(float(definition.get("rewardGrowthMin", 0.0)), float(definition.get("rewardGrowthMax", 0.0)))
		growth = 1.0 + growth_rate * maxi(0, round_index - 1)
	growth = minf(growth, maxf(1.0, float(definition.get("growthCap", 3.0))))
	var fluctuation_min := -float(definition.get("fluctuation", 0.0))
	var fluctuation_max := float(definition.get("fluctuation", 0.0))
	if definition.has("fluctuationMin"):
		fluctuation_min = float(definition.get("fluctuationMin", 0.0))
		fluctuation_max = float(definition.get("fluctuationMax", 0.0))
	var fluctuation := 1.0 + randf_range(fluctuation_min, fluctuation_max)
	for key in result:
		if result[key] is int or result[key] is float:
			result[key] = maxi(0, int(floor(float(result[key]) * growth * fluctuation)))
	return result

## 发放一次生死簿击杀奖励，并在满环后重置进度。
func settle_kill_ring(runtime_id: String, runtime: Dictionary, definition: Dictionary) -> Dictionary:
	var generator_id := str(runtime.get("generator_id", ""))
	var reward: Dictionary = runtime.get("reward", {})
	quests._grant_reward(reward)
	var kills_done := int(quests.ring_progress.get(generator_id, 0)) + 1
	var ring_size := maxi(1, int(definition.get("ringSize", 1)))
	var ring_done := kills_done >= ring_size
	quests.ring_progress[generator_id] = 0 if ring_done else kills_done
	quests.active.erase(runtime_id)
	quests.cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 0))
	return {"reward": reward, "complete": ring_done, "target": runtime.get("target", {})}
