extends RefCounted
## 赛博传送资格、费用、目的地状态与输入；HUD 几何仍由 Game 布局接口负责。

var game: Node

func _init(owner: Node) -> void:
	game = owner

func try_open() -> void:
	var basic_tune_id := SkillSystem.equipped_id("tune", "basic")
	if SkillSystem.level(basic_tune_id) < game.CYBER_TELEPORT_SKILL_REQUIREMENT or SkillSystem.equipped_sect_skill_level("tune") < game.CYBER_TELEPORT_SKILL_REQUIREMENT:
		game.message = "赛博传送需要装备的基础轻功与特殊轻功均达到 30 级。"
		game._close_menu()
		game._show_dialogue("赛博传送", game.message)
		return
	var teleport_cost := cost()
	if int(GameState.combat_state.mp) < teleport_cost:
		game.message = "精力不足，赛博传送需要 %d 点精力。" % teleport_cost
		game._close_menu()
		game._show_dialogue("赛博传送", game.message)
		return
	game.cyber_maps.clear()
	for index in DataRegistry.map_files.size():
		var map_id := DataRegistry.map_files[index].get_file().get_basename()
		if DataRegistry.map_type(map_id) != "inDoor":
			game.cyber_maps.append(index)
	if game.cyber_maps.is_empty():
		game.message = "暂无可传送的野外地图。"
		game._close_menu()
		game._show_dialogue("赛博传送", game.message)
		return
	game.cyber_open = true
	game.cyber_index = 0
	game.system_open = false
	game.skill_open = false
	game._refresh_menu()
	refresh_menu(teleport_cost)

func handle_key(key: Key) -> void:
	var teleport_cost := cost()
	if key == KEY_ESCAPE:
		game.cyber_open = false
		game.details_panel.visible = false
		game.menu_open = true
		game.menu_panel.visible = true
		game.menu_index = 3
		game.system_open = true
		game.system_index = 0
		game._refresh_menu()
		return
	if key == KEY_UP:
		game.cyber_index = posmod(game.cyber_index - 1, game.cyber_maps.size())
	elif key == KEY_DOWN:
		game.cyber_index = posmod(game.cyber_index + 1, game.cyber_maps.size())
	elif key == KEY_SPACE:
		if int(GameState.combat_state.mp) < teleport_cost:
			game.message = "精力不足，赛博传送需要 %d 点精力。" % teleport_cost
		else:
			GameState.combat_state.mp -= teleport_cost
			GameState.advance_time(1.0)
			var destination: int = game.cyber_maps[game.cyber_index]
			game.cyber_open = false
			game.details_panel.visible = false
			game._close_menu()
			game._load_map(destination, game.map_context.map_id if game.map_context else "", true)
			game.message = "赛博传送完成，消耗 %d 精力" % teleport_cost
			return
	if game.cyber_open:
		refresh_menu(teleport_cost)

func cost() -> int:
	var maximum := GameState.player_mp_max()
	return maxi(1, int(ceil(float(maximum) / 3.0))) if maximum > 0 else 0

func refresh_menu(teleport_cost: int) -> void:
	if game.active_detail_hud != "cyber" or not game.detail_huds.cyber.panel.visible:
		game._use_detail_hud("cyber")
	if not is_instance_valid(game.cyber_selection_widget) or game.cyber_labels.size() != game.cyber_maps.size():
		build_menu()
	else:
		game._layout_cyber_widgets()
	game.message = "↑↓选择目的地　空格确认　ESC返回　消耗 %d 精力" % teleport_cost
	game._set_menu_hint("赛博传送", game.message)

func build_menu() -> void:
	game.details_content.visible = true
	game.details_content.text = ""
	game._clear_details_widgets()
	game.cyber_labels.clear()
	game._layout_cyber_panel()
	for position in game.cyber_maps.size():
		var index: int = game.cyber_maps[position]
		var map_id := DataRegistry.map_files[index].get_file().get_basename()
		var label: Label = game._detail_label(DataRegistry.map_display_name(map_id), Rect2(), 13, HORIZONTAL_ALIGNMENT_CENTER)
		game.cyber_labels.append(label)
	game.cyber_selection_widget = Panel.new()
	game.cyber_selection_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.cyber_selection_widget.add_theme_stylebox_override("panel", game._ui_box(Color(1, 1, 1, 0), Color(0.78, 0.12, 0.06, 1), 2))
	game.details_content.add_child(game.cyber_selection_widget)
	game.details_widgets.append(game.cyber_selection_widget)
	game._layout_cyber_widgets()
