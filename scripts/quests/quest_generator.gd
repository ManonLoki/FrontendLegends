extends RefCounted
## 通用任务生成与环任务推进服务；按 JSON 类型构建目标和奖励。

var quests: Node

## 绑定任务系统协调器。
func _init(quest_system: Node) -> void:
	quests = quest_system

## 根据生成器类型创建差事、普通悬赏、跑腿环或击杀环。
func offer(generator_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	var runtime_id := "generator:" + generator_id
	if definition.is_empty():
		return {"ok": false, "message": "未知任务生成器"}
	if quests.active.has(runtime_id) or quests._on_cooldown(generator_id):
		return {"ok": false, "message": "该环任务进行中"}
	var generator_type := str(definition.get("type", ""))
	var excluded_npc_ids: Array[String] = quests._reserved_task_npc_ids()
	var placed_target: Dictionary = quests._placed_npc_target(excluded_npc_ids, generator_type == "killRing")
	if generator_type in ["ring", "killRing"] and placed_target.is_empty():
		return {"ok": false, "message": "（环任务目标池是空的，请检查地图 Interactive 层 NPC id）"}
	var runtime := {"generator_id": generator_id, "kind": generator_type, "giverNpcId": definition.get("giverNpcId", ""), "state": "active", "progress": 0, "round": 1}
	var failure := _assign_target(runtime, definition, generator_type, placed_target, excluded_npc_ids)
	if not failure.is_empty():
		return failure
	_assign_ring_item(runtime, definition, generator_type)
	_assign_reward(runtime, definition, generator_type)
	quests.active[runtime_id] = runtime
	return {"ok": true, "message": _offer_message(runtime, definition, generator_id)}

## 按类型把目标写入运行状态；失败时返回可直接显示的错误字典。
func _assign_target(runtime: Dictionary, definition: Dictionary, generator_type: String, placed_target: Dictionary, excluded_npc_ids: Array[String]) -> Dictionary:
	if generator_type == "errand":
		var candidates := _errand_candidates(definition.get("pool", {}), excluded_npc_ids)
		if candidates.is_empty():
			return {"ok": false, "message": "（差事池是空的，先在 quests.json 配置）"}
		runtime.target = candidates[randi() % candidates.size()]
		runtime.met_goal = false
	elif generator_type == "bounty":
		var enemies: Array = definition.get("enemyPool", []).filter(func(enemy_id):
			var id := str(enemy_id)
			return not excluded_npc_ids.has(id) and quests._is_kill_quest_target(id)
		)
		if enemies.is_empty():
			return {"ok": false, "message": "（悬赏池没有符合资格且未被其他任务占用的人物）"}
		var enemy_id := str(enemies[randi() % enemies.size()])
		var enemy: Dictionary = DataRegistry.get_npc(enemy_id)
		var prefixes: Array = definition.get("enemyTemplate", {}).get("namePrefix", [])
		var prefix := str(prefixes[randi() % prefixes.size()]) if not prefixes.is_empty() else ""
		var maps: Array = definition.get("spawnMaps", [])
		runtime.target = {"target_id": enemy_id, "target_name": prefix + str(enemy.get("displayName", enemy_id)), "target_kind": "npc", "map_id": str(maps[randi() % maps.size()]) if not maps.is_empty() else ""}
		runtime.ready = false
	elif generator_type in ["ring", "killRing"]:
		var npc: Dictionary = DataRegistry.get_npc(placed_target.get("npc_id", ""))
		runtime.target = {"target_id": placed_target.get("npc_id", ""), "target_name": npc.get("display_name", npc.get("displayName", placed_target.get("npc_id", ""))), "map_id": placed_target.get("map_id", ""), "map_name": placed_target.get("map_name", placed_target.get("map_id", ""))}
	return {}

## 把差事物品池和人物池转换为统一候选目标。
func _errand_candidates(pool: Dictionary, excluded_npc_ids: Array[String] = []) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for item_id in pool.get("items", []):
		candidates.append({"target_id": str(item_id), "target_name": DataRegistry.get_item(str(item_id)).get("name", item_id), "target_kind": "item"})
	for npc_id in pool.get("npcs", []):
		if excluded_npc_ids.has(str(npc_id)):
			continue
		var npc: Dictionary = DataRegistry.get_npc(str(npc_id))
		candidates.append({"target_id": str(npc_id), "target_name": npc.get("displayName", npc_id), "target_kind": "npc"})
	return candidates

## 按物品概率为跑腿环选择额外交付物。
func _assign_ring_item(runtime: Dictionary, definition: Dictionary, generator_type: String) -> void:
	if generator_type != "ring":
		return
	var items: Array = definition.get("items", [])
	if not items.is_empty() and randf() < float(definition.get("itemChance", 0.5)):
		var item_id := str(items[randi() % items.size()])
		runtime.item_id = item_id
		runtime.item_name = DataRegistry.get_item(item_id).get("name", item_id)

## 计算初始奖励；交付物成本单独记录，结算时不参与环数成长或随机浮动。
func _assign_reward(runtime: Dictionary, definition: Dictionary, generator_type: String) -> void:
	if generator_type == "killRing":
		runtime.reward = quests._kill_ring_reward(definition, str(runtime.get("target", {}).get("target_id", "")))
		return
	runtime.reward = quests._base_reward(definition)
	if generator_type == "ring" and not str(runtime.get("item_id", "")).is_empty():
		var item_price := maxi(0, int(DataRegistry.get_item(str(runtime.item_id)).get("price", 0)))
		runtime.item_refund_money = int(ceil(float(item_price) * maxf(0.0, float(definition.get("itemRefundRate", 1.0)))))
		runtime.reward.money = int(runtime.reward.get("money", 0)) + int(definition.get("itemExtraMoney", 0))

## 按是否需要物品选择接取文案，并填充目标、地图和环数。
func _offer_message(runtime: Dictionary, definition: Dictionary, generator_id: String) -> String:
	var target: Dictionary = runtime.get("target", {})
	var line_key := "offerItem" if not str(runtime.get("item_id", "")).is_empty() else "offer"
	var ring_size := maxi(1, int(definition.get("ringSize", 1)))
	var values := {"target": target.get("target_name", ""), "map": target.get("map_name", target.get("map_id", "")), "item": runtime.get("item_name", ""), "count": int(quests.ring_progress.get(generator_id, 0)) % ring_size + 1, "ringSize": ring_size}
	return quests._line(definition, line_key, "已接取：{target}", values)

## 交付可选物品、推进环数、发放缩放奖励并设置冷却。
func advance(generator_id: String, amount: int = 1) -> Dictionary:
	var runtime_id := "generator:" + generator_id
	if not quests.active.has(runtime_id):
		return {"ok": false, "message": "没有进行中的环任务"}
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	var runtime: Dictionary = quests.active[runtime_id]
	var delivery_failure := _consume_delivery_item(runtime, definition)
	if not delivery_failure.is_empty():
		return delivery_failure
	runtime.progress = int(quests.ring_progress.get(generator_id, runtime.get("progress", 0))) + maxi(0, amount)
	var ring_size := maxi(1, int(definition.get("ringSize", 1)))
	var reward_round := int(floor(float(int(runtime.progress) - 1) / float(ring_size))) + 1
	var reward: Dictionary = quests._scaled_reward(definition, runtime.get("reward", quests._base_reward(definition)), reward_round)
	reward.money = int(reward.get("money", 0)) + maxi(0, int(runtime.get("item_refund_money", 0)))
	quests._grant_reward(reward)
	quests.ring_progress[generator_id] = int(runtime.progress)
	quests.active.erase(runtime_id)
	quests.cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 30))
	var target: Dictionary = runtime.get("target", {}) if runtime.get("target", {}) is Dictionary else {}
	return {"ok": true, "complete": int(runtime.progress) % ring_size == 0, "progress": runtime.progress, "required": ring_size, "reward": reward, "target": target}

## 验证并扣除跑腿环交付物；装备中的任务物品不能直接交付。
func _consume_delivery_item(runtime: Dictionary, definition: Dictionary) -> Dictionary:
	if str(definition.get("type", "")) != "ring" or str(runtime.get("item_id", "")).is_empty():
		return {}
	var item_id := str(runtime.get("item_id", ""))
	if InventorySystem.count(item_id) < 1:
		return {"ok": false, "message": quests._line(definition, "needItem", "【{item}】不在你身上，可交不了差。", {"item": runtime.get("item_name", item_id)})}
	if not InventorySystem.equipped_slot(item_id).is_empty():
		return {"ok": false, "message": quests._line(definition, "itemEquipped", "先卸下【{item}】再交付。", {"item": runtime.get("item_name", item_id)})}
	InventorySystem.remove_item(item_id, 1)
	return {}

## 生成任务推进文案，并在满环时追加环完成文本。
func advance_message(definition: Dictionary, advanced: Dictionary, talk_key: String, fallback: String) -> String:
	var target: Dictionary = advanced.get("target", {})
	var values := {"target": target.get("target_name", ""), "map": target.get("map_id", ""), "reward": quests._format_reward(advanced.get("reward", {}))}
	var message: String = quests._line(definition, talk_key, fallback, values)
	if bool(advanced.get("complete", false)):
		var ring_done_line: String = quests._line(definition, "ringDone", "", {"ringSize": int(definition.get("ringSize", 1))})
		if not ring_done_line.is_empty():
			message += "\n" + ring_done_line
	return message
