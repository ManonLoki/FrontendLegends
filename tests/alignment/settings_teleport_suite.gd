extends "res://tests/alignment/menu_suite.gd"
## 传送时序、冥想上限与独立系统设置回归。

func _run_settings_teleport_suite(game: Node) -> void:
	var game_state = root.get_node("GameState")
	var skill_system = root.get_node("SkillSystem")
	var data_registry = root.get_node("DataRegistry")
	var system_settings = root.get_node("SystemSettings")
	# 传送使用自己的下拉 HUD：保留一级菜单、替换功法操作列表，ESC 回功法菜单。
	game_state.profile.sect = "NG神教"
	skill_system.ensure_skills().levels["af088f07-4c52-5a8c-aa16-df96e6b3e056"] = 40
	skill_system.ensure_skills().levels["4d75539d-7873-5039-a596-d3dacc29c4d1"] = 40
	skill_system.ensure_skills().equipped_basic["tune"] = "af088f07-4c52-5a8c-aa16-df96e6b3e056"
	skill_system.ensure_skills().equipped_special["tune"] = "4d75539d-7873-5039-a596-d3dacc29c4d1"
	# 基础架构 40 + NG 架构 40×2，根骨 25 时理论修为终点为 3000；
	# 两门已装备功法另提供 40+40×3=160 精力，传送按总上限 190 的 1/3 收取 64。
	skill_system.ensure_skills().levels["dcebef7e-09b8-5a69-8e3d-159cb2b0c355"] = 40
	skill_system.ensure_skills().levels["9287473e-59a9-5dc8-a914-324ec57ffc14"] = 40
	skill_system.ensure_skills().equipped_basic["arch"] = "dcebef7e-09b8-5a69-8e3d-159cb2b0c355"
	skill_system.ensure_skills().equipped_special["arch"] = "9287473e-59a9-5dc8-a914-324ec57ffc14"
	game_state.profile.attributes.constitution = 25
	game_state.profile.vitals.cultivation = 30
	game_state.combat_state.mp = 9
	game.skill_index = 4
	game._select_skill_menu()
	_assert_true(skill_system.meditation_cap() == 3000 and skill_system.meditation_max_mp_cap() == 3000 and int(skill_system.combat_bonus().get("mp_max", 0)) == 160 and game_state.player_mp_max() == 190 and game.cyber_teleport_controller.cost() == 64, "修为上限应为 3000，已装备功法额外提供 160 精力；传送按当前总上限的 1/3 计费")
	_assert_true(is_equal_approx(game_state.meditation_modifier(25), 1.0), "初始根骨25的冥想修正应处于中性值1.0")
	_assert_true(skill_system.MEDITATION_INNER_POWER_UNIT == 25.0, "每级综合内功应按公式贡献25点冥想修为上限")
	_assert_true(skill_system.meditation_cap_from_values(25, 40, 40) == int(floor(float(40 + 40 * 2) * 25.0 * game_state.meditation_modifier(25))), "40级基础+40级高级、根骨25的冥想上限必须由通用公式推得")
	_assert_true(skill_system.meditation_cap_from_values(25, 39, 40) == 2975 and skill_system.meditation_cap_from_values(25, 40, 39) == 2950, "基础或高级内功等级变化时上限必须随公式变化，不得写死3000")
	_assert_true(skill_system.meditation_cap_from_values(30, 40, 40) == 3300, "根骨变化时冥想上限必须应用根骨修正动态变化")
	game_state.profile.vitals.cultivation = 2999
	game_state.combat_state.mp = game_state.player_mp_max() - 1
	var final_layer_result: Dictionary = skill_system.meditate_tick()
	_assert_true(bool(final_layer_result.get("ok", false)) and bool(final_layer_result.get("cultivation_gained", false)) and game_state.profile.vitals.cultivation == 3000 and game_state.combat_state.mp == 0, "真实冥想 tick 应能从2999升至公式上限3000并清空当前精力")
	game_state.combat_state.mp = game_state.player_mp_max() - 1
	var fill_final_mp_result: Dictionary = skill_system.meditate_tick()
	_assert_true(not bool(fill_final_mp_result.get("ok", true)) and game_state.profile.vitals.cultivation == 3000 and game_state.combat_state.mp == 3160, "修为到 3000 后应继续允许当前精力充至含功法加成的 3160，并在充满时停止")
	var capped_cultivation_before := int(game_state.profile.vitals.cultivation)
	var capped_mp_before := int(game_state.combat_state.mp)
	var capped_result: Dictionary = skill_system.meditate_tick()
	_assert_true(not bool(capped_result.get("ok", true)) and game_state.profile.vitals.cultivation == capped_cultivation_before and game_state.combat_state.mp == capped_mp_before, "冥想到顶后继续 tick 不得突破 3000 修为或 3160 总精力上限")
	game_state.profile.vitals.cultivation = 30
	game_state.combat_state.mp = game_state.player_mp_max() - 1
	game.meditation_open = true
	game.meditation_tick_accumulator = 0.0
	game._update_continuous_skill_actions(skill_system.MEDITATION_TICK_SECONDS * 2.0)
	_assert_true(game_state.profile.vitals.cultivation == 31 and game_state.combat_state.mp == 0, "长帧补算也必须在冥想提升修为后先停在当前精力 0")
	game._update_continuous_skill_actions(0.0)
	_assert_true(game_state.profile.vitals.cultivation == 31 and game_state.combat_state.mp == 5, "剩余冥想时间片应在下一帧从 0 继续恢复精力")
	game._close_meditation()
	game_state.profile.vitals.cultivation = 30
	game_state.combat_state.mp = 9
	_assert_true(game_state.player_mp_max() == 190 and not game.cyber_open and game.dialogue_open and game.dialogue_content.text.contains("需要 64 点精力"), "传送要求应随修为与已装备功法共同构成的精力上限计算")
	game._close_dialogue()
	game_state.profile.vitals.cultivation = 600
	game_state.combat_state.mp = 1200
	while game.map_transitioning:
		await process_frame
	game.menu_open = true
	game.menu_panel.visible = true
	game.menu_index = 2
	game.skill_open = true
	game.skill_index = 4
	game._refresh_menu()
	game._select_skill_menu()
	_assert_true(game.cyber_open and game.active_detail_hud == "cyber" and game.details_panel == game.detail_huds.cyber.panel, "传送应打开独立 CyberHUD")
	_assert_true(game.menu_open and game.menu_panel.visible and not game.skill_menu_panel.visible, "传送目的地 HUD 应保留一级菜单并替换功法二级菜单")
	_assert_true(game.details_panel.size.x < 300.0 and is_equal_approx(game.details_panel.position.y, game.menu_panel.position.y + game.menu_panel.size.y), "CyberHUD 应作为功法菜单下方的窄下拉列表，不得使用全屏详情面板")
	var cyber_labels_before: Array = game.cyber_labels.duplicate()
	var cyber_selection_before = game.cyber_selection_widget
	game._handle_cyber_key(KEY_DOWN)
	_assert_true(game.cyber_selection_widget == cyber_selection_before and game.cyber_labels == cyber_labels_before, "传送光标移动应复用标签和选中框，不得销毁重建整套 HUD")
	game._handle_cyber_key(KEY_ESCAPE)
	_assert_true(not game.cyber_open and not game.details_panel.visible and game.skill_open and game.skill_menu_panel.visible and game.skill_index == 4, "传送 HUD 按 ESC 应退回功法二级菜单的传送项")
	game._select_skill_menu()
	var destination_index: int = game.cyber_maps[game.cyber_index]
	var destination_name: String = data_registry.map_display_name(data_registry.map_id_at(destination_index))
	var map_before_teleport: int = game.map_index
	var mp_before_teleport: int = int(game_state.combat_state.mp)
	game._handle_cyber_key(KEY_SPACE)
	_assert_true(game.dialogue_open and game.dialogue_content.text.contains("你在赛博世界中，靠着量子纠缠，嗖的一下就到达了%s" % destination_name), "传送确认后必须先显示指定量子纠缠文案")
	_assert_true(game.map_index == map_before_teleport and int(game_state.combat_state.mp) == mp_before_teleport, "用户尚未推进传送文案时不得切图或扣除精力")
	game.dialogue_controller.advance()
	_assert_true(not game.dialogue_open and int(game_state.combat_state.mp) == mp_before_teleport - game.cyber_teleport_controller.cost(), "用户推进完传送文案后才应扣除精力")
	await create_timer(0.5).timeout
	_assert_true(game.map_index == destination_index, "用户推进完传送文案后应切换到选定地图")
	game_state.profile.vitals.potential = 2468
	game_state.save_game()
	var save_before_settings := FileAccess.get_file_as_string(game_state.current_save_path())
	game.menu_open = true
	game.menu_panel.visible = true
	game.menu_index = 3
	game.system_open = true
	game.system_index = 3
	game._select_system_menu()
	_assert_true(game.settings_open and game.active_detail_hud == "settings" and game.details_panel == game.detail_huds.settings.panel, "设置必须使用独立 SettingsHUD")
	_assert_true(system_settings.bgm_enabled() and game.settings_controller.bgm_label.text.contains("【开】"), "BGM 设置必须默认打开")
	game.settings_controller.handle_key(KEY_SPACE)
	_assert_true(not system_settings.bgm_enabled() and AudioServer.is_bus_mute(AudioServer.get_bus_index(system_settings.BGM_BUS_NAME)), "关闭 BGM 后必须即时静音专用音频总线")
	var settings_document = JSON.parse_string(FileAccess.get_file_as_string(system_settings.current_settings_path()))
	_assert_true(settings_document is Dictionary and not bool(settings_document.get("bgm_enabled", true)), "BGM 开关必须写入独立设置文件")
	_assert_true(FileAccess.get_file_as_string(game_state.current_save_path()) == save_before_settings, "修改系统设置不得改写角色存档")
	system_settings.load_settings()
	_assert_true(not system_settings.bgm_enabled(), "重新读取独立设置文件后必须保留关闭状态")
	game.settings_controller.handle_key(KEY_RIGHT)
	_assert_true(system_settings.bgm_enabled() and not AudioServer.is_bus_mute(AudioServer.get_bus_index(system_settings.BGM_BUS_NAME)), "设置 HUD 应能重新打开 BGM")
	game.settings_controller.handle_key(KEY_ESCAPE)
	_assert_true(not game.settings_open and not game.details_panel.visible and game.system_open and game.system_index == 3, "SettingsHUD 按 ESC 应返回系统菜单的设置项")
	game._close_menu()
	_assert_true(not game.skill_menu_panel.visible and not game.system_menu_panel.visible, "关闭菜单时应分别隐藏两个二级 HUD 面板")
	system_settings.delete_settings()
	game.queue_free()
