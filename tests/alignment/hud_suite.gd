extends "res://tests/alignment/domain_suite.gd"
## 场景坐标、图集、详情 HUD、交易与交互回归。

func _run_hud_suite() -> Node:
	var game_state = root.get_node("GameState")
	var skill_system = root.get_node("SkillSystem")
	var inventory_system = root.get_node("InventorySystem")
	var data_registry = root.get_node("DataRegistry")
	var npc_system = root.get_node("NpcSystem")
	var orientation_script = load("res://scripts/mobile_orientation.gd")
	var web_script: String = orientation_script._build_web_script(true)
	_assert_true(not web_script.contains("rotate(90deg)"), "Web 横屏失败时不得旋转 Canvas，否则微信触摸坐标会与画面错位")
	_assert_true(web_script.contains("if (true)") and not web_script.contains("__FROM_USER_GESTURE__"), "Web 横屏脚本必须安全替换用户手势标记")
	_assert_true(web_script.contains("FrontendMobileOrientation.request()"), "移动 Web 横屏必须通过 HTML 用户手势桥请求")
	var web_shell := FileAccess.get_file_as_string("res://web/index_shell.html")
	_assert_true(web_shell.contains("id=\"game-frame\"") and web_shell.contains("remapRotatedTouch"), "微信 CSS 横屏必须在 Godot Canvas 外层旋转并重映射触摸坐标")
	_assert_true(web_shell.contains("width=\"480\" height=\"320\""), "Web Canvas 必须在 HTML 层声明固定 480×320 内部尺寸")
	_assert_true(web_shell.contains("gameFrame.style.left") and web_shell.contains("matrix(0, ${uniformScale}"), "旋转容器必须按实时可视区使用像素矩阵居中")
	_assert_true(web_shell.contains("availableHeight / naturalHeight") and web_shell.contains("naturalWidth * uniformScale"), "微信 WebGL 必须按高度生成唯一倍率并等比缩放宽度")
	_assert_true(web_shell.contains("window.visualViewport") and web_shell.contains("maximum-scale=1"), "微信缩放必须锁定页面级缩放并使用真实可视视口")
	var web_builder := FileAccess.get_file_as_string("res://tools/build-web.mjs")
	_assert_true(not web_builder.contains("writeFile(exportPresets"), "Web 构建不得临时改写导出预设")
	_assert_true(web_builder.contains("rm(outputDirectory") and web_builder.contains("relativeOutputDirectory"), "Web 构建必须安全清空发布目录后再导出")
	var web_hasher := FileAccess.get_file_as_string("res://tools/hash-web-build.mjs")
	_assert_true(web_builder.contains("packManifest") and web_hasher.contains("__CONTENT_PACK_MANIFEST__") and web_hasher.contains("manifest.${manifestHash}.bin"), "Web 构建必须把免 JSON gzip 的内容寻址分包清单注入页面")
	_assert_true(web_shell.contains("FrontendContentPackManifest") and web_shell.contains("__CONTENT_PACK_MANIFEST__"), "Web 页面必须向运行时暴露当前分包清单")
	var content_pack_source := FileAccess.get_file_as_string("res://scripts/content_packs/content_pack_manager.gd")
	_assert_true(content_pack_source.contains("request.accept_gzip = false"), "Web 分包请求必须避免浏览器与 Godot 重复解压 gzip")
	var export_presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	_assert_true(export_presets.count("platform=\"Web\"") == 1 and export_presets.contains("Web=\"Web\""), "项目必须只保留 Web 分包导出预设")
	_assert_true(export_presets.count("include_filter=\"*.ogg,*.tmx,*.tsx,*.tpsheet\"") == 3, "macOS、Windows 与 Android 导出必须包含音频、运行时地图和图集定义")
	_assert_true(export_presets.contains("name=\"Web\"") and export_presets.contains("custom_features=\"split_content_packs\"") and export_presets.contains("export_filter=\"exclude\""), "正式 Web 构建必须使用内容分包预设")
	_assert_true(export_presets.count("include_filter=\"*.tmx,*.tpsheet\"") == 1, "Web 主包只应保留运行时 TMX 与图集定义")
	_assert_true(export_presets.contains("assets/Map/assets/*.png,assets/Map/tilesets/*.tsx") and export_presets.contains("dist/*,node_modules/*") and export_presets.contains("tests/*,tools/*,docs/*"), "Web 主包必须排除分包资源与非运行文件")
	var bgm_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/Data/bgm_packs.json"))
	for pack_definition in bgm_catalog.get("packs", {}).values():
		_assert_true(export_presets.contains(str(pack_definition.get("audio", ""))), "Web 必须显式排除每个地区音频资源")
	var map_pack_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/Data/map_packs.json"))
	_assert_true(map_pack_catalog.get("packs", {}).size() == 12 and int(map_pack_catalog.get("sharedUseThreshold", 0)) == 5, "Web 地图必须按 12 个地区拆分，并提取高复用共享图块")
	var map_transition_source := FileAccess.get_file_as_string("res://scripts/game/world/map_transition_controller.gd")
	_assert_true(map_transition_source.contains("ensure_map_pack(target_map_id)"), "Web 跨地区加载地图前必须先挂载对应地图包")
	_assert_true(map_transition_source.contains("地图资源加载失败") and map_transition_source.contains("transition_overlay.color.a = 0.0"), "地图分包失败时必须退出黑色遮罩并显示错误")
	var dark_study_map := TiledMapLoader.new()
	_assert_true(dark_study_map.load_file("res://assets/Map/maps/LoreWorld/KaiyuanTown/DarkXue.tmx"), "HUD 测试应能加载 DARK学地图")
	dark_study_map.inject_objects(data_registry.world_event_objects(dark_study_map.map_id, dark_study_map.tile_width, dark_study_map.tile_height))
	# 启动、角色创建、地图相机与逻辑视口统一为 480×320。
	var splash = load("res://scenes/splash.tscn").instantiate()
	root.add_child(splash)
	await process_frame
	var splash_bgm: AudioStreamPlayer = splash.get_node("TitleBgm")
	_assert_true(splash_bgm.playing and splash_bgm.stream.resource_path.ends_with("前端群侠传.ogg"), "Splash 应自动播放前端群侠传 OGG")
	_assert_true((splash_bgm.stream as AudioStreamOggVorbis).loop, "Splash 标题音乐应循环播放")
	var splash_view_center: Vector2 = splash.get_viewport_rect().size * 0.5
	_assert_true(splash.stage.size == Vector2(480.0, 320.0) and splash.stage.scale == Vector2.ONE and splash.stage.get_rect().get_center().is_equal_approx(splash_view_center), "Splash 的 480×320 设计舞台应与逻辑视口重合")
	_assert_true(splash.prompt.size.x == 480.0 and is_equal_approx(splash.prompt.position.x, 0.0), "Splash 提示文字应在完整设计画布上居中")
	splash.queue_free()
	await process_frame
	var character_creation = load("res://scenes/character_creation.tscn").instantiate()
	root.add_child(character_creation)
	await process_frame
	var creation_bgm: AudioStreamPlayer = character_creation.get_node("TitleBgm")
	_assert_true(creation_bgm.playing and creation_bgm.stream.resource_path.ends_with("前端群侠传.ogg"), "CharacterCreation 应自动播放前端群侠传 OGG")
	_assert_true((creation_bgm.stream as AudioStreamOggVorbis).loop, "CharacterCreation 标题音乐应循环播放")
	var creation_view_center: Vector2 = character_creation.get_viewport_rect().size * 0.5
	_assert_true(character_creation.stage.size == Vector2(480.0, 320.0) and character_creation.stage.scale == Vector2.ONE and character_creation.stage.get_rect().get_center().is_equal_approx(creation_view_center), "CharacterCreation 的 480×320 设计舞台应与逻辑视口重合")
	_assert_true(character_creation.intro_root.scale == Vector2.ONE and character_creation.intro_root.position == Vector2.ZERO, "CharacterCreation 开场内容应占满设计画布")
	_assert_true(character_creation.form.scale == Vector2.ONE and character_creation.form.position == Vector2.ZERO, "CharacterCreation 表单应占满设计画布")
	var name_style: StyleBoxFlat = character_creation.name_edit.get_theme_stylebox("normal")
	_assert_true(is_zero_approx(name_style.bg_color.a), "角色姓名输入框普通状态不得保留黄色或其他实色背景")
	_assert_true(name_style.content_margin_left == 4.0 and name_style.content_margin_top == 4.0 and name_style.content_margin_right == 4.0 and name_style.content_margin_bottom == 4.0, "角色姓名输入框文字应与四边保持 4px 内边距")
	_assert_true(character_creation.name_edit.mouse_filter == Control.MOUSE_FILTER_STOP, "角色姓名输入框必须接收移动端触摸以唤起软键盘")
	character_creation.mobile_runtime = true
	character_creation._finish_intro()
	_assert_true(not character_creation.name_editing, "移动端进入角色表单时不应在用户按 A 前自动弹出键盘")
	var name_touch := InputEventScreenTouch.new()
	name_touch.pressed = true
	name_touch.position = character_creation.name_edit.get_global_rect().get_center()
	character_creation._input(name_touch)
	_assert_true(character_creation.name_editing and character_creation.name_edit.has_focus(), "移动端直接触摸姓名输入框应在同一事件栈进入编辑状态")
	character_creation._save_name_edit()
	var mobile_keyboard_event := InputEventKey.new()
	mobile_keyboard_event.keycode = KEY_SPACE
	mobile_keyboard_event.pressed = true
	character_creation._input(mobile_keyboard_event)
	_assert_true(character_creation.name_editing and character_creation.name_edit.has_focus(), "移动 Web 实体键盘确认键应与虚拟 A 一样进入姓名输入焦点")
	character_creation._input(mobile_keyboard_event)
	_assert_true(not character_creation.name_editing and not character_creation.name_edit.has_focus(), "移动 Web 实体键盘再次确认应退出姓名输入焦点")
	character_creation.queue_free()
	await process_frame

	# 对话分页与顶部进度条几何：一行一页；相机视口顶部 16px、水平居中。
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var runtime_bgm = game.map_transition_controller.bgm_controller
	_assert_true(not runtime_bgm.current_track_path().is_empty(), "游戏场景加载初始地图时应同步启动对应 BGM")
	_assert_true(runtime_bgm.active_player_index >= 0 and runtime_bgm.players[runtime_bgm.active_player_index].playing, "初始地图 BGM 应在实际游戏场景中持续播放")
	# 新 TexturePacker 图集必须直接按 tpsheet 载入，不能继续使用旧横排图集坐标。
	_assert_true(game.player_sprite_regions.size() == 64 and game.player_foot_anchors.size() == 64, "Player 图集应载入男女、四方向、idle/run 各四帧，共 64 帧")
	_assert_true(npc_system.sprite_regions.size() == 70, "NPC 图集应从 NPC.tpsheet 载入全部 70 个角色区域")
	for gender in ["male", "female"]:
		for direction in ["down", "left", "right", "up"]:
			for motion in ["idle", "run"]:
				for frame in 4:
					var expected_player_frame := "player_%s_%s_%s_%d" % [gender, direction, motion, frame]
					_assert_true(game.player_sprite_regions.has(expected_player_frame), "Player 图集缺少帧：%s" % expected_player_frame)
	for npc_id in data_registry.npcs:
		var npc_sprite := str(data_registry.npcs[npc_id].get("sprite", "npc-1")).get_file().get_basename()
		_assert_true(npc_system.sprite_regions.has(npc_sprite), "NPC %s 引用了图集中不存在的角色 %s" % [npc_id, npc_sprite])
	for player_region_value in game.player_sprite_regions.values():
		var player_region: Rect2 = player_region_value
		_assert_true(Rect2(Vector2.ZERO, game.player_texture.get_size()).encloses(player_region), "Player 帧区域不得越出运行时图集")
	for player_frame_key in game.player_foot_anchors:
		var foot_anchor: Vector2 = game.player_foot_anchors[player_frame_key]
		var player_region: Rect2 = game.player_sprite_regions[player_frame_key]
		_assert_true(foot_anchor.x >= 0.0 and foot_anchor.x <= player_region.size.x, "Player 帧脚部横向支点必须位于裁切区域内：%s" % player_frame_key)
		_assert_true(foot_anchor.y > 0.0 and foot_anchor.y <= player_region.size.y, "Player 帧脚底线必须位于裁切区域内：%s" % player_frame_key)
	for npc_region_value in npc_system.sprite_regions.values():
		var npc_region: Rect2 = npc_region_value
		_assert_true(Rect2(Vector2.ZERO, game.npc_texture.get_size()).encloses(npc_region), "NPC 帧区域不得越出新 128×244 图集")
	game_state.profile.gender = "male"
	game.facing = Vector2i.DOWN
	game.player_moving = false
	game.animation_frame = 2
	_assert_true(game._player_frame_key() == "player_male_down_idle_0", "静止时应固定显示当前方向的 idle_0")
	game_state.profile.gender = "female"
	game.facing = Vector2i.LEFT
	game.player_moving = true
	game.animation_frame = 0
	_assert_true(game._player_frame_key() == "player_female_left_run_0", "行走序列第 0 帧应使用第一张动作帧")
	game.animation_frame = 1
	_assert_true(game._player_frame_key() == "player_female_left_run_1", "行走序列第二帧应使用第一张跨步帧")
	game.animation_frame = 2
	_assert_true(game._player_frame_key() == "player_female_left_run_2", "行走序列第三帧应使用相反脚接触帧")
	game.animation_frame = 3
	_assert_true(game._player_frame_key() == "player_female_left_run_3", "行走序列第四帧应使用相反脚的跨步帧")
	game_state.profile.gender = "male"
	game.facing = Vector2i.DOWN
	game.player_moving = false
	game.animation_frame = 0
	var test_player_position := Vector2(100.0, 80.0)
	var expected_player_foot: Vector2 = test_player_position + game.world_renderer.PLAYER_TILE_FOOT * float(game._render_scale())
	for player_frame_key in game.player_foot_anchors:
		var player_region: Rect2 = game.player_sprite_regions[player_frame_key]
		var player_draw_rect: Rect2 = game.world_renderer.player_frame_draw_rect(test_player_position, player_region, player_frame_key)
		var foot_anchor: Vector2 = game.player_foot_anchors[player_frame_key]
		var rendered_player_foot: Vector2 = player_draw_rect.position + foot_anchor * float(game._render_scale()) * float(game.world_renderer.PLAYER_VISUAL_SCALE)
		_assert_true(rendered_player_foot.is_equal_approx(expected_player_foot), "所有 Player 性别、方向和动作帧必须对齐到同一个格子脚点：%s" % player_frame_key)
	_assert_true(is_equal_approx(game.world_renderer.PLAYER_VISUAL_SCALE, 0.72), "Player 新图集应缩放到适合 16px 地图格的可见高度")
	# UI 与地图相机统一使用 480×320 逻辑坐标；窗口缩放只交给 Godot stretch。
	_assert_true(is_equal_approx(game._display_scale(), 1.0), "游戏 UI 不应按物理窗口执行第二次缩放")
	var runtime_viewport_size: Vector2 = game.get_viewport_rect().size
	var runtime_game_view: Rect2 = game._game_view_rect()
	_assert_true(is_equal_approx(runtime_game_view.size.aspect(), game.CAMERA_SIZE.aspect()), "地图相机运行时应保持 480×320 的设计比例")
	_assert_true(is_equal_approx(runtime_game_view.size.y, runtime_viewport_size.y) and is_equal_approx(runtime_game_view.position.y, 0.0), "地图相机运行时应等比放大并占满逻辑窗口高度")
	_assert_true(runtime_game_view.get_center().is_equal_approx(runtime_viewport_size * 0.5), "地图相机应在实际逻辑视口中居中")
	game.map_context = dark_study_map
	var covered_map_size: Vector2 = Vector2(dark_study_map.width * dark_study_map.tile_width, dark_study_map.height * dark_study_map.tile_height) * game.world_renderer.map_zoom()
	_assert_true(covered_map_size == Vector2(320.0, 240.0), "室内地图应按原始像素尺寸显示，不得自动放大")
	game._layout_game_view()
	game._toggle_menu()
	var stable_menu_widgets: Array = game.menu_widgets.duplicate()
	for frame in 3:
		game._process(1.0 / 60.0)
	_assert_true(game.menu_widgets.size() == stable_menu_widgets.size(), "菜单连续帧不应重复创建控件")
	for index in stable_menu_widgets.size():
		_assert_true(game.menu_widgets[index] == stable_menu_widgets[index], "菜单连续帧应复用同一批控件，避免闪烁")
	game._toggle_menu()
	var design_rect := Rect2(Vector2.ZERO, Vector2(480.0, 320.0))
	for panel in [game.map_badge_panel, game.menu_panel, game.details_panel, game.tree_confirm_panel, game.battle_panel]:
		_assert_true(design_rect.encloses(Rect2(panel.position, panel.size)), "%s 必须完整位于设计画布内" % panel.name)
	var runtime_rect := Rect2(Vector2.ZERO, game.get_viewport_rect().size)
	_assert_true(runtime_rect.encloses(Rect2(game.dialogue_panel.position, game.dialogue_panel.size)), "Dialogue 必须完整位于扩展后的运行时逻辑视口内")
	# 人物面板括号百分比只反映伤势造成的上限折损，与当前剩余体力无关。
	var true_hp_max: int = game_state.player_hp_max()
	var previous_injury := int(game_state.combat_state.get("injury", 0))
	var previous_hp := int(game_state.combat_state.get("hp", 0))
	game_state.combat_state.injury = int(round(float(true_hp_max) * 0.5))
	var effective_hp_max: int = game_state.player_effective_hp_max()
	game_state.combat_state.hp = maxi(1, int(floor(float(effective_hp_max) * 0.25)))
	game._show_profile_panel()
	var profile_text := ""
	for profile_widget in game.details_widgets:
		if profile_widget is Label and str(profile_widget.text).contains("体力："):
			profile_text = str(profile_widget.text)
	var injury_percent: int = game_state.player_effective_hp_percent()
	_assert_true(profile_text.contains("体力：%d / %d（%d%%）" % [game_state.combat_state.hp, effective_hp_max, injury_percent]), "人物面板体力百分比应按有效上限/真实上限显示，不得按当前体力/有效上限计算")
	game_state.combat_state.injury = previous_injury
	game_state.combat_state.hp = previous_hp
	game._show_inventory()
	var inventory_has_title := false
	var first_inventory_category_y := INF
	for widget in game.details_widgets:
		if widget is Label and str(widget.text).begins_with("背包"):
			inventory_has_title = true
		if widget is Label and str(widget.text) == "食物":
			first_inventory_category_y = widget.position.y
	_assert_true(not inventory_has_title, "背包详情面板不应再创建顶部 Title")
	_assert_true(first_inventory_category_y < 30.0, "移除 Title 后背包内容应上移并回收顶部空间")
	var inventory_hud: PanelContainer = game.detail_huds.inventory.panel
	var inventory_child_count: int = (game.detail_huds.inventory.content as Label).get_child_count()
	game._render_skill_book_widgets()
	_assert_true(game.detail_huds.skill_book.panel != inventory_hud, "背包与功法必须使用不同 HUD 面板")
	_assert_true(not inventory_hud.visible and game.detail_huds.skill_book.panel.visible, "切换详情 HUD 时只应显示目标面板")
	_assert_true(game.detail_huds.inventory.content.get_child_count() == inventory_child_count, "渲染功法 HUD 不得清理或重建背包 HUD 的控件")
	var unique_detail_panel_ids: Dictionary = {}
	for detail_entry in game.detail_huds.values():
		unique_detail_panel_ids[(detail_entry.panel as PanelContainer).get_instance_id()] = true
	_assert_true(unique_detail_panel_ids.size() == game.detail_huds.size(), "每类详情 HUD 必须拥有独立 PanelContainer，不得复用")
	game.nearby_npc_id = "fface007-32fe-52f4-8e8c-19b497f364e8"
	game.trade_mode = game.TRADE_MODE_BUY
	game.trade_all_items = data_registry.list_vendor_stock("fface007-32fe-52f4-8e8c-19b497f364e8")
	game.trade_open = true
	game._rebuild_trade_categories()
	_assert_true(game.active_detail_hud == "buy" and game.details_panel == game.detail_huds.buy.panel, "购买应使用独立 BuyHUD，不得复用 NPC 菜单")
	_assert_true(game.details_panel != game.npc_menu_panel, "购买 HUD 与 NPC 交互 HUD 必须是不同节点")
	_assert_true(game.detail_huds.buy.panel != game.detail_huds.sell.panel, "购买与典当必须使用不同 HUD 面板")
	var trade_has_title := false
	var trade_has_money := false
	var trade_has_divider := false
	for widget in game.details_widgets:
		if widget is Label and str(widget.text) == "— 购买 —":
			trade_has_title = true
		elif widget is Label and str(widget.text).begins_with("持有 "):
			trade_has_money = true
		elif widget is ColorRect and widget.size.x <= 1.0 and widget.position.y >= 60.0:
			trade_has_divider = true
	_assert_true(trade_has_title and trade_has_money and trade_has_divider, "购买 HUD 应包含标题、余额和左右栏分隔线")
	game._handle_trade_key(KEY_SPACE)
	var repeatedly_traded_item := str(game.trade_items[game.trade_index])
	var count_before_repeated_buy: int = inventory_system.count(repeatedly_traded_item)
	game._handle_trade_key(KEY_SPACE)
	_assert_true(not game.trade_focus_category and str(game.trade_items[game.trade_index]) == repeatedly_traded_item, "购买一次后应停留在当前右栏物品")
	game._handle_trade_key(KEY_SPACE)
	_assert_true(inventory_system.count(repeatedly_traded_item) == count_before_repeated_buy + 2, "右栏按两次空格应连续购买同一物品两次")
	game._handle_trade_key(KEY_ESCAPE)
	_assert_true(game.trade_open and game.trade_focus_category and game.details_panel.visible, "购买右栏按 ESC 应先退回分类层，不得直接关闭")
	_assert_true(not game.npc_menu_open and not game.npc_menu_panel.visible, "购买回退过程中不得重新叠加 NPC 菜单")
	game._handle_trade_key(KEY_ESCAPE)
	_assert_true(not game.trade_open and not game.details_panel.visible, "购买在分类层按 ESC 应关闭整个交易面板")
	_assert_true(not game.npc_menu_open and not game.npc_menu_panel.visible, "关闭购买面板后不得弹回 NPC 菜单")
	game.trade_mode = game.TRADE_MODE_SELL
	game.trade_open = true
	game.trade_all_items.clear()
	for inventory_entry in inventory_system.list_entries():
		game.trade_all_items.append(inventory_entry.get("id", ""))
	game.trade_category_index = 0
	game._rebuild_trade_categories()
	var sold_category: String = game._item_category(repeatedly_traded_item)
	game.trade_category_index = game.trade_categories.find(sold_category)
	game._refresh_trade_items()
	game._handle_trade_key(KEY_SPACE)
	game.trade_index = game.trade_items.find(repeatedly_traded_item)
	var count_before_repeated_sell: int = inventory_system.count(repeatedly_traded_item)
	var sell_quantity_visible := false
	for sell_widget in game.details_widgets:
		if sell_widget is Label and str(sell_widget.text) == "× %d" % count_before_repeated_sell:
			sell_quantity_visible = true
	_assert_true(count_before_repeated_sell > 1 and sell_quantity_visible, "典当物品存在多个时应显示当前剩余数量")
	game._handle_trade_key(KEY_SPACE)
	_assert_true(not game.trade_focus_category, "典当一次后应停留在右栏，不得跳回分类")
	var single_quantity_hidden := true
	for sell_widget in game.details_widgets:
		if sell_widget is Label and str(sell_widget.text) == "× 1":
			single_quantity_hidden = false
	_assert_true(inventory_system.count(repeatedly_traded_item) == 1 and single_quantity_hidden, "典当后只剩一个时数量应实时更新并隐藏单件标记")
	game._handle_trade_key(KEY_SPACE)
	_assert_true(inventory_system.count(repeatedly_traded_item) == count_before_repeated_sell - 2, "右栏按两次空格应连续典当物品两次")
	game._handle_trade_key(KEY_ESCAPE)
	_assert_true(game.trade_open and game.trade_focus_category, "典当右栏按 ESC 应先退回分类层")
	game._handle_trade_key(KEY_ESCAPE)
	_assert_true(not game.trade_open and not game.details_panel.visible and not game.npc_menu_open, "典当分类层按 ESC 应直接关闭且不重开 NPC 菜单")
	game.trade_open = false
	game.details_panel.visible = false
	game.inventory_open = false
	game.nearby_npc_id = "ac079dbc-e7f3-5aa7-9ef1-6db6e8ec3eb1"
	game.battle_ui.start()
	await process_frame
	# 高属性与任务人物的资源数值必须使用独立文本区完整显示，头像必须取战斗快照形象。
	game.battle_ui.enemy_hp = 98765
	game.battle_ui.session.enemy_hp = 98765
	game.battle_ui.session.enemy_max_hp = 123456
	game.battle_ui.session.enemy_mp = 87654
	game.battle_ui.session.enemy_mp_max = 234567
	game.battle_ui.refresh()
	var complete_enemy_values: Dictionary = {}
	var enemy_portrait_matches := false
	for battle_widget in game.battle_ui.widgets:
		if battle_widget is Label and battle_widget.has_meta("battle_stat_value"):
			complete_enemy_values[str(battle_widget.text)] = true
		if battle_widget is TextureRect and battle_widget.texture is AtlasTexture:
			var portrait_atlas := battle_widget.texture as AtlasTexture
			if portrait_atlas.atlas == game.npc_texture and portrait_atlas.region == npc_system.sprite_region_for_instance(game.battle_ui.enemy):
				enemy_portrait_matches = true
	_assert_true(complete_enemy_values.has("98765/123456") and complete_enemy_values.has("87654/234567"), "战斗 HUD 应完整显示高属性和任务人物的体力、精力数值")
	_assert_true(enemy_portrait_matches, "战斗 HUD 应直接使用本次敌人快照中的任务形象")
	var stat_components: Array[Control] = []
	for widget in game.battle_ui.widgets:
		_assert_true(Rect2(Vector2.ZERO, game.battle_panel.size).encloses(Rect2(widget.position, widget.size)), "战斗 UI 元素不得互相挤出面板边界：%s %s / %s（面板 %s，报告 %s）" % [widget.get_class(), widget.position, widget.size, game.battle_panel.size, widget.has_meta("battle_report")])
		if widget is Control and widget.has_meta("battle_stat_component"):
			stat_components.append(widget)
	for left_index in stat_components.size():
		for right_index in range(left_index + 1, stat_components.size()):
			var left_rect := Rect2(stat_components[left_index].position, stat_components[left_index].size)
			var right_rect := Rect2(stat_components[right_index].position, stat_components[right_index].size)
			_assert_true(not left_rect.intersects(right_rect), "战斗 HUD 的属性文字区域不得互相覆盖：%s / %s" % [left_rect, right_rect])
	game.battle_ui.active = false
	game.battle_panel.visible = false
	game.battle_ui._clear_widgets()
	_assert_true(game._prop_display_name({"type": "WorldEvent", "properties": {"action": "quest_endpoint", "displayName": "电脑"}}) == "电脑", "世界事件对话标题应使用数据表显示名")
	# 歪脖树使用独立 HUD，不得修改或复用 NPC 菜单的正文状态。
	game.npc_menu_content.visible = false
	game._show_delete_confirm()
	_assert_true(game.tree_confirm_panel.visible and not game.tree_confirm_content.text.is_empty(), "歪脖树独立确认 HUD 不应显示为空白面板")
	_assert_true(not game.npc_menu_content.visible and not game.npc_menu_panel.visible, "歪脖树 HUD 不应复用或改变 NPC 菜单")
	game._close_delete_confirm()
	game.map_context = dark_study_map
	_assert_true(game._npc_occupies_tile(Vector2i(7, 6)), "室内固定 NPC 所在格应阻挡玩家移动")
	_assert_true(not game._npc_occupies_tile(Vector2i(8, 6)), "NPC 碰撞只应占脚下格，不应误挡相邻格")
	game.player_tile = Vector2i(7, 7)
	game.facing = Vector2i.UP
	game._refresh_nearby_npc()
	_assert_true(game.nearby_npc_id == "831434cb-2471-5f24-9fdf-0259fe149eae", "玩家正面紧邻 NPC 时应允许交互")
	game.facing = Vector2i.RIGHT
	game._refresh_nearby_npc()
	_assert_true(game.nearby_npc_id.is_empty(), "NPC 位于玩家侧面时不得触发交互")
	game.nearby_npc_id = "831434cb-2471-5f24-9fdf-0259fe149eae"
	game._interact()
	_assert_true(not game.npc_menu_open, "交互触发前必须重验当前朝向，不得使用旧 NPC 缓存")
	game.move_cooldown = 1.0
	game._apply_facing_input(Vector2.UP)
	_assert_true(game.facing == Vector2i.UP and game.nearby_npc_id == "831434cb-2471-5f24-9fdf-0259fe149eae", "移动冷却期间方向输入也必须立即更新交互朝向")
	game.player_tile = Vector2i(12, 7)
	game.facing = Vector2i.UP
	_assert_true(game._has_front_interactable(), "玩家正面紧邻 Props 时应允许交互")
	game.facing = Vector2i.LEFT
	_assert_true(not game._has_front_interactable(), "Props 位于玩家侧面时不得触发交互")
	var pages: Array[String] = game.dialogue_controller.paginate("第一行\n第二行")
	_assert_true(pages.size() == 2 and pages[0] == "第一行" and pages[1] == "第二行", "对话正文每个逻辑行应独占一页")
	game._show_dialogue("测试", "单页")
	_assert_true(game.dialogue_auto_close_at_msec > 0, "普通单页对话应启用 5 秒自动关闭")
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	game._input(escape_event)
	_assert_true(game.dialogue_open, "ESC 不应关闭原设定中的对话框")
	game.dialogue_auto_close_at_msec = 1
	game.dialogue_controller.update_auto_close()
	_assert_true(not game.dialogue_open, "单页对话到期后应自动关闭")
	game.learning_skill_id = "2224675d-63f2-50e8-a2c6-064acd5c5623"
	game._render_learning_progress()
	var meter: Control = game.learning_progress_widgets[0]
	var view_rect: Rect2 = game._game_view_rect()
	var scale: float = game._display_scale()
	_assert_true(is_equal_approx(meter.position.y, view_rect.position.y + 16.0 * scale), "学习进度条顶部 margin 应为 16px")
	_assert_true(meter.size.x > 200.0 * scale and is_equal_approx(meter.position.x + meter.size.x, view_rect.end.x - 16.0 * scale), "学习进度条应占用房间名右侧至视口右边距的可用空间")
	_assert_true(not Rect2(game.map_badge_panel.position, game.map_badge_panel.size).intersects(Rect2(meter.position, meter.size)), "房间名 HUD 不得与学习进度条重叠")
	var meditation_meter := Control.new()
	game.hud.add_child(meditation_meter)
	game._layout_top_progress_meter(meditation_meter)
	_assert_true(is_equal_approx(meditation_meter.position.y, view_rect.position.y + 16.0 * scale), "冥想进度条顶部 margin 应为 16px")
	_assert_true(meditation_meter.size.x > 200.0 * scale and is_equal_approx(meditation_meter.position.x + meditation_meter.size.x, view_rect.end.x - 16.0 * scale), "冥想进度条应与学习进度条使用相同的加长布局")
	_assert_true(not Rect2(game.map_badge_panel.position, game.map_badge_panel.size).intersects(Rect2(meditation_meter.position, meditation_meter.size)), "房间名 HUD 不得与冥想进度条重叠")

	return game
