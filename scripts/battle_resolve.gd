extends Node

const DEFEAT_LOSS_RATE_MIN := 0.05
const DEFEAT_LOSS_RATE_MAX := 0.15

func resolve_victory(session: Dictionary, lethal: bool = true) -> String:
	var enemy_id := str(session.get("enemy_id", ""))
	var enemy: Dictionary = session.get("enemy", {})
	if lethal:
		_apply_lethal_wounds(session)
	var lines: Array[String] = []
	if not lethal:
		return "切磋结束：你在交流中获益，双方均未受致命伤。"
	# 任务结算与普通 Token 奖励互斥：若此敌人与某个进行中任务挂钩，奖励走任务
	# 的 reward 表（金额已按任务配置好），不再叠加按战力估算的野战 Token。
	var quest_line := QuestSystem.on_enemy_defeated(enemy_id)
	if not quest_line.is_empty():
		lines.append(quest_line)
	else:
		var money := int(enemy.get("money", 0))
		if money <= 0:
			money = maxi(0, int(ceil(_rating(enemy) / 3.0)))
		var vitals: Dictionary = GameState.profile.get("vitals", {})
		vitals.money = int(vitals.get("money", 0)) + money
		GameState.profile.vitals = vitals
		lines.append("击败强敌，获得 %d Token" % money)
	var drops := NpcSystem.get_drop_items(enemy_id)
	var gained: Array[String] = []
	for item_id in drops:
		if InventorySystem.add_item(item_id):
			gained.append(str(DataRegistry.get_item(item_id).get("name", item_id)))
	if not gained.is_empty():
		lines.append("拾获：%s" % "、".join(gained))
	NpcSystem.mark_defeated(enemy_id)
	return "\n".join(lines)

## 战败惩罚：除资源损失外，每门已学功法各有 50% 概率倒退 0~2 级
## （基础/文识功法保底 1 级、门派功法可退到 0 级），用于放大战败代价。
## 切磋（lethal=false）落败不结算伤势/惩罚，与 resolve_victory/resolve_flee 的 lethal 分支保持一致。
func resolve_defeat(session: Dictionary, lethal: bool = true) -> String:
	if not lethal:
		return "切磋落败，受益匪浅。"
	_apply_lethal_wounds(session)
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var money_loss := int(floor(float(vitals.get("money", 0)) * randf_range(DEFEAT_LOSS_RATE_MIN, DEFEAT_LOSS_RATE_MAX)))
	var potential_loss := int(floor(float(vitals.get("potential", 0)) * randf_range(DEFEAT_LOSS_RATE_MIN, DEFEAT_LOSS_RATE_MAX)))
	var experience_loss := int(floor(float(vitals.get("experience", 0)) * randf_range(0.10, 0.20)))
	vitals.money = maxi(0, int(vitals.get("money", 0)) - money_loss)
	vitals.potential = maxi(0, int(vitals.get("potential", 0)) - potential_loss)
	vitals.experience = maxi(0, int(vitals.get("experience", 0)) - experience_loss)
	var skill_loss := 0
	var levels: Dictionary = GameState.profile.get("skills", {}).get("levels", {})
	for skill_id in levels.keys():
		var current := int(levels[skill_id])
		if randf() < 0.5:
			var floor_level := 1 if str(skill_id).begins_with("basic") or str(skill_id) == "literacy" else 0
			var next := maxi(floor_level, current - randi_range(0, 2))
			if next < current:
				levels[skill_id] = next
				skill_loss += 1
	GameState.profile.vitals = vitals
	GameState.profile.skills.levels = levels
	GameState.combat_state.hp = _effective_hp_max()
	# 对齐参考项目 BattleHud.ts：其余战斗结算只改内存，等下次自动/手动保存才落盘；
	# 死亡惩罚是不可逆的永久性损失，这里立即存档，避免玩家靠不存档规避惩罚。
	GameState.save_game()
	var suffix := "，%d 门功法生疏" % skill_loss if skill_loss > 0 else ""
	return "你重伤昏迷，醒来损失 Token %d、潜能 %d、经验 %d%s" % [money_loss, potential_loss, experience_loss, suffix]

func resolve_flee(session: Dictionary, lethal: bool = true) -> String:
	if not lethal:
		return "你收招退了下来。"
	_apply_lethal_wounds(session)
	return "你脱身遁走。" + (" 你在这场恶战中破了相。" if session.get("disfigurement", false) else "")

## 濒死（reached_zero）与重伤（near_death，见 combat_system._track_player_state）
## 各自独立判定“破相”：外观值永久下降，模拟战斗中留下的伤疤/损容代价。
func _apply_lethal_wounds(session: Dictionary) -> void:
	var damage_taken := maxi(0, int(session.get("initial_player_hp", GameState.combat_state.hp)) - int(GameState.combat_state.hp))
	var reduce := SkillSystem.injury_reduce()
	GameState.combat_state.injury = maxi(0, int(GameState.combat_state.injury) + int(ceil(damage_taken * 0.2 * (1.0 - reduce))))
	var appearance_drops := 0
	if bool(session.get("player_reached_zero", false)) and randf() < 0.30:
		appearance_drops += 1
	if bool(session.get("player_near_death", false)) and randf() < 0.15:
		appearance_drops += 1
	if appearance_drops > 0:
		var vitals: Dictionary = GameState.profile.get("vitals", {})
		vitals.appearance = maxi(0, int(vitals.get("appearance", 0)) - appearance_drops * 20)
		GameState.profile.vitals = vitals
		session.disfigurement = true
	GameState.combat_state.hp = mini(_effective_hp_max(), int(GameState.combat_state.hp))

func _effective_hp_max() -> int:
	return GameState.player_effective_hp_max()

## 综合技能等级 = max(加权总和, 单科峰值)，与参考项目 SkillRating.computeRatingScore 一致：
## 基础技能按 1 倍、门派技能按 2 倍计入总和；峰值取未加权的单科最高等级。
func _rating(enemy: Dictionary) -> int:
	var levels: Dictionary = enemy.get("skillLevels", {})
	var power := 0
	var peak := 0
	for skill_id in levels:
		var lv := int(levels[skill_id])
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		var weight := 2 if str(definition.get("category", "")) == "sect" else 1
		power += lv * weight
		peak = maxi(peak, lv)
	return maxi(1, maxi(power, peak))
