extends RefCounted
## 师父学习经济回归：固定学习经验与灵感驱动的潜能、时间、Token 效率。

const BASIC_SKILL_ID := "2224675d-63f2-50e8-a2c6-064acd5c5623"
const SECT_SKILL_ID := "bcb538e2-4d6a-52ae-990d-20377e27ab64"
const MASTER_ID := "21e05288-a075-5137-85e8-a6c4c115be87"

static func run(tree: SceneTree, assert_true: Callable) -> void:
	var state: Node = tree.root.get_node("GameState")
	var skills: Node = tree.root.get_node("SkillSystem")
	var registry: Node = tree.root.get_node("DataRegistry")
	var basic: Dictionary = registry.get_skill(BASIC_SKILL_ID)
	var sect: Dictionary = registry.get_skill(SECT_SKILL_ID)
	assert_true.call(is_equal_approx(skills.LEARN_XP_PER_POTENTIAL_BASE, 10.0), "中性灵感下每点潜能应转换 10 学习经验")
	for test_case in [[basic, 1, 14], [basic, 10, 34], [basic, 40, 506], [basic, 100, 4000], [sect, 1, 14], [sect, 10, 42], [sect, 40, 750], [sect, 100, 6000]]:
		assert_true.call(skills._learning_xp_required(test_case[0], test_case[1]) == test_case[2], "固定学习经验不符：Lv.%d" % test_case[1])
	for definition in [basic, sect]:
		var previous_xp: int = skills._learning_xp_required(definition, 1)
		assert_true.call(previous_xp == 14, "所有功法第一级都应从 50 灵感单点潜能可提供的 14 学习经验起步")
		for target_level in range(2, 101):
			var current_xp: int = skills._learning_xp_required(definition, target_level)
			assert_true.call(current_xp > previous_xp, "固定学习经验每一级都必须严格增长：Lv.%d" % target_level)
			assert_true.call(current_xp % 2 == 0, "固定学习经验每一级都必须为偶数：Lv.%d" % target_level)
			previous_xp = current_xp
	assert_true.call(skills._learning_xp_per_potential(0.70) == 14 and skills._learning_xp_per_potential(1.0) == 10 and skills._learning_xp_per_potential(1.30) == 8, "高/中/低灵感每点潜能应分别转换14/10/8学习经验")
	var original_profile: Dictionary = state.profile.duplicate(true)
	var samples: Array[Dictionary] = []
	for wisdom in [0, 25, 50]:
		state.profile = original_profile.duplicate(true)
		state.profile.sect = "NG神教"
		state.profile.master = MASTER_ID
		state.profile.attributes.wisdom = wisdom
		state.profile.skills = skills.create_default_skills()
		state.profile.skills.levels[BASIC_SKILL_ID] = 9
		state.profile.vitals.potential = 1000
		state.profile.vitals.money = 1000
		var before_potential := int(state.profile.vitals.potential)
		var before_money := int(state.profile.vitals.money)
		var required := int(skills.learning_progress(BASIC_SKILL_ID).total)
		var result: Dictionary = {}
		var ticks := 0
		while not bool(result.get("ok", false)) and ticks < 100:
			result = skills.learn_tick(MASTER_ID, BASIC_SKILL_ID)
			ticks += 1
			assert_true.call(not result.has("reason"), "资源充足时学习不得意外中断")
		assert_true.call(bool(result.get("ok", false)), "10级学习应在100个时间片内完成")
		samples.append({"required": required, "ticks": ticks, "potential": before_potential - int(state.profile.vitals.potential), "token": before_money - int(state.profile.vitals.money)})
	state.profile = original_profile
	assert_true.call(samples[0].required == samples[1].required and samples[1].required == samples[2].required, "不同灵感的10级固定学习经验必须相同")
	assert_true.call(samples == [{"required": 34, "ticks": 5, "potential": 5, "token": 4}, {"required": 34, "ticks": 4, "potential": 4, "token": 3}, {"required": 34, "ticks": 3, "potential": 3, "token": 2}], "灵感0/25/50的10级学习经济应精确为5/4/3潜能与4/3/2 Token")
	assert_true.call(samples[0].potential > samples[1].potential and samples[1].potential > samples[2].potential, "灵感越高，升级实际潜能消耗必须越少")
	assert_true.call(samples[0].token > samples[1].token and samples[1].token > samples[2].token, "灵感越高，升级实际Token消耗必须越少")

	state.profile = original_profile.duplicate(true)
	state.profile.sect = "NG神教"
	state.profile.master = MASTER_ID
	state.profile.attributes.wisdom = 25
	state.profile.skills = skills.create_default_skills()
	state.profile.skills.learn_progress[BASIC_SKILL_ID] = 6
	state.profile.skills.learn_potential_spent[BASIC_SKILL_ID] = 1
	state.profile.vitals.potential = 0
	state.profile.vitals.money = 100
	var potential_failure: Dictionary = skills.learn_tick(MASTER_ID, BASIC_SKILL_ID)
	assert_true.call(str(potential_failure.get("reason", "")) == "potential" and int(state.profile.skills.learn_progress[BASIC_SKILL_ID]) == 6 and int(state.profile.skills.learn_potential_spent[BASIC_SKILL_ID]) == 1 and skills.level(BASIC_SKILL_ID) == 0, "潜能不足必须中断并保留当前学习经验与潜能消耗记录")
	var first_required: int = skills._learning_xp_required(basic, 1)
	state.profile.skills.learn_progress[BASIC_SKILL_ID] = first_required
	state.profile.skills.learn_potential_spent[BASIC_SKILL_ID] = 2
	state.profile.vitals.money = 0
	var token_failure: Dictionary = skills.learn_tick(MASTER_ID, BASIC_SKILL_ID)
	assert_true.call(str(token_failure.get("reason", "")) == "token" and int(state.profile.skills.learn_progress[BASIC_SKILL_ID]) == first_required and int(state.profile.skills.learn_potential_spent[BASIC_SKILL_ID]) == 2 and skills.level(BASIC_SKILL_ID) == 0, "Token 不足必须中断并保留满额学习经验与潜能消耗记录")
	state.profile.vitals.money = int(token_failure.get("tuition", 0))
	var resumed_result: Dictionary = skills.learn_tick(MASTER_ID, BASIC_SKILL_ID)
	assert_true.call(bool(resumed_result.get("ok", false)) and skills.level(BASIC_SKILL_ID) == 1 and int(state.profile.vitals.potential) == 0 and not state.profile.skills.learn_progress.has(BASIC_SKILL_ID), "补足 Token 后应直接从保留的满额经验完成升级，不得重复消耗潜能")
	state.profile = original_profile
