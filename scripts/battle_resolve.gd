extends Node

const COMBAT_RULES := preload("res://scripts/combat/combat_rules.gd")
const DEFEAT_LOSS_RATE_MIN := 0.05
const DEFEAT_LOSS_RATE_MAX := 0.10
const DEFEAT_SKILL_LOSS_CHANCE := 0.25
## 结算伤势 = 净体力损失 × 系数，并以真实体力上限的封顶比例限制单场增量。
const LETHAL_INJURY_COEF := 0.15
const LETHAL_INJURY_CAP_RATIO := 0.20
## 濒死与重伤各自独立滚动破相概率。
const DISFIGURE_ZERO_CHANCE := 0.30
const DISFIGURE_NEAR_DEATH_CHANCE := 0.15

func resolve_victory(session: Dictionary, lethal: bool = true) -> String:
	var enemy_id := str(session.get("enemy_id", ""))
	var enemy: Dictionary = session.get("enemy", {})
	if lethal:
		_apply_lethal_wounds(session)
	var lines: Array[String] = []
	if not lethal:
		return "切磋胜出，点到为止。"
	# 任务结算与普通 Token 奖励互斥：若此敌人与某个进行中任务挂钩，奖励走任务
	# 的 reward 表（金额已按任务配置好），不再叠加按战力估算的野战 Token。
	var quest_result: Dictionary = QuestSystem.handle_enemy_defeated(enemy_id)
	var quest_line := str(quest_result.get("message", ""))
	if bool(quest_result.get("handled", false)):
		if not quest_line.is_empty():
			lines.append(quest_line)
	else:
		var reward := _combat_reward(enemy)
		var vitals: Dictionary = GameState.profile.get("vitals", {})
		for key in reward:
			vitals[key] = int(vitals.get(key, 0)) + int(reward[key])
		GameState.profile.vitals = vitals
		lines.append("强敌授首！（经验+%d 潜能+%d Token+%d）" % [reward.experience, reward.potential, reward.money])
	var drops := NpcSystem.get_drop_items(enemy_id)
	var gained: Array[String] = []
	for item_id in drops:
		if InventorySystem.add_item(item_id):
			gained.append(str(DataRegistry.get_item(item_id).get("name", item_id)))
	if not gained.is_empty():
		lines.append("拾获：%s。" % "、".join(gained))
	var disfigure_text := str(session.get("disfigurement_text", ""))
	if not disfigure_text.is_empty(): lines.append(disfigure_text)
	NpcSystem.mark_defeated(enemy_id)
	return " ".join(lines)

## 战败惩罚保留资源风险，但一场战败最多令一门功法倒退一级，避免抹去长时间成长。
## 切磋（lethal=false）落败不结算伤势/惩罚，与 resolve_victory/resolve_flee 的 lethal 分支保持一致。
func resolve_defeat(session: Dictionary, lethal: bool = true) -> String:
	if not lethal:
		return "切磋落败，受益匪浅。"
	_apply_lethal_wounds(session)
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var money_loss := int(floor(float(vitals.get("money", 0)) * randf_range(DEFEAT_LOSS_RATE_MIN, DEFEAT_LOSS_RATE_MAX)))
	var potential_loss := int(floor(float(vitals.get("potential", 0)) * randf_range(DEFEAT_LOSS_RATE_MIN, DEFEAT_LOSS_RATE_MAX)))
	var experience_loss := int(floor(float(vitals.get("experience", 0)) * randf_range(DEFEAT_LOSS_RATE_MIN, DEFEAT_LOSS_RATE_MAX)))
	vitals.money = maxi(0, int(vitals.get("money", 0)) - money_loss)
	vitals.potential = maxi(0, int(vitals.get("potential", 0)) - potential_loss)
	vitals.experience = maxi(0, int(vitals.get("experience", 0)) - experience_loss)
	var skill_loss := 0
	var levels: Dictionary = GameState.profile.get("skills", {}).get("levels", {})
	var loss_candidates: Array[String] = []
	for skill_id in levels.keys():
		var current := int(levels[skill_id])
		var floor_level := 1 if str(skill_id).begins_with("basic") or str(skill_id) == "1011d493-be02-53e2-86a2-a6a439328f84" else 0
		if current > floor_level:
			loss_candidates.append(str(skill_id))
	if not loss_candidates.is_empty() and randf() < DEFEAT_SKILL_LOSS_CHANCE:
		var lost_id: String = loss_candidates.pick_random()
		levels[lost_id] = int(levels[lost_id]) - 1
		skill_loss = 1
	GameState.profile.vitals = vitals
	GameState.profile.skills.levels = levels
	SkillSystem.refresh_derived_attributes()
	GameState.normalize_combat_state()
	GameState.combat_state.hp = _effective_hp_max()
	# 对齐参考项目 BattleHud.ts：其余战斗结算只改内存，等下次自动/手动保存才落盘；
	# 死亡惩罚是不可逆的永久性损失，这里立即存档，避免玩家靠不存档规避惩罚。
	GameState.save_game()
	var suffix := "，%d 门功夫生疏" % skill_loss if skill_loss > 0 else ""
	var result := "你重伤昏迷，醒来已失 Token %d、潜能 %d、经验 %d%s。" % [money_loss, potential_loss, experience_loss, suffix]
	var disfigure_text := str(session.get("disfigurement_text", ""))
	return result + (" " + disfigure_text if not disfigure_text.is_empty() else "")

func resolve_flee(session: Dictionary, lethal: bool = true) -> String:
	if not lethal:
		return "你收招退了下来。"
	_apply_lethal_wounds(session)
	var disfigure_text := str(session.get("disfigurement_text", ""))
	return "你脱身遁走。" + (disfigure_text if not disfigure_text.is_empty() else "")

## 濒死（reached_zero）与重伤（near_death，见 combat_system._track_player_state）
## 各自独立判定“破相”：外观值永久下降，模拟战斗中留下的伤疤/损容代价。
func _apply_lethal_wounds(session: Dictionary) -> void:
	var in_battle_injury := maxi(0, int(session.get("player_in_battle_injury", 0)))
	var net_hp_loss := maxi(0, int(session.get("initial_player_hp", GameState.combat_state.hp)) - int(GameState.combat_state.hp))
	var reduce := SkillSystem.injury_reduce()
	var injury_gain := int(ceil(float(net_hp_loss) * LETHAL_INJURY_COEF * (1.0 - reduce))) + in_battle_injury
	injury_gain = mini(injury_gain, maxi(1, int(floor(float(GameState.player_hp_max()) * LETHAL_INJURY_CAP_RATIO))))
	GameState.combat_state.injury = clampi(int(GameState.combat_state.injury) + injury_gain, 0, GameState.player_hp_max() - 1)
	var appearance_drops := 0
	if bool(session.get("player_reached_zero", false)) and randf() < DISFIGURE_ZERO_CHANCE:
		appearance_drops += 1
	if bool(session.get("player_near_death", false)) and randf() < DISFIGURE_NEAR_DEATH_CHANCE:
		appearance_drops += 1
	if appearance_drops > 0:
		var vitals: Dictionary = GameState.profile.get("vitals", {})
		vitals.appearance = maxi(0, int(vitals.get("appearance", 0)) - appearance_drops * 20)
		GameState.profile.vitals = vitals
		session.disfigurement = true
		session.disfigurement_text = "你在生死边缘挣扎，容貌大损！" if appearance_drops > 1 else "你在这场恶战中破了相。"
	GameState.combat_state.hp = mini(_effective_hp_max(), int(GameState.combat_state.hp))

func _effective_hp_max() -> int:
	return GameState.player_effective_hp_max()

## 普通战斗按武学评级与战斗阶位发放成长资源；生活财富不再等同击败掉落。
func _combat_reward(enemy: Dictionary) -> Dictionary:
	var configured: Dictionary = enemy.get("combatReward", {})
	if not configured.is_empty():
		return {
			"experience": maxi(0, int(configured.get("experience", 0))),
			"potential": maxi(0, int(configured.get("potential", 0))),
			"money": maxi(0, int(configured.get("money", 0))),
		}
	var rating := _rating(enemy)
	var rank := str(enemy.get("combatRank", COMBAT_RULES.DEFAULT_COMBAT_RANK))
	var scale := float(COMBAT_RULES.NPC_RANK_REWARD_SCALE.get(rank, COMBAT_RULES.NPC_RANK_REWARD_SCALE[COMBAT_RULES.DEFAULT_COMBAT_RANK]))
	return {
		"experience": maxi(1, int(ceil(float(rating) * COMBAT_RULES.COMBAT_REWARD_EXP_COEF * scale))),
		"potential": maxi(1, int(ceil(float(rating) * COMBAT_RULES.COMBAT_REWARD_POT_COEF * scale))),
		"money": maxi(1, int(ceil(sqrt(float(rating)) * COMBAT_RULES.COMBAT_REWARD_MONEY_COEF * scale))),
	}

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
