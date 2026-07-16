extends RefCounted
## 动态悬赏目标与悬赏环结算服务；通过 QuestSystem 保存唯一任务状态。

const SKILL_MAPS := preload("res://scripts/skills/skill_maps.gd")
const BASIC_SKILL_KEYS := SKILL_MAPS.BASIC_SKILL_IDS
const NAME_MODIFIERS: Array[String] = ["傻X", "脑残", "白痴", "霸道", "凶狠"]
const NAME_ROLES: Array[String] = ["老板", "客户", "领导", "同事", "朋友"]
const NAME_SURNAMES: Array[String] = ["赵", "钱", "孙", "李", "周", "吴", "郑", "王"]
const NAME_GIVEN: Array[String] = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

var quests: Node

## 绑定任务系统协调器。
func _init(quest_system: Node) -> void:
	quests = quest_system

## 按玩家当前属性与基础技能生成一个随环数成长的悬赏人物。
func offer(generator_id: String = "bountyring_xiaobuer") -> Dictionary:
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	var runtime_id := "generator:" + generator_id
	if definition.is_empty() or quests.active.has(runtime_id) or quests._on_cooldown(generator_id):
		return {"ok": false, "message": "悬赏暂不可接取"}
	quests.bounty_sequence += 1
	var target_id := "__bounty_target_%d" % quests.bounty_sequence
	var spawn_maps: Array = definition.get("spawnMaps", [])
	if spawn_maps.is_empty():
		return {"ok": false, "message": "（悬赏池是空的，先在 quests.json 配置）"}
	var target_map := str(spawn_maps[randi() % spawn_maps.size()])
	var kill_index := int(quests.ring_progress.get(generator_id, 0))
	var target_scale := maxf(0.05, 1.0 - float(definition.get("baseDiscount", 0.0)) + float(definition.get("roundGrowth", 0.0)) * kill_index)
	var scaled_attributes := _scaled_dictionary(GameState.profile.get("attributes", {}), GameState.profile.get("attributes", {}).keys(), target_scale)
	var player_skills: Dictionary = GameState.profile.get("skills", {}).get("levels", {})
	var scaled_skills := _scaled_dictionary(player_skills, BASIC_SKILL_KEYS, target_scale)
	var target_name := str(NAME_MODIFIERS.pick_random()) + str(NAME_ROLES.pick_random()) + str(NAME_SURNAMES.pick_random()) + str(NAME_GIVEN.pick_random())
	var target_sprite := str(definition.get("targetSprite", "npc-30")).strip_edges()
	if target_sprite.is_empty():
		target_sprite = "npc-30"
	NpcSystem.register_runtime(target_id, {"displayName": target_name, "sprite": target_sprite, "roles": ["civilian"], "description": "小不二悬赏缉拿的对象，据说与你有些渊源。", "defaultLine": "你……找我有事？", "attributes": scaled_attributes, "skillLevels": scaled_skills, "equippedSkillIds": BASIC_SKILL_KEYS.duplicate()})
	quests.bounty_target = {"target_id": target_id, "target_name": target_name, "target_sprite": target_sprite, "map_id": target_map, "map_name": DataRegistry.region_display_name(target_map), "generator_id": generator_id}
	if not quests.bounty_money_base.has(generator_id):
		quests.bounty_money_base[generator_id] = float(definition.get("rewardBase", 0))
	if not quests.bounty_stat_base.has(generator_id):
		quests.bounty_stat_base[generator_id] = float(definition.get("rewardBase", 0))
	quests.active[runtime_id] = {"generator_id": generator_id, "kind": "bountyRing", "giverNpcId": definition.get("giverNpcId", ""), "state": "active", "progress": 0, "round": kill_index + 1, "target": quests.bounty_target}
	var message: String = quests._line(definition, "offer", "悬赏目标：{target}（{map}）", {"target": quests.bounty_target.target_name, "map": quests.bounty_target.map_name})
	return {"ok": true, "message": message, "target": quests.bounty_target}

## 按缩放倍率复制指定字段，所有生成数值至少为一。
func _scaled_dictionary(source: Dictionary, keys: Array, scale: float) -> Dictionary:
	var result: Dictionary = {}
	for key in keys:
		result[key] = maxi(1, int(round(float(source.get(key, 1)) * scale)))
	return result

## 记录动态人物的安全地图格，并同步活动任务目标。
func set_target_tile(tile: Vector2i) -> void:
	if quests.bounty_target.is_empty():
		return
	quests.bounty_target["tile"] = tile
	for runtime_id in quests.active:
		var runtime: Dictionary = quests.active[runtime_id]
		if str(runtime.get("generator_id", "")) == str(quests.bounty_target.get("generator_id", "")):
			runtime["target"] = quests.bounty_target

## 返回暗网悬赏榜当前显示文本。
func board_text(generator_id: String = "bountyring_xiaobuer") -> String:
	if quests.bounty_target.is_empty():
		return "暗网悬赏榜暂时空着，去找小不二接一单吧。"
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	var values := {"target": quests.bounty_target.get("target_name", ""), "map": quests.bounty_target.get("map_name", quests.bounty_target.get("map_id", ""))}
	return quests._line(definition, "offer", "「{target}」已在「{map}」，请速速将其捉拿归案！", values)

## 注销动态人物并清空当前悬赏目标。
func clear_target() -> void:
	if not quests.bounty_target.is_empty():
		NpcSystem.unregister_runtime(str(quests.bounty_target.get("target_id", "")))
	quests.bounty_target = {}

## 结算一次悬赏环击杀，并按是否满环更新下一次奖励基数。
func settle_ring(runtime_id: String, runtime: Dictionary, definition: Dictionary) -> Dictionary:
	var generator_id := str(runtime.get("generator_id", ""))
	var money_base := float(quests.bounty_money_base.get(generator_id, definition.get("rewardBase", 0)))
	var stat_base := float(quests.bounty_stat_base.get(generator_id, definition.get("rewardBase", 0)))
	var fluctuation_min := float(definition.get("fluctuationMin", 0.0))
	var fluctuation_max := maxf(fluctuation_min, float(definition.get("fluctuationMax", fluctuation_min)))
	var reward := _rolled_reward(money_base, stat_base, fluctuation_min, fluctuation_max)
	quests._grant_reward(reward)
	var kills_done := int(quests.ring_progress.get(generator_id, 0)) + 1
	var ring_size := maxi(1, int(definition.get("ringSize", 1)))
	var ring_done := kills_done >= ring_size
	if ring_done:
		quests.ring_progress[generator_id] = 0
		quests.bounty_money_base[generator_id] = float(definition.get("rewardBase", 0))
		quests.bounty_stat_base[generator_id] = float(definition.get("rewardBase", 0))
	else:
		quests.ring_progress[generator_id] = kills_done
		quests.bounty_money_base[generator_id] = money_base * (1.0 + randf_range(float(definition.get("rewardGrowthMin", 0.0)), float(definition.get("rewardGrowthMax", 0.0))))
		quests.bounty_stat_base[generator_id] = stat_base * (1.0 + randf_range(float(definition.get("statGrowthMin", definition.get("rewardGrowthMin", 0.0))), float(definition.get("statGrowthMax", definition.get("rewardGrowthMax", 0.0)))))
	quests.active.erase(runtime_id)
	quests.cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 0))
	return {"reward": reward, "complete": ring_done, "target": runtime.get("target", {})}

## 为经验、潜能和 Token 分别滚动同一浮动区间。
func _rolled_reward(money_base: float, stat_base: float, minimum: float, maximum: float) -> Dictionary:
	var roll := func(base: float) -> int:
		return maxi(0, int(floor(base * (1.0 + randf_range(minimum, maximum)))))
	return {"experience": roll.call(stat_base * 3.0), "potential": roll.call(stat_base * 3.0), "money": roll.call(money_base * 3.0 * 0.8)}
