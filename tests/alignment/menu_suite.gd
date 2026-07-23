extends "res://tests/alignment/hud_suite.gd"
## 练功、学习、菜单、加力、冥想与传送回归。

func _run_menu_suite(game: Node) -> void:
	var game_state = root.get_node("GameState")
	var skill_system = root.get_node("SkillSystem")
	var data_registry = root.get_node("DataRegistry")
	var combat_system = root.get_node("CombatSystem")
	_assert_true(game.SKILL_ITEMS == ["冥想", "练功", "加力", "功法", "传送"], "传送必须位于功法菜单最后一项，并显示为“传送”")
	_assert_true(game.SYSTEM_ITEMS == ["摸鱼", "疗伤", "保存", "设置"], "系统菜单最后一项必须由退出改为设置")
	# 背包是主菜单的子页面：分类栏第一次 ESC 返回主菜单，第二次才关闭菜单。
	game.menu_open = false
	game.menu_panel.visible = false
	game._show_inventory()
	game._handle_inventory_key(KEY_ESCAPE)
	_assert_true(not game.inventory_open and not game.details_panel.visible, "背包分类栏按 ESC 应先关闭背包详情页")
	_assert_true(game.menu_open and game.menu_panel.visible and game.menu_index == 1, "背包分类栏按 ESC 应返回主菜单并保留在背包项")
	game._handle_menu_key(KEY_ESCAPE)
	_assert_true(not game.menu_open and not game.menu_panel.visible, "返回主菜单后再次按 ESC 才应完全退出菜单")
	# 练功必须先选左栏分类，再进入右栏选择具体功法。
	game_state.profile.sect = "NG神教"
	game_state.profile.attributes.wisdom = 25
	game_state.profile.vitals.cultivation = 80
	game_state.combat_state.mp = 10
	game_state.combat_state.hp = 100
	skill_system.ensure_skills().levels["2224675d-63f2-50e8-a2c6-064acd5c5623"] = 80
	skill_system.ensure_skills().levels["bcb538e2-4d6a-52ae-990d-20377e27ab64"] = 40
	skill_system.ensure_skills().levels["4d75539d-7873-5039-a596-d3dacc29c4d1"] = 40
	skill_system.ensure_skills().levels["394fdd1b-c49d-52fc-a31b-41adf88a32d6"] = 40
	skill_system.ensure_skills().practice_progress["bcb538e2-4d6a-52ae-990d-20377e27ab64"] = 73
	skill_system.ensure_skills().learn_progress["bcb538e2-4d6a-52ae-990d-20377e27ab64"] = 73
	var ng_definition: Dictionary = data_registry.get_skill("bcb538e2-4d6a-52ae-990d-20377e27ab64")
	game_state.profile.attributes.wisdom = 50
	_assert_true(skill_system.skill_exp_required("bcb538e2-4d6a-52ae-990d-20377e27ab64", 100) == 390 and skill_system._learning_xp_required(ng_definition, 100) == 6000 and skill_system._learning_xp_per_potential() == 14, "高灵感只应提高潜能转化效率，固定升级经验不得改变")
	game_state.profile.attributes.wisdom = 25
	_assert_true(skill_system._learning_xp_required(ng_definition, 41) == 794, "师父学习 40→41 级应固定需要 794 学习经验")
	_assert_true(skill_system.practice_progress("bcb538e2-4d6a-52ae-990d-20377e27ab64").total == 100 and skill_system.learning_progress("bcb538e2-4d6a-52ae-990d-20377e27ab64").total == 794, "练功经验与固定学习经验必须使用独立口径")
	var practice_hp_before: int = game_state.combat_state.hp
	var practice_mp_before: int = game_state.combat_state.mp
	var aligned_practice_tick: Dictionary = skill_system.practice_tick("bcb538e2-4d6a-52ae-990d-20377e27ab64")
	_assert_true(bool(aligned_practice_tick.get("ok", false)) and int(skill_system.ensure_skills().practice_progress["bcb538e2-4d6a-52ae-990d-20377e27ab64"]) == 78, "灵感 25 时练功每 tick 应推进 floor(25/5)=5 点经验")
	_assert_true(game_state.combat_state.mp == practice_mp_before - 2 and game_state.combat_state.hp == practice_hp_before - 4, "练功每 tick 应固定消耗 2 精力，并按经验增量分摊 80% 体力成本")
	game._open_practice()
	_assert_true(game.practice_focus_category and game.practice_categories.size() == 3, "练功打开后应先聚焦编码、思维、招架分类栏")
	_assert_true(game.practice_items == ["bcb538e2-4d6a-52ae-990d-20377e27ab64"], "编码分类右栏应只显示对应的已学门派功法")
	var first_category_x := -INF
	var first_skill_x := -INF
	for first_practice_widget in game.details_widgets:
		if first_practice_widget is Label and str(first_practice_widget.text) == "编码":
			first_category_x = first_practice_widget.position.x
		elif first_practice_widget is Label and str(first_practice_widget.text) == "模版语法":
			first_skill_x = first_practice_widget.position.x
	_assert_true(first_category_x > 0.0 and first_skill_x > game.details_panel.size.x * 0.34, "练功 HUD 首次打开必须按面板实际尺寸完成左右栏布局，不得缩在左上角")
	game._handle_practice_key(KEY_SPACE)
	_assert_true(not game.practice_focus_category and game.practicing_skill_id.is_empty(), "分类栏按空格应只进入功法栏，不得立即开始练功")
	game._handle_practice_key(KEY_SPACE)
	_assert_true(game.practicing_skill_id == "bcb538e2-4d6a-52ae-990d-20377e27ab64" and game.practice_progress_widgets.size() == 1, "功法栏选中具体功法后按空格才应开始修炼")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(game.practice_open and not game.practice_focus_category and game.practicing_skill_id.is_empty(), "修炼中按 ESC 应先停止并留在功法栏")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(game.practice_open and game.practice_focus_category, "功法栏按 ESC 应先退回分类栏")
	game._handle_practice_key(KEY_DOWN)
	_assert_true(game.practice_category_index == 1 and game.practice_items == ["4d75539d-7873-5039-a596-d3dacc29c4d1"], "切换练功分类时右栏功法必须同步更新")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(not game.practice_open and not game.details_panel.visible, "练功分类栏按 ESC 才关闭整个独立 HUD")

	# 练功进度条：开始时显示当前等级内进度，停止后立即清理。
	game.practice_open = true
	game.practice_focus_category = false
	game.practice_items.assign(["bcb538e2-4d6a-52ae-990d-20377e27ab64"])
	game.practice_index = 0
	game.practicing_skill_id = "bcb538e2-4d6a-52ae-990d-20377e27ab64"
	skill_system.ensure_skills().practice_progress["bcb538e2-4d6a-52ae-990d-20377e27ab64"] = 3
	game._refresh_practice()
	_assert_true(game.practice_progress_widgets.size() == 1, "开始练功后应显示独立进度条")
	var practice_meter = game.practice_progress_widgets[0]
	var expected_practice_progress: Dictionary = skill_system.practice_progress("bcb538e2-4d6a-52ae-990d-20377e27ab64")
	_assert_true(practice_meter.current == int(expected_practice_progress.current) and practice_meter.total == int(expected_practice_progress.total), "练功进度条应显示当前等级内的真实进度")
	_assert_true(practice_meter.z_index > game.details_panel.z_index, "练功进度 HUD 应显示在练功面板上方")
	_assert_true(not Rect2(game.map_badge_panel.position, game.map_badge_panel.size).intersects(Rect2(practice_meter.position, practice_meter.size)), "房间名 HUD 不得与练功进度条重叠")
	skill_system.ensure_skills().practice_progress["bcb538e2-4d6a-52ae-990d-20377e27ab64"] = 4
	game._refresh_practice()
	_assert_true(game.practice_progress_widgets[0] == practice_meter and practice_meter.current == 4, "练功 tick 刷新时应复用并更新同一进度条，避免闪烁")
	game.practicing_skill_id = ""
	game._refresh_practice()
	_assert_true(game.practice_progress_widgets.is_empty(), "停止练功后应立即清理进度条")
	# 练功失败应立即停止，并在底部对话框明确提示原因。
	skill_system.ensure_skills().levels["2224675d-63f2-50e8-a2c6-064acd5c5623"] = 10
	skill_system.ensure_skills().levels["dcebef7e-09b8-5a69-8e3d-159cb2b0c355"] = 5
	skill_system.ensure_skills().equipped_basic["arch"] = "dcebef7e-09b8-5a69-8e3d-159cb2b0c355"
	skill_system.ensure_skills().equipped_special.erase("arch")
	skill_system.ensure_skills().levels["bcb538e2-4d6a-52ae-990d-20377e27ab64"] = 1
	game_state.profile.vitals.cultivation = 3
	game._refresh_practice()
	var practice_level_cap_visible := false
	for practice_widget in game.details_widgets:
		if practice_widget is Label and str(practice_widget.text) == "1/8":
			practice_level_cap_visible = true
	_assert_true(game_state.player_mp_max() == 8 and skill_system.practice_cap("bcb538e2-4d6a-52ae-990d-20377e27ab64") == 8 and practice_level_cap_visible, "练功上限应包含 3 修为与已装备架构功法的 5 点精力加成，并显示为 1/8（实际精力上限 %d，练功上限 %d，显示 %s）" % [game_state.player_mp_max(), skill_system.practice_cap("bcb538e2-4d6a-52ae-990d-20377e27ab64"), practice_level_cap_visible])
	game_state.profile.vitals.cultivation = 10
	game_state.combat_state.mp = 0
	game_state.combat_state.hp = 100
	skill_system.ensure_skills().practice_progress["bcb538e2-4d6a-52ae-990d-20377e27ab64"] = 0
	game.practicing_skill_id = "bcb538e2-4d6a-52ae-990d-20377e27ab64"
	game.practice_tick_accumulator = 0.0
	game._update_continuous_skill_actions(skill_system.PRACTICE_TICK_SECONDS)
	_assert_true(game.practicing_skill_id.is_empty() and game.practice_progress_widgets.is_empty(), "练功失败后应停止并清理进度条")
	_assert_true(game.dialogue_open and game.dialogue_panel.visible and game.dialogue_content.text.contains("精力不足，练不动功。"), "精力不足时应在底部练功对话框显示参考文案")
	_assert_true(game.dialogue_panel.z_index > game.details_panel.z_index, "练功资源不足的对话 HUD 应显示在练功面板上方")
	game._close_dialogue()
	skill_system.ensure_skills().levels["bcb538e2-4d6a-52ae-990d-20377e27ab64"] = 7
	game_state.profile.vitals.cultivation = 2
	var practice_cap_failure: Dictionary = skill_system.practice_tick("bcb538e2-4d6a-52ae-990d-20377e27ab64")
	_assert_true(game_state.player_mp_max() == 7 and str(practice_cap_failure.get("reason", "")) == "cap" and str(practice_cap_failure.get("message", "")).contains("精力修为不足，须多冥想积累内力。"), "功法达到含装备加成的 7 点精力上限时，应明确提示继续冥想（实际精力上限 %d，结果 %s）" % [game_state.player_mp_max(), practice_cap_failure])
	game.practice_open = true
	game.menu_open = false
	game.menu_panel.visible = false
	game.practicing_skill_id = "bcb538e2-4d6a-52ae-990d-20377e27ab64"
	game._refresh_practice()
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(game.practice_open and game.practicing_skill_id.is_empty() and game.details_panel.visible, "练功中第一次 ESC 应只停止练功并保留面板")
	_assert_true(not game.menu_open and not game.menu_panel.visible, "停止练功时不得弹出顶部菜单")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(game.practice_open and game.practice_focus_category and game.details_panel.visible, "停止状态再次按 ESC 应从功法栏退回分类栏")
	game._handle_practice_key(KEY_ESCAPE)
	_assert_true(not game.practice_open and not game.details_panel.visible, "回到分类栏后再次按 ESC 应真正关闭练功面板")
	_assert_true(not game.menu_open and not game.menu_panel.visible, "关闭练功面板后不得打开顶部菜单")

	# 学习进度条生命周期：进入右栏不显示；空格启动才显示；资源阻断后立即消失。
	game._clear_learning_progress_widgets()
	game.learning_skill_id = ""
	game.learn_open = true
	game.nearby_npc_id = "21e05288-a075-5137-85e8-a6c4c115be87"
	game_state.profile.sect = "NG神教"
	game_state.profile.master = "21e05288-a075-5137-85e8-a6c4c115be87"
	game.learn_all_items = skill_system.learn_options_for_npc("21e05288-a075-5137-85e8-a6c4c115be87")
	game.learn_category_index = 0
	game._rebuild_learn_categories()
	game._handle_learn_key(KEY_SPACE)
	_assert_true(not game.learn_focus_category and game.learning_progress_widgets.is_empty(), "仅进入功法右栏时不应显示学习进度条")
	game_state.profile.vitals.potential = 0
	game._handle_learn_key(KEY_SPACE)
	_assert_true(str(game.learning_skill_id).is_empty() and game.learning_progress_widgets.is_empty() and str(game.message).contains("潜能不足") and game.dialogue_open and game.dialogue_content.text.contains("潜能不足"), "潜能不足时应弹出提示且不得启动或闪现学习进度条")
	game._close_dialogue()
	game_state.profile.vitals.potential = 1000
	game._handle_learn_key(KEY_SPACE)
	_assert_true(not str(game.learning_skill_id).is_empty() and game.learning_progress_widgets.size() == 1, "选中功法按空格后才应显示并启动进度条")
	var selected_skill: String = game.learn_items[game.learn_index]
	game_state.profile.vitals.potential = 1
	game._update_continuous_skill_actions(skill_system.LEARNING_TICK_SECONDS)
	var interrupted_progress := int(skill_system.ensure_skills().learn_progress.get(selected_skill, 0))
	_assert_true(interrupted_progress > 0 and not str(game.learning_skill_id).is_empty(), "最后一点潜能应先推进并保存当前学习经验")
	game._update_continuous_skill_actions(skill_system.LEARNING_TICK_SECONDS)
	_assert_true(str(game.learning_skill_id).is_empty() and game.learning_progress_widgets.is_empty() and int(skill_system.ensure_skills().learn_progress.get(selected_skill, 0)) == interrupted_progress and game.dialogue_open and game.dialogue_content.text.contains("潜能不足"), "潜能不足应弹出提示、中断并停留在当前学习经验")
	game._close_dialogue()
	var selected_definition: Dictionary = data_registry.get_skill(selected_skill)
	var selected_level: int = skill_system.level(selected_skill)
	var selected_required: int = skill_system._learning_xp_required(selected_definition, selected_level + 1)
	var selected_gain: int = skill_system._learning_xp_per_potential()
	var spent_before := int(ceil(float(selected_required - selected_gain) / float(selected_gain)))
	skill_system.ensure_skills().learn_progress[selected_skill] = selected_required - selected_gain
	skill_system.ensure_skills().learn_potential_spent[selected_skill] = spent_before
	game_state.profile.vitals.potential = 1
	game_state.profile.vitals.money = 100000
	var money_before := int(game_state.profile.vitals.money)
	game._handle_learn_key(KEY_SPACE)
	game._update_continuous_skill_actions(skill_system.LEARNING_TICK_SECONDS)
	_assert_true(skill_system.level(selected_skill) == selected_level + 1, "最后 1 点潜能应在同一 tick 完成升级")
	_assert_true(int(game_state.profile.vitals.potential) == 0, "每个有效学习 tick 应只消耗 1 点潜能")
	_assert_true(int(game_state.profile.vitals.money) == money_before - ceili(float(spent_before + 1) * 0.65), "升级 Token 学费应按本级实际潜能消耗的 65% 结算")
	_assert_true(str(game.learning_skill_id).is_empty() and game.learning_progress_widgets.is_empty(), "学习完成后进度条应立即消失")
	var token_blocked_level: int = skill_system.level(selected_skill)
	var token_blocked_required: int = skill_system._learning_xp_required(selected_definition, token_blocked_level + 1)
	var token_blocked_spent := int(ceil(float(token_blocked_required) / float(selected_gain)))
	skill_system.ensure_skills().learn_progress[selected_skill] = token_blocked_required
	skill_system.ensure_skills().learn_potential_spent[selected_skill] = token_blocked_spent
	game_state.profile.vitals.money = 0
	game._handle_learn_key(KEY_SPACE)
	_assert_true(str(game.learning_skill_id).is_empty() and game.learning_progress_widgets.is_empty() and str(game.message).contains("Token 不足") and int(skill_system.ensure_skills().learn_progress[selected_skill]) == token_blocked_required and game.dialogue_open and game.dialogue_content.text.contains("Token 不足"), "Token 不足应弹出提示、在启动前中断并保留满额学习经验")
	game._close_dialogue()
	var token_tuition := ceili(float(token_blocked_spent) * 0.65)
	game_state.profile.vitals.money = token_tuition
	game._handle_learn_key(KEY_SPACE)
	game._update_continuous_skill_actions(skill_system.LEARNING_TICK_SECONDS)
	_assert_true(skill_system.level(selected_skill) == token_blocked_level + 1 and int(game_state.profile.vitals.potential) == 0 and int(game_state.profile.vitals.money) == 0, "补足 Token 后应直接完成升级且不得再次消耗潜能")
	game.npc_menu_open = false
	game.npc_menu_panel.visible = false
	game.learn_focus_category = false
	game._handle_learn_key(KEY_ESCAPE)
	_assert_true(game.learn_open and game.learn_focus_category and game.details_panel.visible and not game.npc_menu_panel.visible, "学习功法栏按 ESC 应只退回分类，不得叠加 NPC 菜单")
	game._handle_learn_key(KEY_ESCAPE)
	_assert_true(not game.learn_open and not game.details_panel.visible and not game.npc_menu_open and not game.npc_menu_panel.visible, "学习分类层按 ESC 应关闭独立 HUD 并直接回到地图")

	# 顶栏与两个二级菜单必须由独立 HUD 面板承载，切换时互斥显示。
	game.menu_open = true
	game.menu_panel.visible = true
	game.menu_index = 2
	game.skill_open = true
	game.system_open = false
	game._refresh_menu()
	_assert_true(game.menu_panel.visible and game.skill_menu_panel.visible and not game.system_menu_panel.visible, "技能二级菜单应保留一级菜单，并只显示独立的 SkillMenu 面板")
	_assert_true(game.skill_menu_items.get_child_count() == game.SKILL_ITEMS.size(), "技能二级菜单条目应挂在自己的 HUD 面板中")
	# 加力在技能菜单内进入独立调整态，上下调档、空格确认；上限取基础架构+高级架构×2。
	game_state.profile.sect = "NG神教"
	skill_system.ensure_skills().levels["dcebef7e-09b8-5a69-8e3d-159cb2b0c355"] = 40
	skill_system.ensure_skills().levels["9287473e-59a9-5dc8-a914-324ec57ffc14"] = 40
	skill_system.ensure_skills().equipped_basic["arch"] = "dcebef7e-09b8-5a69-8e3d-159cb2b0c355"
	skill_system.ensure_skills().equipped_special["arch"] = "9287473e-59a9-5dc8-a914-324ec57ffc14"
	skill_system.ensure_skills().force_power = 0
	game.skill_index = 2
	game._select_skill_menu()
	_assert_true(game.force_power_open and game.force_power_limit == 120 and game.dialogue_content.text.contains("加力 0 / 120"), "选择加力后应按图示进入菜单内调整态，并显示当前值与内功上限")
	game._handle_menu_key(KEY_UP)
	_assert_true(game.force_power_value == 1 and game.dialogue_content.text.contains("命中耗 1 精力"), "加力调整态按上应增加一档并实时刷新说明")
	game._handle_menu_key(KEY_SPACE)
	_assert_true(not game.force_power_open and skill_system.force_power() == 1 and game.skill_open and game.skill_menu_panel.visible, "加力按空格应提交选定值并返回技能二级菜单")
	# 精力不足时不得按剩余精力部分加力；足额时整档扣除并附加 0~2 倍伤害。
	skill_system.set_force_power(10)
	game_state.combat_state.mp = 5
	var no_force_result := {"damage": 100}
	_assert_true(combat_system._apply_player_force_power(no_force_result) == 0 and game_state.combat_state.mp == 5 and no_force_result.damage == 100, "精力不足完整档位时加力必须完全不生效")
	game_state.combat_state.mp = 10
	seed(13)
	var force_result := {"damage": 100}
	var force_extra: int = combat_system._apply_player_force_power(force_result)
	_assert_true(game_state.combat_state.mp == 0 and force_extra >= 8 and force_extra <= 10 and force_result.damage == 100 + force_extra, "10 点加力应整档扣精力，并按 10/(10+100) 的递减收益追加约 8~10 点伤害")
	game.menu_index = 3
	game.skill_open = false
	game.system_open = true
	game._refresh_menu()
	_assert_true(game.menu_panel.visible and game.system_menu_panel.visible and not game.skill_menu_panel.visible, "系统二级菜单应保留一级菜单，并只显示独立的 SystemMenu 面板")
	_assert_true(game.system_menu_items.get_child_count() == game.SYSTEM_ITEMS.size(), "系统二级菜单条目应挂在自己的 HUD 面板中")
	game.system_index = 2
	game._select_system_menu()
	_assert_true(game.menu_open and game.menu_panel.visible and game.system_menu_panel.visible, "保存等无弹窗的二级操作不得收起父子菜单")
