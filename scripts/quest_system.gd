extends Node

var active: Dictionary = {}
var completed: Dictionary = {}
var bounty_target: Dictionary = {}
var cooldown_until: Dictionary = {}
var ring_progress: Dictionary = {}
var bounty_money_base: Dictionary = {}
var bounty_stat_base: Dictionary = {}
var bounty_sequence := 0
const BASIC_SKILL_KEYS: Array[String] = ["basicStrength", "basicAgility", "basicConstitution", "basicParry", "literacy"]
const BOUNTY_NAME_MODIFIERS: Array[String] = ["傻X", "脑残", "白痴", "霸道", "凶狠"]
const BOUNTY_NAME_ROLES: Array[String] = ["老板", "客户", "领导", "同事", "朋友"]
const BOUNTY_NAME_SURNAMES: Array[String] = ["赵", "钱", "孙", "李", "周", "吴", "郑", "王"]
const BOUNTY_NAME_GIVEN: Array[String] = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

func _line(definition: Dictionary, key: String, fallback: String, values: Dictionary = {}) -> String:
	var result := str(definition.get("lines", {}).get(key, fallback))
	for name in values:
		result = result.replace("{" + str(name) + "}", str(values[name]))
	return result

func _format_reward(reward: Dictionary) -> String:
	return "（经验+%d 潜能+%d Token+%d）" % [int(reward.get("experience", 0)), int(reward.get("potential", 0)), int(reward.get("money", 0))]

func _on_cooldown(generator_id: String) -> bool:
	return GameState.game_time_sec < float(cooldown_until.get(generator_id, 0.0))

func _active_for_npc(npc_id: String) -> Dictionary:
	for runtime_id in active:
		var runtime: Dictionary = active[runtime_id]
		if str(runtime.get("giverNpcId", "")) == npc_id or str(runtime.get("completion_giver_id", "")) == npc_id:
			return runtime
		var target = runtime.get("target", {})
		# 只有九日环目标是即时任务端点；普通送信目标仍走普通对话，仅标记 met_goal。
		if str(runtime.get("kind", "")) == "ring" and target is Dictionary and str(target.get("target_id", "")) == npc_id:
			return runtime
	return {}

func _grant_reward(reward: Dictionary) -> void:
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	for key in ["experience", "potential", "money"]:
		vitals[key] = int(vitals.get(key, 0)) + int(reward.get(key, 0))
	GameState.profile.vitals = vitals

func _placed_npc_target(exclude_id: String = "") -> Dictionary:
	var excluded: Array = [exclude_id] if not exclude_id.is_empty() else []
	var candidates: Array[Dictionary] = DataRegistry.list_placed_npc_targets(excluded)
	return candidates[randi() % candidates.size()] if not candidates.is_empty() else {}

func interact_npc(npc_id: String) -> String:
	var novice: Dictionary = DataRegistry.get_quest("novice_darkxue_project")
	var novice_id := "novice_darkxue_project"
	if active.has(novice_id):
		var runtime: Dictionary = active[novice_id]
		if npc_id == str(runtime.get("completion_giver_id", "")):
			var hp_cost := int(runtime.get("hp_cost", 0))
			if int(GameState.combat_state.get("hp", 0)) <= hp_cost:
				return str(novice.get("lines", {}).get("lowHp", "状态不足，暂时无法交付任务。"))
			GameState.combat_state.hp = maxi(1, int(GameState.combat_state.hp) - hp_cost)
			var result := complete(novice_id)
			cooldown_until[novice_id] = GameState.game_time_sec + float(novice.get("cooldownSec", 30))
			return _line(novice, "done", "任务完成：{target} {reward}", {"target": runtime.get("target", "项目"), "reward": result.get("message", "")})
		if npc_id == str(novice.get("giverNpcId", "")):
			return str(novice.get("lines", {}).get("inProgress", "任务进行中。")).replace("{target}", str(runtime.get("target", "项目")))

	if npc_id == str(novice.get("giverNpcId", "")):
		if _on_cooldown(novice_id):
			return _line(novice, "cooldown", "暂时没有新任务。")
		var requires: Dictionary = novice.get("requires", {})
		if int(GameState.profile.get("vitals", {}).get("experience", 0)) > int(requires.get("expMax", 999999999)):
			return str(novice.get("lines", {}).get("tooExp", "这个任务不适合你了。"))
		var variants: Array = novice.get("variants", [])
		if variants.is_empty():
			return str(novice.get("lines", {}).get("cooldown", "暂时没有任务。"))
		var variant: Dictionary = variants[randi() % variants.size()]
		active[novice_id] = {"state": "active", "progress": 0, "completion_giver_id": novice.get("completionGiverId", ""), "target": variant.get("title", "项目"), "hp_cost": variant.get("hpCost", 0), "reward": novice.get("reward", {})}
		return str(novice.get("lines", {}).get("accepted", "已接取任务：{target}")).replace("{target}", str(variant.get("title", "项目")))

	for generator_id in DataRegistry.quest_generators:
		var definition: Dictionary = DataRegistry.quest_generators[generator_id]
		if npc_id != str(definition.get("giverNpcId", "")):
			continue
		var runtime_id := "generator:" + str(generator_id)
		if active.has(runtime_id):
			var runtime: Dictionary = active[runtime_id]
			if str(runtime.get("kind", "")) in ["errand", "bounty"]:
				return _deliver_standard(runtime_id, runtime, definition)
			var line_key := "inProgressItem" if str(runtime.get("kind", "")) == "ring" and not str(runtime.get("item_id", "")).is_empty() else "inProgress"
			return _line(definition, line_key, "任务进行中。", {"target": runtime.get("target", {}).get("target_name", "") if runtime.get("target", {}) is Dictionary else "", "map": runtime.get("target", {}).get("map_id", "") if runtime.get("target", {}) is Dictionary else "", "item": runtime.get("item_name", "")})
		if _on_cooldown(str(generator_id)):
			return _line(definition, "cooldown", "暂时没有新任务。")
		var requires: Dictionary = definition.get("requires", {})
		if int(GameState.profile.get("vitals", {}).get("age", 0)) < int(requires.get("minAge", 0)):
			return _line(definition, "requireFail", "你年岁尚浅，暂时接不了这项任务。")
		var generator_type := str(definition.get("type", ""))
		var offered: Dictionary = offer_bounty(str(generator_id)) if generator_type == "bountyRing" else offer_generator(str(generator_id))
		return str(offered.get("message", "任务暂不可接取"))

	# 普通送信目标不接管对话，只记录玩家确已与其交谈。
	for runtime_id in active:
		var talk_runtime: Dictionary = active[runtime_id]
		var talk_target: Dictionary = talk_runtime.get("target", {}) if talk_runtime.get("target", {}) is Dictionary else {}
		if str(talk_runtime.get("kind", "")) == "errand" and str(talk_target.get("target_kind", "")) == "npc" and str(talk_target.get("target_id", "")) == npc_id:
			talk_runtime.met_goal = true
			return ""
	var runtime := _active_for_npc(npc_id)
	if not runtime.is_empty():
		var generator_id := str(runtime.get("generator_id", ""))
		if not generator_id.is_empty():
			var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
			if runtime.get("target", {}) is Dictionary and str(runtime.target.get("target_id", "")) == npc_id:
				var advanced := advance_generator(generator_id, 1)
				if not bool(advanced.get("ok", false)):
					return str(advanced.get("message", "任务已完成"))
				var talk_key := "targetItem" if not str(runtime.get("item_id", "")).is_empty() else "targetTalk"
				return _generator_advance_message(definition, advanced, talk_key, "「知道了知道了」{reward}")
			var target_data: Dictionary = runtime.get("target", {})
			return _line(definition, "inProgress", "任务进行中。", {"target": target_data.get("target_name", ""), "map": target_data.get("map_id", "")})
	return ""

func begin_novice_completion(endpoint_id: String) -> Dictionary:
	var novice_id := "novice_darkxue_project"
	if not active.has(novice_id):
		return {}
	var runtime: Dictionary = active[novice_id]
	if endpoint_id != str(runtime.get("completion_giver_id", "")):
		return {}
	var definition: Dictionary = DataRegistry.get_quest(novice_id)
	var hp_cost := int(runtime.get("hp_cost", 0))
	if int(GameState.combat_state.get("hp", 0)) <= hp_cost:
		return {"message": str(definition.get("lines", {}).get("lowHp", "状态不足，暂时无法交付任务。")), "lock_seconds": 0.0, "can_finish": false}
	return {
		"message": "你坐到电脑前，开始实现【%s】。\n需求文档越看越长，报错一行接一行，你屏住呼吸继续敲代码……" % runtime.get("target", "项目"),
		"lock_seconds": 5.0,
		"can_finish": true,
	}

func finish_novice_completion(endpoint_id: String) -> String:
	var novice_id := "novice_darkxue_project"
	if not active.has(novice_id):
		return "（任务状态已变化）"
	var runtime: Dictionary = active[novice_id]
	if endpoint_id != str(runtime.get("completion_giver_id", "")):
		return "（任务状态已变化）"
	var definition: Dictionary = DataRegistry.get_quest(novice_id)
	var hp_cost := int(runtime.get("hp_cost", 0))
	if int(GameState.combat_state.get("hp", 0)) <= hp_cost:
		return str(definition.get("lines", {}).get("lowHp", "状态不足，暂时无法交付任务。"))
	GameState.combat_state.hp = maxi(1, int(GameState.combat_state.hp) - hp_cost)
	var reward: Dictionary = runtime.get("reward", _base_reward(definition))
	_grant_reward(reward)
	active.erase(novice_id)
	cooldown_until[novice_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 30))
	return "你完成了%s任务，获得了 %d经验 %d金钱 %d潜能" % [runtime.get("target", "项目"), int(reward.get("experience", 0)), int(reward.get("money", 0)), int(reward.get("potential", 0))]

func offer(quest_id: String) -> Dictionary:
	if active.has(quest_id):
		return {"ok": false, "message": "任务进行中"}
	var definition: Dictionary = DataRegistry.get_quest(quest_id)
	if definition.is_empty():
		return {"ok": false, "message": "未知任务"}
	active[quest_id] = {"state": "active", "progress": 0}
	return {"ok": true, "message": "已接取：%s" % definition.get("title", quest_id)}

func progress(quest_id: String, amount: int = 1) -> void:
	if active.has(quest_id):
		active[quest_id].progress = int(active[quest_id].get("progress", 0)) + amount

func complete(quest_id: String) -> Dictionary:
	if not active.has(quest_id):
		return {"ok": false, "message": "没有进行中的任务"}
	var definition: Dictionary = DataRegistry.get_quest(quest_id)
	var reward: Dictionary = definition.get("reward", {})
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	for key in ["experience", "potential"]:
		vitals[key] = int(vitals.get(key, 0)) + int(reward.get(key, 0))
	GameState.profile.vitals = vitals
	vitals.money = int(vitals.get("money", 0)) + int(reward.get("money", 0))
	GameState.profile.vitals = vitals
	completed[quest_id] = true
	active.erase(quest_id)
	return {"ok": true, "message": "任务完成：%s" % definition.get("title", quest_id), "reward": reward}

func list_active() -> Array:
	return active.keys()

func can_interact(npc_id: String) -> bool:
	if not _active_for_npc(npc_id).is_empty():
		return true
	if str(DataRegistry.get_quest("novice_darkxue_project").get("giverNpcId", "")) == npc_id:
		return true
	for generator_id in DataRegistry.quest_generators:
		if str(DataRegistry.quest_generators[generator_id].get("giverNpcId", "")) == npc_id:
			return true
	return false

func on_talk(npc_id: String) -> String:
	return interact_npc(npc_id)

func reset_runtime() -> void:
	for runtime_id in active:
		var runtime: Dictionary = active[runtime_id]
		var target = runtime.get("target", {})
		if target is Dictionary and str(target.get("target_id", "")).begins_with("__bounty_target_"):
			NpcSystem.unregister_runtime(str(target.get("target_id", "")))
	active.clear()
	bounty_target = {}
	cooldown_until.clear()
	ring_progress.clear()
	bounty_money_base.clear()
	bounty_stat_base.clear()

func offer_generator(generator_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	var runtime_id := "generator:" + generator_id
	if definition.is_empty():
		return {"ok": false, "message": "未知任务生成器"}
	if active.has(runtime_id) or _on_cooldown(generator_id):
		return {"ok": false, "message": "该环任务进行中"}
	var generator_type := str(definition.get("type", ""))
	var target := _placed_npc_target(str(definition.get("giverNpcId", "")))
	if generator_type in ["ring", "killRing"] and target.is_empty():
		return {"ok": false, "message": "（环任务目标池是空的，请检查地图 Interactive 层 NPC id）"}
	var runtime := {"generator_id": generator_id, "kind": generator_type, "giverNpcId": definition.get("giverNpcId", ""), "state": "active", "progress": 0, "round": 1}
	if generator_type == "errand":
		var candidates: Array[Dictionary] = []
		var pool: Dictionary = definition.get("pool", {})
		for item_id in pool.get("items", []):
			candidates.append({"target_id": str(item_id), "target_name": DataRegistry.get_item(str(item_id)).get("name", item_id), "target_kind": "item"})
		for npc_id in pool.get("npcs", []):
			var npc: Dictionary = DataRegistry.get_npc(str(npc_id))
			candidates.append({"target_id": str(npc_id), "target_name": npc.get("displayName", npc_id), "target_kind": "npc"})
		if candidates.is_empty():
			return {"ok": false, "message": "（差事池是空的，先在 quests.json 配置）"}
		runtime.target = candidates[randi() % candidates.size()]
		runtime.met_goal = false
	elif generator_type == "bounty":
		var enemies: Array = definition.get("enemyPool", [])
		if enemies.is_empty():
			return {"ok": false, "message": "（悬赏池是空的，先在 quests.json 配置）"}
		var enemy_id := str(enemies[randi() % enemies.size()])
		var enemy: Dictionary = DataRegistry.get_npc(enemy_id)
		var prefixes: Array = definition.get("enemyTemplate", {}).get("namePrefix", [])
		var prefix := str(prefixes[randi() % prefixes.size()]) if not prefixes.is_empty() else ""
		var maps: Array = definition.get("spawnMaps", [])
		runtime.target = {"target_id": enemy_id, "target_name": prefix + str(enemy.get("displayName", enemy_id)), "target_kind": "npc", "map_id": str(maps[randi() % maps.size()]) if not maps.is_empty() else ""}
		runtime.ready = false
	if str(definition.get("type", "")) in ["ring", "killRing"] and not target.is_empty():
		var target_npc: Dictionary = DataRegistry.get_npc(target.get("npc_id", ""))
		runtime.target = {"target_id": target.get("npc_id", ""), "target_name": target_npc.get("display_name", target_npc.get("displayName", target.get("npc_id", ""))), "map_id": target.get("map_id", ""), "map_name": target.get("map_name", target.get("map_id", ""))}
	if str(definition.get("type", "")) == "ring":
		var items: Array = definition.get("items", [])
		if not items.is_empty() and randf() < float(definition.get("itemChance", 0.5)):
			var item_id := str(items[randi() % items.size()])
			runtime.item_id = item_id
			runtime.item_name = DataRegistry.get_item(item_id).get("name", item_id)
	if str(definition.get("type", "")) == "killRing":
		runtime.reward = _kill_ring_reward(definition, str(runtime.get("target", {}).get("target_id", "")))
	else:
		runtime.reward = _base_reward(definition)
		if str(definition.get("type", "")) == "ring" and not str(runtime.get("item_id", "")).is_empty():
			runtime.reward.money = int(runtime.reward.get("money", 0)) + int(definition.get("itemExtraMoney", 0))
	active[runtime_id] = runtime
	var target_data: Dictionary = runtime.get("target", {})
	var line_key := "offerItem" if not str(runtime.get("item_id", "")).is_empty() else "offer"
	return {"ok": true, "message": _line(definition, line_key, "已接取：{target}", {"target": target_data.get("target_name", ""), "map": target_data.get("map_name", target_data.get("map_id", "")), "item": runtime.get("item_name", ""), "count": int(ring_progress.get(generator_id, 0)) % maxi(1, int(definition.get("ringSize", 1))) + 1, "ringSize": int(definition.get("ringSize", 1))})}

func _deliver_standard(runtime_id: String, runtime: Dictionary, definition: Dictionary) -> String:
	var target: Dictionary = runtime.get("target", {}) if runtime.get("target", {}) is Dictionary else {}
	var kind := str(runtime.get("kind", ""))
	if kind == "errand":
		if str(target.get("target_kind", "")) == "item":
			var item_id := str(target.get("target_id", ""))
			if InventorySystem.count(item_id) < 1:
				return _line(definition, "inProgress", "快去把【{target}】带回来。", {"target": target.get("target_name", item_id)})
			InventorySystem.remove_item(item_id, 1)
		elif not bool(runtime.get("met_goal", false)):
			return _line(definition, "inProgress", "你还没见到【{target}】，快去。", {"target": target.get("target_name", "")})
	elif kind == "bounty" and not bool(runtime.get("ready", false)):
		return _line(definition, "inProgress", "【{target}】还没伏法。", {"target": target.get("target_name", ""), "map": target.get("map_id", "")})
	var reward: Dictionary = runtime.get("reward", _base_reward(definition))
	_grant_reward(reward)
	active.erase(runtime_id)
	cooldown_until[str(runtime.get("generator_id", ""))] = GameState.game_time_sec + float(definition.get("cooldownSec", 300))
	return _line(definition, "done", "办得好！{reward}", {"target": target.get("target_name", ""), "reward": _format_reward(reward)})

func _base_reward(definition: Dictionary) -> Dictionary:
	var explicit: Dictionary = definition.get("reward", {})
	if not explicit.is_empty():
		return explicit.duplicate(true)
	var base := int(definition.get("rewardBase", 0))
	if base > 0:
		return {"experience": base * 2, "potential": base * 2, "money": int(round(float(base) * 1.6))}
	return {}

func _kill_ring_reward(definition: Dictionary, target_id: String) -> Dictionary:
	var target: Dictionary = DataRegistry.get_npc(target_id)
	var attributes: Dictionary = target.get("attributes", {})
	var skills: Dictionary = target.get("skillLevels", {})
	var attribute_score := 0.0
	for key in ["strength", "agility", "constitution", "wisdom"]:
		attribute_score += float(attributes.get(key, 1))
	var skill_score := 0.0
	for skill_id in skills:
		skill_score += float(skills[skill_id])
	var average_skill := skill_score / float(maxi(1, skills.size()))
	var raw := (attribute_score * 1.5 + average_skill * 4.0) * float(definition.get("rewardPotentialScale", 1.0))
	var potential := clampi(int(round(raw)), int(definition.get("rewardPotentialMin", 0)), int(definition.get("rewardPotentialMax", 999999)))
	return {"experience": potential, "potential": potential, "money": int(ceil(float(potential) * 0.8))}

func _scaled_reward(definition: Dictionary, reward: Dictionary, round_index: int) -> Dictionary:
	var result := reward.duplicate(true)
	var growth := 0.0
	if definition.has("ringGrowth"):
		growth = pow(1.0 + float(definition.get("ringGrowth", 0.0)), maxi(0, round_index - 1))
	elif definition.has("rewardGrowthMin"):
		growth = pow(1.0 + randf_range(float(definition.get("rewardGrowthMin", 0.0)), float(definition.get("rewardGrowthMax", 0.0))), maxi(0, round_index - 1))
	else:
		growth = 1.0
	var fluctuation_min := -float(definition.get("fluctuation", 0.0))
	var fluctuation_max := float(definition.get("fluctuation", 0.0))
	if definition.has("fluctuationMin"):
		fluctuation_min = float(definition.get("fluctuationMin", 0.0))
		fluctuation_max = float(definition.get("fluctuationMax", 0.0))
	var fluctuation := 1.0 + randf_range(fluctuation_min, fluctuation_max)
	for key in result:
		if result[key] is int or result[key] is float:
			result[key] = maxi(0, int(round(float(result[key]) * growth * fluctuation)))
	return result

func advance_generator(generator_id: String, amount: int = 1) -> Dictionary:
	var runtime_id := "generator:" + generator_id
	if not active.has(runtime_id):
		return {"ok": false, "message": "没有进行中的环任务"}
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	var runtime: Dictionary = active[runtime_id]
	var target_data: Dictionary = runtime.get("target", {}) if runtime.get("target", {}) is Dictionary else {}
	if str(definition.get("type", "")) == "ring" and not str(runtime.get("item_id", "")).is_empty():
		var item_id := str(runtime.get("item_id", ""))
		if InventorySystem.count(item_id) < 1:
			return {"ok": false, "message": _line(definition, "needItem", "【{item}】不在你身上，可交不了差。", {"item": runtime.get("item_name", item_id)})}
		if not InventorySystem.equipped_slot(item_id).is_empty():
			return {"ok": false, "message": _line(definition, "itemEquipped", "先卸下【{item}】再交付。", {"item": runtime.get("item_name", item_id)})}
		InventorySystem.remove_item(item_id, 1)
	runtime.progress = int(ring_progress.get(generator_id, runtime.get("progress", 0))) + maxi(0, amount)
	var ring_size := maxi(1, int(definition.get("ringSize", 1)))
	var reward_round := int(floor(float(int(runtime.progress) - 1) / float(ring_size))) + 1
	var round_index := reward_round
	var reward: Dictionary = _scaled_reward(definition, runtime.get("reward", _base_reward(definition)), round_index)
	_grant_reward(reward)
	ring_progress[generator_id] = int(runtime.progress)
	active.erase(runtime_id)
	cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 30))
	return {"ok": true, "complete": int(runtime.progress) % ring_size == 0, "progress": runtime.progress, "required": ring_size, "reward": reward, "target": target_data}

## 环任务推进后的展示文案：talk_key 按触发场景传入实际使用的 lines key（谈话用 targetTalk，击杀用 done），
## 环满时追加 ringDone 彩蛋文案。
func _generator_advance_message(definition: Dictionary, advanced: Dictionary, talk_key: String, fallback: String) -> String:
	var target_data: Dictionary = advanced.get("target", {})
	var message := _line(definition, talk_key, fallback, {"target": target_data.get("target_name", ""), "map": target_data.get("map_id", ""), "reward": _format_reward(advanced.get("reward", {}))})
	if bool(advanced.get("complete", false)):
		var ring_done_line := _line(definition, "ringDone", "", {"ringSize": int(definition.get("ringSize", 1))})
		if not ring_done_line.is_empty():
			message += "\n" + ring_done_line
	return message

func abandon(quest_id: String) -> void:
	active.erase(quest_id)

func abandon_active() -> Dictionary:
	if active.is_empty():
		return {"ok": false, "message": "你没有在办的差事。"}
	var runtime_id := str(active.keys()[0])
	var runtime: Dictionary = active[runtime_id]
	var generator_id := str(runtime.get("generator_id", ""))
	var name := ""
	var ring_reset := false
	if runtime_id == "novice_darkxue_project":
		name = str(runtime.get("target", "项目"))
		cooldown_until[runtime_id] = GameState.game_time_sec + float(DataRegistry.get_quest(runtime_id).get("cooldownSec", 30))
	elif runtime_id.begins_with("generator:"):
		var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
		var kind := str(definition.get("type", ""))
		var target_data: Dictionary = runtime.get("target", {}) if runtime.get("target", {}) is Dictionary else {}
		name = str(target_data.get("target_name", definition.get("title", generator_id)))
		if kind == "ring":
			ring_reset = true
		if kind == "ring":
			ring_progress[generator_id] = 0
		elif kind in ["bounty", "errand"]:
			cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 30))
		if str(target_data.get("target_id", "")).begins_with("__bounty_target_"):
			NpcSystem.unregister_runtime(str(target_data.get("target_id", "")))
			bounty_target = {}
	active.erase(runtime_id)
	var suffix := "，这一环的计数从头再来。" if ring_reset else "。"
	return {"ok": true, "message": "你放弃了差事（%s）%s" % [name, suffix]}

func offer_bounty(generator_id: String = "bountyring_xiaobuer") -> Dictionary:
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	var runtime_id := "generator:" + generator_id
	if definition.is_empty() or active.has(runtime_id) or _on_cooldown(generator_id):
		return {"ok": false, "message": "悬赏暂不可接取"}
	bounty_sequence += 1
	var target_id := "__bounty_target_%d" % bounty_sequence
	var spawn_maps: Array = definition.get("spawnMaps", [])
	if spawn_maps.is_empty():
		return {"ok": false, "message": "（悬赏池是空的，先在 quests.json 配置）"}
	var target_map := str(spawn_maps[randi() % spawn_maps.size()])
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var player_skills: Dictionary = GameState.profile.get("skills", {}).get("levels", {})
	var kill_index := int(ring_progress.get(generator_id, 0))
	var target_scale := maxf(0.05, 1.0 - float(definition.get("baseDiscount", 0.0)) + float(definition.get("roundGrowth", 0.0)) * kill_index)
	var scaled_attributes: Dictionary = {}
	for key in player_attributes:
		scaled_attributes[key] = maxi(1, int(round(float(player_attributes[key]) * target_scale)))
	var scaled_skills: Dictionary = {}
	for skill_id in BASIC_SKILL_KEYS:
		scaled_skills[skill_id] = maxi(1, int(round(float(player_skills.get(skill_id, 1)) * target_scale)))
	var target_name: String = str(BOUNTY_NAME_MODIFIERS.pick_random()) + str(BOUNTY_NAME_ROLES.pick_random()) + str(BOUNTY_NAME_SURNAMES.pick_random()) + str(BOUNTY_NAME_GIVEN.pick_random())
	var target_sprite := str(definition.get("targetSprite", "npc-30")).strip_edges()
	if target_sprite.is_empty():
		target_sprite = "npc-30"
	NpcSystem.register_runtime(target_id, {"displayName": target_name, "sprite": target_sprite, "roles": ["civilian"], "description": "小不二悬赏缉拿的对象，据说与你有些渊源。", "defaultLine": "你……找我有事？", "attributes": scaled_attributes, "skillLevels": scaled_skills, "equippedSkillIds": BASIC_SKILL_KEYS.duplicate()})
	bounty_target = {"target_id": target_id, "target_name": target_name, "target_sprite": target_sprite, "map_id": target_map, "map_name": DataRegistry.region_display_name(target_map), "generator_id": generator_id}
	if not bounty_money_base.has(generator_id):
		bounty_money_base[generator_id] = float(definition.get("rewardBase", 0))
	if not bounty_stat_base.has(generator_id):
		bounty_stat_base[generator_id] = float(definition.get("rewardBase", 0))
	active[runtime_id] = {"generator_id": generator_id, "kind": "bountyRing", "giverNpcId": definition.get("giverNpcId", ""), "state": "active", "progress": 0, "round": kill_index + 1, "target": bounty_target}
	return {"ok": true, "message": _line(definition, "offer", "悬赏目标：{target}（{map}）", {"target": bounty_target.target_name, "map": bounty_target.map_name}), "target": bounty_target}

func get_bounty_target() -> Dictionary:
	return bounty_target

func set_bounty_target_tile(tile: Vector2i) -> void:
	if bounty_target.is_empty():
		return
	bounty_target["tile"] = tile
	for runtime_id in active:
		var runtime: Dictionary = active[runtime_id]
		if str(runtime.get("generator_id", "")) == str(bounty_target.get("generator_id", "")):
			runtime["target"] = bounty_target

func bounty_board_text(generator_id: String = "bountyring_xiaobuer") -> String:
	if bounty_target.is_empty():
		return "暗网悬赏榜暂时空着，去找小不二接一单吧。"
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	return _line(definition, "inProgress", "「{target}」已在「{map}」，请速速将其捉拿归案！", {"target": bounty_target.get("target_name", ""), "map": bounty_target.get("map_name", bounty_target.get("map_id", ""))})

func get_active_target() -> Dictionary:
	for runtime_id in active:
		var target = active[runtime_id].get("target", {})
		if target is Dictionary and not str(target.get("target_id", "")).is_empty():
			return target
	return {}

func clear_bounty_target() -> void:
	if not bounty_target.is_empty():
		NpcSystem.unregister_runtime(str(bounty_target.get("target_id", "")))
	bounty_target = {}

func _settle_bounty_ring(runtime_id: String, runtime: Dictionary, definition: Dictionary) -> Dictionary:
	var generator_id := str(runtime.get("generator_id", ""))
	var money_base := float(bounty_money_base.get(generator_id, definition.get("rewardBase", 0)))
	var stat_base := float(bounty_stat_base.get(generator_id, definition.get("rewardBase", 0)))
	var fluctuation_min := float(definition.get("fluctuationMin", 0.0))
	var fluctuation_max := maxf(fluctuation_min, float(definition.get("fluctuationMax", fluctuation_min)))
	var roll := func(base: float) -> int:
		return maxi(0, int(floor(base * (1.0 + randf_range(fluctuation_min, fluctuation_max)))))
	var reward := {
		"experience": roll.call(stat_base * 2.0),
		"potential": roll.call(stat_base * 2.0),
		"money": roll.call(money_base * 1.6),
	}
	_grant_reward(reward)
	var kills_done := int(ring_progress.get(generator_id, 0)) + 1
	var ring_size := maxi(1, int(definition.get("ringSize", 1)))
	var ring_done := kills_done >= ring_size
	if ring_done:
		ring_progress[generator_id] = 0
		bounty_money_base[generator_id] = float(definition.get("rewardBase", 0))
		bounty_stat_base[generator_id] = float(definition.get("rewardBase", 0))
	else:
		ring_progress[generator_id] = kills_done
		bounty_money_base[generator_id] = money_base * (1.0 + randf_range(float(definition.get("rewardGrowthMin", 0.0)), float(definition.get("rewardGrowthMax", 0.0))))
		bounty_stat_base[generator_id] = stat_base * (1.0 + randf_range(float(definition.get("statGrowthMin", definition.get("rewardGrowthMin", 0.0))), float(definition.get("statGrowthMax", definition.get("rewardGrowthMax", 0.0)))))
	active.erase(runtime_id)
	cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 0))
	return {"reward": reward, "complete": ring_done, "target": runtime.get("target", {})}

func _settle_kill_ring(runtime_id: String, runtime: Dictionary, definition: Dictionary) -> Dictionary:
	var generator_id := str(runtime.get("generator_id", ""))
	var reward: Dictionary = runtime.get("reward", {})
	_grant_reward(reward)
	var kills_done := int(ring_progress.get(generator_id, 0)) + 1
	var ring_size := maxi(1, int(definition.get("ringSize", 1)))
	var ring_done := kills_done >= ring_size
	ring_progress[generator_id] = 0 if ring_done else kills_done
	active.erase(runtime_id)
	cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 0))
	return {"reward": reward, "complete": ring_done, "target": runtime.get("target", {})}

func on_enemy_defeated(enemy_id: String) -> String:
	for runtime_id in active.keys():
		var runtime: Dictionary = active[runtime_id]
		var target_value = runtime.get("target", {})
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		if str(target.get("target_id", "")) != enemy_id:
			continue
		var generator_id := str(runtime.get("generator_id", ""))
		var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
		var kind := str(definition.get("type", ""))
		var result: Dictionary
		if kind == "bounty":
			runtime.ready = true
			return ""
		elif kind == "bountyRing":
			result = _settle_bounty_ring(str(runtime_id), runtime, definition)
			clear_bounty_target()
		elif kind == "killRing":
			result = _settle_kill_ring(str(runtime_id), runtime, definition)
		else:
			result = advance_generator(generator_id, 1)
		if not bool(result.get("ok", false)):
			# 专用环结算以存在 reward 表示成功；通用推进仍使用 ok。
			if not result.has("reward"):
				return str(result.get("message", "任务进度推进"))
		return _generator_advance_message(definition, result, "done", "已击败{target}，获得{reward}")
	return ""
