extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state: Node = root.get_node("GameState")
	var data_registry: Node = root.get_node("DataRegistry")
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if not game.map_context or game.map_context.tilesets.size() < 2:
		push_error("Scene did not load a rendered TMX map")
		quit(1)
		return
	var spawn: Dictionary = game.map_context.spawn_point()
	if spawn.is_empty():
		push_error("Scene did not load a map SpawnPoint")
		quit(1)
		return
	var expected_spawn := Vector2i(int(floor(float(spawn.get("x", 0)) / game.map_context.tile_width)), int(floor(float(spawn.get("y", 0)) / game.map_context.tile_height)))
	if game.player_tile != expected_spawn:
		push_error("Player did not start at map SpawnPoint")
		quit(1)
		return
	var paused_tile: Vector2i = game.player_tile
	var paused_time: float = state.game_time_sec
	game.virtual_direction = Vector2.RIGHT
	game._show_details("暂停世界验证")
	game._process(1.0)
	if game.player_tile != paused_tile or state.game_time_sec != paused_time:
		push_error("World simulation advanced while a HUD was open")
		quit(1)
		return
	game.details_panel.visible = false
	game.virtual_direction = Vector2.ZERO
	game._show_profile_panel()
	if game.details_widgets.is_empty():
		push_error("Profile HUD did not build its two-column layout")
		quit(1)
		return
	game.details_panel.visible = false
	game._show_skill_book()
	if game.details_widgets.is_empty():
		push_error("Skill HUD did not build its two-pane layout")
		quit(1)
		return
	game.details_panel.visible = false
	# PlayerHome keeps both directions at its door. The arrival-only tile must
	# not trigger a return trip; the departure tile must still leave the house.
	if game.map_context.map_id == "PlayerHome":
		game.player_tile = Vector2i(6, 13)
		game._try_map_transition()
		await create_timer(0.35).timeout
		if game.map_context.map_id != "PlayerHome":
			push_error("Arrival transaction immediately returned the player home")
			quit(1)
			return
		game.player_tile = Vector2i(6, 14)
		game._try_map_transition()
		await create_timer(0.4).timeout
		if game.map_context.map_id != "KaiyuanTown":
			push_error("PlayerHome departure transaction did not reach KaiyuanTown")
			quit(1)
			return
	if not game._has_front_interactable() and game.nearby_npc_id.is_empty():
		# PlayerHome is the real SpawnPoint map and intentionally has no NPC;
		# use a registered NPC id to exercise the menu state machine below.
		game.nearby_npc_id = "nai_cha_mei_mei"
	game._interact()
	if not game.npc_menu_open:
		push_error("NPC interaction menu did not open")
		quit(1)
		return
	game._handle_npc_menu_key(KEY_DOWN)
	if game.npc_menu_index != 1 or not game.npc_menu_widgets[2].has_theme_stylebox_override("panel"):
		push_error("NPC interaction menu did not move selection down")
		quit(1)
		return
	game._handle_npc_menu_key(KEY_UP)
	if game.npc_menu_index != 0 or not game.npc_menu_widgets[0].has_theme_stylebox_override("panel"):
		push_error("NPC interaction menu did not move selection up")
		quit(1)
		return
	game._select_npc_menu()
	if not game.details_panel.visible:
		push_error("NPC detail panel did not open")
		quit(1)
		return
	game.npc_menu_open = true
	game.nearby_npc_id = "nai_cha_mei_mei"
	game._refresh_npc_menu()
	game.npc_menu_index = game.npc_menu_labels.find("购买")
	if game.npc_menu_index < 0:
		push_error("Dynamic NPC menu did not expose vendor purchase action")
		quit(1)
		return
	game._select_npc_menu()
	if not game.trade_open:
		push_error("NPC trade list did not open")
		quit(1)
		return
	game._handle_trade_key(KEY_ESCAPE)
	game.npc_menu_open = true
	game.nearby_npc_id = "douglas_crockford"
	state.profile.sect = "香草派"
	state.profile.master = "douglas_crockford"
	game._refresh_npc_menu()
	game.npc_menu_index = game.npc_menu_labels.find("学习")
	if game.npc_menu_index < 0:
		push_error("Dynamic NPC menu did not expose learning action")
		quit(1)
		return
	game._select_npc_menu()
	if not game.learn_open:
		push_error("NPC learning list did not open")
		quit(1)
		return
	game._handle_learn_key(KEY_ESCAPE)
	game._show_inventory()
	if not game.inventory_open:
		push_error("Inventory panel did not open")
		quit(1)
		return
	if game.details_widgets.is_empty():
		push_error("Inventory HUD did not build its two-pane layout")
		quit(1)
		return
	game._handle_inventory_key(KEY_ESCAPE)
	game._show_dialogue("测试 NPC", "这是一段足够长的对话文本，用来验证 Godot 版本已经具备旧项目的分页对话行为。第二句继续扩展文本长度，确保会产生多个页面。这里再补充一段内容，模拟旧项目中较长的 NPC 任务说明与奖励描述。")
	if not game.dialogue_open or game.dialogue_pages.size() < 2:
		push_error("Dialogue did not paginate")
		quit(1)
		return
	game._advance_dialogue()
	if not game.dialogue_open:
		push_error("Dialogue closed before final page")
		quit(1)
		return
	while game.dialogue_open:
		game._advance_dialogue()
	if game.dialogue_open:
		push_error("Dialogue did not close after final page")
		quit(1)
		return
	game._toggle_menu()
	game.menu_index = 3
	game._select_menu()
	if not game.system_open:
		push_error("System submenu did not open")
		quit(1)
		return
	game._handle_menu_key(KEY_DOWN)
	game._handle_menu_key(KEY_ESCAPE)
	if game.system_open:
		push_error("System submenu did not close")
		quit(1)
		return
	game._toggle_menu()
	game._start_battle()
	if not game.battle_active:
		push_error("Scene did not start NPC battle")
		quit(1)
		return
	game._end_battle("smoke exit")
	if game.battle_active:
		push_error("Battle did not exit")
		quit(1)
		return
	var previous_map: String = game.map_context.map_id
	game._load_map((game.map_index + 1) % data_registry.map_files.size(), previous_map, false)
	await create_timer(0.4).timeout
	if game.map_transitioning or not game.map_context:
		push_error("Map transition did not settle")
		quit(1)
		return
	print("FrontendLegends scene smoke test passed")
	quit(0)
