extends Node

var active: Dictionary = {}
var completed: Dictionary = {}
var bounty_target: Dictionary = {}
var cooldown_until: Dictionary = {}
var ring_progress: Dictionary = {}
var bounty_sequence := 0

func _line(definition: Dictionary, key: String, fallback: String, values: Dictionary = {}) -> String:
	var result := str(definition.get("lines", {}).get(key, fallback))
	for name in values:
		result = result.replace("{" + str(name) + "}", str(values[name]))
	return result

func _on_cooldown(generator_id: String) -> bool:
	return GameState.game_time_sec < float(cooldown_until.get(generator_id, 0.0))

func _active_for_npc(npc_id: String) -> Dictionary:
	for runtime_id in active:
		var runtime: Dictionary = active[runtime_id]
		if str(runtime.get("giverNpcId", "")) == npc_id or str(runtime.get("completion_giver_id", "")) == npc_id:
			return runtime
		var target = runtime.get("target", {})
		if target is Dictionary and str(target.get("target_id", "")) == npc_id:
			return runtime
	return {}

func _grant_reward(reward: Dictionary) -> void:
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	for key in ["experience", "potential", "money"]:
		vitals[key] = int(vitals.get(key, 0)) + int(reward.get(key, 0))
	GameState.profile.vitals = vitals

func _placed_npc_target(exclude_id: String = "") -> Dictionary:
	var candidates: Array[Dictionary] = []
	for map_path in DataRegistry.map_files:
		var file := FileAccess.open(map_path, FileAccess.READ)
		if not file:
			continue
		var xml := file.get_as_text()
		for npc_id in DataRegistry.npcs:
			if str(npc_id) == exclude_id or not xml.contains("npcId=\"" + str(npc_id) + "\""):
				continue
			candidates.append({"npc_id": str(npc_id), "map_id": map_path.get_file().get_basename()})
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
			return _line(definition, "inProgress", "任务进行中。", {"target": active[runtime_id].get("target", {}).get("target_name", "") if active[runtime_id].get("target", {}) is Dictionary else "", "map": active[runtime_id].get("target", {}).get("map_id", "") if active[runtime_id].get("target", {}) is Dictionary else ""})
		if _on_cooldown(str(generator_id)):
			return _line(definition, "cooldown", "暂时没有新任务。")
		var requires: Dictionary = definition.get("requires", {})
		if int(GameState.profile.get("vitals", {}).get("age", 0)) < int(requires.get("minAge", 0)):
			return _line(definition, "requireFail", "你年岁尚浅，暂时接不了这项任务。")
		var generator_type := str(definition.get("type", ""))
		var offered: Dictionary = offer_bounty(str(generator_id)) if generator_type == "bountyRing" else offer_generator(str(generator_id))
		return str(offered.get("message", "任务暂不可接取"))

	var runtime := _active_for_npc(npc_id)
	if not runtime.is_empty():
		var runtime_id := str(runtime.get("generator_id", ""))
		if runtime_id.begins_with("generator:"):
			var generator_id := runtime_id.trim_prefix("generator:")
			if runtime.get("target", {}) is Dictionary and str(runtime.target.get("target_id", "")) == npc_id:
				var advanced := advance_generator(generator_id, 1)
				return "目标已完成，获得奖励：%s" % str(advanced.get("reward", {}))
			return _line(DataRegistry.quest_generators.get(generator_id, {}), "inProgress", "任务进行中。")
	return ""

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
		if target is Dictionary and str(target.get("target_id", "")).begins_with("bounty_target_"):
			NpcSystem.unregister_runtime(str(target.get("target_id", "")))
	active.clear()
	bounty_target = {}
	cooldown_until.clear()
	ring_progress.clear()

func offer_generator(generator_id: String) -> Dictionary:
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	var runtime_id := "generator:" + generator_id
	if definition.is_empty():
		return {"ok": false, "message": "未知任务生成器"}
	if active.has(runtime_id) or _on_cooldown(generator_id):
		return {"ok": false, "message": "该环任务进行中"}
	var target := _placed_npc_target(str(definition.get("giverNpcId", "")))
	var runtime := {"generator_id": generator_id, "state": "active", "progress": 0, "round": 1}
	if str(definition.get("type", "")) in ["ring", "killRing"] and not target.is_empty():
		runtime.target = {"target_id": target.get("npc_id", ""), "target_name": DataRegistry.get_npc(target.get("npc_id", "")).get("displayName", target.get("npc_id", "")), "map_id": target.get("map_id", "")}
	if str(definition.get("type", "")) == "killRing":
		runtime.reward = _kill_ring_reward(definition, str(runtime.get("target", {}).get("target_id", "")))
	else:
		runtime.reward = _base_reward(definition)
	active[runtime_id] = runtime
	var target_data: Dictionary = runtime.get("target", {})
	return {"ok": true, "message": _line(definition, "offer", "已接取：{target}", {"target": target_data.get("target_name", ""), "map": target_data.get("map_id", "")})}

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
	runtime.progress = int(ring_progress.get(generator_id, runtime.get("progress", 0))) + maxi(0, amount)
	var ring_size := maxi(1, int(definition.get("ringSize", 1)))
	if int(runtime.progress) < ring_size:
		ring_progress[generator_id] = int(runtime.progress)
		var step_reward: Dictionary = _scaled_reward(definition, runtime.get("reward", _base_reward(definition)), int(runtime.get("round", 1)))
		_grant_reward(step_reward)
		cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 30))
		active.erase(runtime_id)
		return {"ok": true, "complete": false, "progress": runtime.progress, "required": ring_size, "reward": step_reward}
	var round_index := int(runtime.get("round", 1))
	var reward: Dictionary = _scaled_reward(definition, runtime.get("reward", _base_reward(definition)), round_index)
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	for key in ["experience", "potential", "money"]:
		if reward.has(key):
			vitals[key] = int(vitals.get(key, 0)) + int(reward[key])
	GameState.profile.vitals = vitals
	runtime.progress = 0
	runtime.round = round_index + 1
	ring_progress[generator_id] = 0
	active.erase(runtime_id)
	cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 30))
	return {"ok": true, "complete": true, "progress": 0, "required": ring_size, "reward": reward}

func abandon(quest_id: String) -> void:
	active.erase(quest_id)

func abandon_active() -> Dictionary:
	if active.is_empty():
		return {"ok": false, "message": "没有进行中的任务"}
	var runtime_id := str(active.keys()[0])
	var runtime: Dictionary = active[runtime_id]
	var generator_id := str(runtime.get("generator_id", ""))
	if runtime_id == "novice_darkxue_project":
		cooldown_until[runtime_id] = GameState.game_time_sec + float(DataRegistry.get_quest(runtime_id).get("cooldownSec", 30))
	elif runtime_id.begins_with("generator:"):
		var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
		var kind := str(definition.get("type", ""))
		if kind == "ring":
			ring_progress[generator_id] = 0
		elif kind in ["bounty", "errand", "bountyRing", "killRing"]:
			cooldown_until[generator_id] = GameState.game_time_sec + float(definition.get("cooldownSec", 30))
		var target = runtime.get("target", {})
		if target is Dictionary and str(target.get("target_id", "")).begins_with("bounty_target_"):
			NpcSystem.unregister_runtime(str(target.get("target_id", "")))
			bounty_target = {}
	active.erase(runtime_id)
	return {"ok": true, "message": "已放弃任务"}

func offer_bounty(generator_id: String = "bountyring_xiaobuer") -> Dictionary:
	var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
	var runtime_id := "generator:" + generator_id
	if definition.is_empty() or active.has(runtime_id) or _on_cooldown(generator_id):
		return {"ok": false, "message": "悬赏暂不可接取"}
	bounty_sequence += 1
	var target_id := "bounty_target_%d" % bounty_sequence
	var spawn_maps: Array = definition.get("spawnMaps", [])
	var target_map := str(spawn_maps[randi() % spawn_maps.size()]) if not spawn_maps.is_empty() else "KaiyuanTown"
	var player_attributes: Dictionary = GameState.profile.get("attributes", {})
	var player_skills: Dictionary = GameState.profile.get("skills", {}).get("levels", {})
	var target_name := "悬赏目标%d" % bounty_sequence
	NpcSystem.register_runtime(target_id, {"displayName": target_name, "sprite": definition.get("targetSprite", "npc-30"), "roles": ["civilian"], "description": "小不二发布的动态悬赏目标。", "defaultLine": "你找我有事？", "attributes": player_attributes.duplicate(true), "skillLevels": player_skills.duplicate(true), "equippedSkillIds": []})
	bounty_target = {"target_id": target_id, "target_name": target_name, "map_id": target_map, "generator_id": generator_id}
	active[runtime_id] = {"generator_id": generator_id, "state": "active", "progress": 0, "round": 1, "target": bounty_target, "reward": _base_reward(definition)}
	return {"ok": true, "message": "悬赏目标：%s（%s）" % [bounty_target.target_name, target_map], "target": bounty_target}

func get_bounty_target() -> Dictionary:
	return bounty_target

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
		var result: Dictionary = advance_generator(generator_id, 1)
		clear_bounty_target()
		return "悬赏目标已击败，%s" % result.get("message", "任务进度推进")
	return ""
