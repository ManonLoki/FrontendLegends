extends SceneTree
## combatRole 只改变行动选择，并通过提前一回合的战报意图给玩家反应窗口。

const ULTIMATE_NPC_ID := "c6592971-0e60-5f47-969c-2db122c7c011"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state: Node = root.get_node("GameState")
	var combat: Node = root.get_node("CombatSystem")
	state.use_test_save_path("enemy-ai-decisions")
	state.delete_save()
	state.create_profile("AI测试", {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25})

	var force_session: Dictionary = combat.create_session(ULTIMATE_NPC_ID, true)
	force_session.enemy_mp = 0
	force_session.enemy.combatRole = "striker"
	var striker_intent: Dictionary = combat.enemy_ai.choose_intent(force_session, 0.20)
	force_session.enemy.combatRole = "tank"
	var tank_attack_intent: Dictionary = combat.enemy_ai.choose_intent(force_session, 0.20)
	_assert_true(str(striker_intent.action) == "attack" and bool(striker_intent.use_force), "输出型在固定局势下应主动加力")
	_assert_true(str(tank_attack_intent.action) == "attack" and not bool(tank_attack_intent.use_force), "坦克型在相同局势下应保留精力")

	var ult_session: Dictionary = combat.create_session(ULTIMATE_NPC_ID, true)
	ult_session.enemy.combatRole = "controller"
	var controller_intent: Dictionary = combat.enemy_ai.choose_intent(ult_session, 0.50)
	ult_session.enemy.combatRole = "striker"
	var striker_at_same_roll: Dictionary = combat.enemy_ai.choose_intent(ult_session, 0.50)
	_assert_true(str(controller_intent.action) == "ultimate" and not controller_intent.get("ult", {}).is_empty(), "控制型应在可支付时优先绝招")
	_assert_true(str(striker_at_same_roll.action) == "attack", "输出型在相同随机值下应选择直接进攻，形成差异")

	var recovery_session: Dictionary = combat.create_session(ULTIMATE_NPC_ID, true)
	recovery_session.enemy.combatRole = "tank"
	recovery_session.enemy_hp = 1
	recovery_session.enemy_mp = int(recovery_session.enemy_mp_max)
	var tank_recovery: Dictionary = combat.enemy_ai.choose_intent(recovery_session, 0.50)
	recovery_session.enemy.combatRole = "striker"
	var striker_recovery: Dictionary = combat.enemy_ai.choose_intent(recovery_session, 0.50)
	_assert_true(str(tank_recovery.action) == "rest" and str(striker_recovery.action) == "attack", "低体力时坦克应恢复、输出型应继续施压")

	var telegraph_session: Dictionary = combat.create_session(ULTIMATE_NPC_ID, true)
	telegraph_session.log.clear()
	var prepared: Dictionary = combat.enemy_ai.prepare_intent(telegraph_session, 0.50)
	_assert_true(telegraph_session.enemy_intent == prepared and str(telegraph_session.log[-1]).begins_with("【预判】"), "敌方意图必须在行动前写入权威战报")
	seed(4815)
	var expected_combat_roll := randf()
	seed(4815)
	combat.enemy_ai.prepare_intent(telegraph_session)
	_assert_true(is_equal_approx(randf(), expected_combat_roll), "AI 决策随机源不得扰动命中、暴击与伤害的全局校准序列")
	state.delete_save()
	print("enemy_ai_decision_test: PASS" if failures.is_empty() else "enemy_ai_decision_test: FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
