extends Node

const BOUNTY_CONTROLLER := preload("res://scripts/quests/bounty_controller.gd")
const QUEST_REWARDS := preload("res://scripts/quests/quest_rewards.gd")
const QUEST_GENERATOR := preload("res://scripts/quests/quest_generator.gd")
const COMBAT_RULES := preload("res://scripts/combat/combat_rules.gd")

## 承担交易/典当/授业职能的人物不进入生死任务目标池；未成年人物一律排除。
const KILL_QUEST_EXCLUDED_ROLES := ["vendor", "pawn", "master"]
const KILL_QUEST_MIN_AGE := 18
## 击杀类任务种类：只互斥追杀目标并响应击败事件；其余种类占用交付端点。
const KILL_QUEST_KINDS := ["bounty", "bountyRing", "killRing"]

## 活动任务以固定 quest_id 或 generator:<generator_id> 为键；不同键可并行，
## 相同键不可重复。该字典与其他任务进度都只存在于本局会话。
var active: Dictionary = {}
var bounty_target: Dictionary = {}
var cooldown_until: Dictionary = {}
var ring_progress: Dictionary = {}
var bounty_money_base: Dictionary = {}
var bounty_stat_base: Dictionary = {}
var bounty_sequence := 0

@onready var bounty := BOUNTY_CONTROLLER.new(self)
@onready var rewards := QUEST_REWARDS.new(self)
@onready var generator := QUEST_GENERATOR.new(self)

## 读取任务文案模板并替换全部花括号变量。
func _line(definition: Dictionary, key: String, fallback: String, values: Dictionary = {}) -> String:
	var result := str(definition.get("lines", {}).get(key, fallback))
	for name in values:
		result = result.replace("{" + str(name) + "}", str(values[name]))
	return result

## 把经验、潜能和 Token 奖励格式化为统一短文本。
func _format_reward(reward: Dictionary) -> String:
	return "（经验+%d 潜能+%d Token+%d）" % [int(reward.get("experience", 0)), int(reward.get("potential", 0)), int(reward.get("money", 0))]

## 判断任务生成器是否仍处于游戏时钟冷却期。
func _on_cooldown(generator_id: String) -> bool:
	return GameState.game_time_sec < float(cooldown_until.get(generator_id, 0.0))

## giverNpcId 是接任务的 NPC，completion_giver_id 是交任务的 NPC——多数任务两者
## 是同一人，但需要分别前往发布点与交付点的新手项目两者不同。
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

## 将任务奖励安全累加到角色生命资源。
func _grant_reward(reward: Dictionary) -> void:
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	for key in ["experience", "potential", "money"]:
		vitals[key] = int(vitals.get(key, 0)) + int(reward.get(key, 0))
	GameState.profile.vitals = vitals

func _append_reserved_npc_id(ids: Array[String], value: Variant) -> void:
	var npc_id := str(value)
	if not npc_id.is_empty() and not ids.has(npc_id):
		ids.append(npc_id)

## 汇总当前活动任务真正的交付端点；只用于非击杀任务，避免一次交互同时结算两项任务。
## 发布者和静态配置不做全局保留，交付人物也允许成为另一项任务的击杀目标。
func _reserved_delivery_npc_ids() -> Array[String]:
	var ids: Array[String] = []
	for definition in DataRegistry.quests.values():
		if definition is Dictionary:
			_append_reserved_npc_id(ids, definition.get("completionGiverId", definition.get("giverNpcId", "")))
	for definition in DataRegistry.quest_generators.values():
		if definition is Dictionary:
			_append_reserved_npc_id(ids, definition.get("giverNpcId", ""))
	for runtime in active.values():
		if not runtime is Dictionary:
			continue
		var kind := str(runtime.get("kind", ""))
		if runtime.has("completion_giver_id"):
			_append_reserved_npc_id(ids, runtime.get("completion_giver_id", ""))
		elif kind in ["errand", "bounty"]:
			_append_reserved_npc_id(ids, runtime.get("giverNpcId", ""))
		var target = runtime.get("target", {})
		if kind == "ring" and target is Dictionary:
			_append_reserved_npc_id(ids, target.get("target_id", ""))
	return ids

## 击杀类任务只互斥正在追杀的目标，允许命中其他任务的发布者、交付者或谈话目标。
func _active_kill_target_ids() -> Array[String]:
	var ids: Array[String] = []
	for runtime in active.values():
		if not runtime is Dictionary or str(runtime.get("kind", "")) not in KILL_QUEST_KINDS:
			continue
		var target = runtime.get("target", {})
		if target is Dictionary:
			_append_reserved_npc_id(ids, target.get("target_id", ""))
	return ids

## 从地图人物摆放池随机选取任务目标并排除指定人物。
func _placed_npc_target(excluded_ids: Array = [], combat_only: bool = false) -> Dictionary:
	var excluded: Array = excluded_ids.duplicate()
	var candidates: Array[Dictionary] = DataRegistry.list_placed_npc_targets(excluded)
	if combat_only:
		candidates = candidates.filter(func(target): return _is_kill_quest_target(str(target.get("npc_id", ""))))
	return candidates[randi() % candidates.size()] if not candidates.is_empty() else {}

## 生死类随机目标共享同一资格检查，地图池和显式 enemyPool 不得出现两套规则。
func _is_kill_quest_target(npc_id: String) -> bool:
	var npc: Dictionary = DataRegistry.get_npc(npc_id)
	var roles: Array = npc.get("roles", [])
	return not npc.is_empty() \
		and str(npc.get("combatRank", COMBAT_RULES.DEFAULT_COMBAT_RANK)) != COMBAT_RULES.RANK_NONCOMBATANT \
		and int(npc.get("age", KILL_QUEST_MIN_AGE)) >= KILL_QUEST_MIN_AGE \
		and not roles.any(func(role): return str(role) in KILL_QUEST_EXCLUDED_ROLES) \
		and bool(npc.get("targetableByKillQuest", true))

## 三类任务对话分支，按顺序尝试：1) 固定新手项目
## （独立状态机，不走通用生成器）；2) DataRegistry.quest_generators 驱动的通用
## 环任务/差事/悬赏；3) 已在跑的送信类任务只记录“已交谈”，不接管对话。
func interact_npc(npc_id: String) -> String:
	var novice: Dictionary = DataRegistry.get_quest("b7ce37d7-b841-5a71-ac4b-24c8a491967b")
	var novice_id := "b7ce37d7-b841-5a71-ac4b-24c8a491967b"
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
		active[novice_id] = {"state": "active", "progress": 0, "completion_giver_id": novice.get("completionGiverId", ""), "target": variant.get("title", "项目"), "hp_cost": variant.get("hpCost", 0), "reward": rewards.novice_reward(novice, variant)}
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

## 锁定 DARK 学电脑交互并返回延迟结算所需信息。
func begin_novice_completion(endpoint_id: String) -> Dictionary:
	var novice_id := "b7ce37d7-b841-5a71-ac4b-24c8a491967b"
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

## 在工作演出结束后扣除体力、发放奖励并进入冷却。
func finish_novice_completion(endpoint_id: String) -> String:
	var novice_id := "b7ce37d7-b841-5a71-ac4b-24c8a491967b"
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

## 完成指定固定任务并发放其配置奖励。
func complete(quest_id: String) -> Dictionary:
	if not active.has(quest_id):
		return {"ok": false, "message": "没有进行中的任务"}
	var definition: Dictionary = DataRegistry.get_quest(quest_id)
	var reward: Dictionary = definition.get("reward", {})
	_grant_reward(reward)
	active.erase(quest_id)
	return {"ok": true, "message": "任务完成：%s" % definition.get("title", quest_id), "reward": reward}

## 判断人物是否是当前任务的发布、交付或目标端点。
func can_interact(npc_id: String) -> bool:
	if not _active_for_npc(npc_id).is_empty():
		return true
	if str(DataRegistry.get_quest("b7ce37d7-b841-5a71-ac4b-24c8a491967b").get("giverNpcId", "")) == npc_id:
		return true
	for generator_id in DataRegistry.quest_generators:
		if str(DataRegistry.quest_generators[generator_id].get("giverNpcId", "")) == npc_id:
			return true
	return false

## 注销动态人物并清空仅属于本局会话的任务状态。
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

## 按 quests.json 中的 generator_type（errand/bounty/ring/killRing）分流构建
## runtime.target 的形状；各类型字段结构不同，读取时须按 kind 区分处理。
func offer_generator(generator_id: String) -> Dictionary:
	return generator.offer(generator_id)

## 验证并交付普通差事或普通悬赏。
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

## 返回任务配置的通用基础奖励。
func _base_reward(definition: Dictionary) -> Dictionary:
	return rewards.base_reward(definition)

## 按击杀目标强度计算生死簿奖励。
func _kill_ring_reward(definition: Dictionary, target_id: String) -> Dictionary:
	return rewards.kill_ring_reward(definition, target_id)

## 两种增长配置二选一（ringGrowth 优先）：固定倍率 ringGrowth 用于环任务的
## 确定性递增；随机区间 rewardGrowthMin/Max 用于悬赏环的浮动式递增，二者互斥。
func _scaled_reward(definition: Dictionary, reward: Dictionary, round_index: int) -> Dictionary:
	return rewards.scaled_reward(definition, reward, round_index)

## 推进通用环任务并完成物品交付与奖励结算。
func advance_generator(generator_id: String, amount: int = 1) -> Dictionary:
	return generator.advance(generator_id, amount)

## 环任务推进后的展示文案：talk_key 按触发场景传入实际使用的 lines key（谈话用 targetTalk，击杀用 done），
## 环满时追加 ringDone 彩蛋文案。
func _generator_advance_message(definition: Dictionary, advanced: Dictionary, talk_key: String, fallback: String) -> String:
	return generator.advance_message(definition, advanced, talk_key, fallback)

## 悬赏目标的属性/功法按玩家当前面板动态缩放（target_scale），并随连续
## 击杀轮次（kill_index）走高——悬赏难度始终围绕玩家实力浮动，而非固定强度。
func offer_bounty(generator_id: String = "c7666a34-f17b-5427-875a-74f227071fa2") -> Dictionary:
	return bounty.offer(generator_id)

## 返回当前动态悬赏人物及地图信息。
func get_bounty_target() -> Dictionary:
	return bounty_target

## 记录动态悬赏人物最终选择的安全地图格。
func set_bounty_target_tile(tile: Vector2i) -> void:
	bounty.set_target_tile(tile)

## 返回暗网悬赏榜当前展示文案。
func bounty_board_text(generator_id: String = "c7666a34-f17b-5427-875a-74f227071fa2") -> String:
	return bounty.board_text(generator_id)

## 注销并清空当前动态悬赏人物。
func clear_bounty_target() -> void:
	bounty.clear_target()

## 悬赏环奖励基数按初始值线性增长；击杀环奖励在生成时一次性计算，结算时按原值发放。
func _settle_bounty_ring(runtime_id: String, runtime: Dictionary, definition: Dictionary) -> Dictionary:
	return bounty.settle_ring(runtime_id, runtime, definition)

## 发放一次击杀环奖励并更新环进度。
func _settle_kill_ring(runtime_id: String, runtime: Dictionary, definition: Dictionary) -> Dictionary:
	return rewards.settle_kill_ring(runtime_id, runtime, definition)

## 结构化返回任务是否接管本次击杀，奖励互斥不依赖可为空的展示文案。
func handle_enemy_defeated(enemy_id: String) -> Dictionary:
	for runtime_id in active.keys():
		var runtime: Dictionary = active[runtime_id]
		var generator_id := str(runtime.get("generator_id", ""))
		var definition: Dictionary = DataRegistry.quest_generators.get(generator_id, {})
		var kind := str(definition.get("type", runtime.get("kind", "")))
		if kind not in KILL_QUEST_KINDS:
			continue
		var target_value = runtime.get("target", {})
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		if str(target.get("target_id", "")) != enemy_id:
			continue
		var result: Dictionary
		if kind == "bounty":
			# 普通悬赏（非环）只标记击杀完成，实际发奖延后到玩家回去交付
			# （见 _deliver_standard）；handled 标记确保空文案也不会叠加野战奖励。
			runtime.ready = true
			return {"handled": true, "message": _line(definition, "ready", "【{target}】已经伏法，回去交差。", {"target": target.get("target_name", enemy_id)})}
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
				return {"handled": true, "message": str(result.get("message", "任务进度推进"))}
		return {"handled": true, "message": _generator_advance_message(definition, result, "done", "已击败{target}，获得{reward}")}
	return {"handled": false, "message": ""}

## 兼容只需要展示文本的既有调用；战斗结算必须使用 handle_enemy_defeated。
func on_enemy_defeated(enemy_id: String) -> String:
	return str(handle_enemy_defeated(enemy_id).get("message", ""))
