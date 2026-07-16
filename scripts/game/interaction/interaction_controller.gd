extends RefCounted
## 地图交互、Props、歪脖树确认与 NPC 浮动菜单。

var game: Node

func _init(owner: Node) -> void:
	game = owner

func _interact() -> void:
	# 不信任跨帧缓存；打开任何交互 HUD 前按玩家当前朝向重新解析目标。
	game._refresh_nearby_npc()
	if game.nearby_npc_id.is_empty():
		if not _interact_prop():
			game.message = "面前没有可交互对象"
	else:
		game.npc_menu_open = true
		game.npc_menu_index = 0
		game.npc_menu_panel.visible = true
		_position_npc_menu()
		_refresh_npc_menu()

func _interact_prop() -> bool:
	if not game.map_context:
		return false
	var object: Dictionary = game.map_context.interactable_object_at_tile(game.player_tile.x + game.facing.x, game.player_tile.y + game.facing.y)
	var properties: Dictionary = object.get("properties", {})
	if object.is_empty() or (str(properties.get("event", "")).is_empty() and str(properties.get("text", "")).is_empty() and str(properties.get("questGiver", "")).is_empty()):
		return false
	var event := str(properties.get("event", ""))
	if event == "drink":
		var vitals: Dictionary = GameState.profile.get("vitals", {})
		var capacity: int = GameState.vitals_capacity()
		var gain := mini(20, maxi(0, capacity - int(vitals.get("water", 0))))
		vitals.water = int(vitals.get("water", 0)) + gain
		GameState.profile.vitals = vitals
		game.message = str(properties.get("text", "你喝了些水。")) + "（饮水 +%d）" % gain
	elif event == "bountyBoard":
		game.message = QuestSystem.bounty_board_text()
	elif event == "deleteSave":
		_show_delete_confirm()
		return true
	elif not str(properties.get("questGiver", "")).is_empty():
		var quest_endpoint := str(properties.get("questGiver", ""))
		var detailed: Dictionary = QuestSystem.begin_novice_completion(quest_endpoint)
		if not detailed.is_empty():
			game.message = str(detailed.get("message", ""))
			var after_last := Callable()
			if bool(detailed.get("can_finish", false)):
				after_last = func() -> String: return QuestSystem.finish_novice_completion(quest_endpoint)
			game._show_dialogue(_prop_display_name(object), game.message, float(detailed.get("lock_seconds", 0.0)), after_last)
			return true
		game.message = QuestSystem.interact_npc(quest_endpoint)
	else:
		game.message = str(properties.get("text", "已查看。"))
	if event != "deleteSave" and (not str(properties.get("text", "")).is_empty() or not str(properties.get("questGiver", "")).is_empty() or event == "bountyBoard"):
		game._show_dialogue(_prop_display_name(object), game.message)
	else:
		game._show_details(game.message)
	return true

func _prop_display_name(object: Dictionary) -> String:
	var properties: Dictionary = object.get("properties", {})
	var display_name := str(properties.get("displayName", "")).strip_edges()
	if display_name.is_empty():
		display_name = str(object.get("name", "")).strip_edges()
	return display_name if not display_name.is_empty() else "告示"

func _show_delete_confirm() -> void:
	game.delete_confirm_open = true
	game.delete_confirm_index = 1
	game.npc_menu_open = false
	game.npc_menu_panel.visible = false
	game.tree_confirm_panel.visible = true
	_layout_delete_confirm()
	_refresh_delete_confirm()

func _layout_delete_confirm() -> void:
	var scale: float = game._display_scale()
	var panel_size: Vector2 = Vector2(360.0, 118.0) * scale
	game.tree_confirm_panel.position = (game.DESIGN_SIZE - panel_size) * 0.5
	game.tree_confirm_panel.size = panel_size
	game.tree_confirm_content.add_theme_font_size_override("font_size", maxi(12, int(round(13.0 * scale))))

func _refresh_delete_confirm() -> void:
	game.tree_confirm_content.text = "这棵歪脖树正合上吊。真要吊死吗？（存档将被删除）\n\n%s    %s" % [game._cursor("吊死", game.delete_confirm_index == 0), game._cursor("再想想", game.delete_confirm_index == 1)]

func _handle_delete_confirm_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		_close_delete_confirm()
	elif key in [KEY_LEFT, KEY_UP]:
		game.delete_confirm_index = 0
		_refresh_delete_confirm()
	elif key in [KEY_RIGHT, KEY_DOWN]:
		game.delete_confirm_index = 1
		_refresh_delete_confirm()
	elif key == KEY_SPACE:
		if game.delete_confirm_index == 0:
			GameState.delete_save()
			game.get_tree().change_scene_to_file("res://scenes/splash.tscn")
		else:
			_close_delete_confirm()

func _close_delete_confirm() -> void:
	game.delete_confirm_open = false
	game.tree_confirm_panel.visible = false

func _has_front_interactable() -> bool:
	if not game.map_context:
		return false
	var object: Dictionary = game.map_context.interactable_object_at_tile(game.player_tile.x + game.facing.x, game.player_tile.y + game.facing.y)
	if object.is_empty():
		return false
	var properties: Dictionary = object.get("properties", {})
	return not str(properties.get("event", "")).is_empty() or not str(properties.get("text", "")).is_empty() or not str(properties.get("questGiver", "")).is_empty()

func _handle_npc_menu_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		game.npc_menu_open = false
		game.npc_menu_panel.visible = false
		_clear_npc_menu_widgets()
		return
	if key == KEY_UP:
		game.npc_menu_index = posmod(game.npc_menu_index - 1, maxi(1, game.npc_menu_actions.size()))
		_refresh_npc_menu()
	elif key == KEY_DOWN:
		game.npc_menu_index = posmod(game.npc_menu_index + 1, maxi(1, game.npc_menu_actions.size()))
		_refresh_npc_menu()
	elif key == KEY_SPACE:
		game.npc_world_controller.select_menu_action()
		if game.npc_menu_open:
			_refresh_npc_menu()
	return

func _refresh_npc_menu() -> void:
	game.npc_menu_panel.visible = true
	var npc: Dictionary = NpcSystem.build_instance(game.nearby_npc_id)
	var roles: Array = npc.get("roles", [])
	if "static" in roles:
		game.npc_menu_actions.assign(["view"])
		game.npc_menu_labels.assign(["查看"])
		game.npc_menu_index = 0
	else:
		game.npc_menu_actions.assign(["talk", "view", "spar", "fight"])
		game.npc_menu_labels.assign(["交谈", "查看", "切磋", "战斗"])
		if "vendor" in roles:
			game.npc_menu_actions.append(game.TRADE_MODE_BUY)
			game.npc_menu_labels.append("购买")
		if "pawn" in roles:
			game.npc_menu_actions.append(game.TRADE_MODE_SELL)
			game.npc_menu_labels.append("典当")
		var teach_options := SkillSystem.learn_options_for_npc(game.nearby_npc_id)
		if SkillSystem.can_join(game.nearby_npc_id):
			game.npc_menu_actions.append("join")
			game.npc_menu_labels.append("拜师")
		if not teach_options.is_empty():
			game.npc_menu_actions.append("learn")
			game.npc_menu_labels.append("学习")
	game.npc_menu_index = clampi(game.npc_menu_index, 0, maxi(0, game.npc_menu_actions.size() - 1))
	_render_npc_menu_widgets()
	_position_npc_menu()

func _clear_npc_menu_widgets() -> void:
	for widget in game.npc_menu_widgets:
		if is_instance_valid(widget):
			widget.free()
	game.npc_menu_widgets.clear()

func _close_npc_menu() -> void:
	game.npc_menu_open = false
	game.npc_menu_panel.visible = false
	_clear_npc_menu_widgets()

func _render_npc_menu_widgets() -> void:
	# 浮动菜单保持紧凑，由 _position_npc_menu() 根据人物可见精灵矩形选择摆放位置。
	_clear_npc_menu_widgets()
	game.npc_menu_content.visible = false
	var scale: float = game._display_scale()
	var row_height: float = 27.0 * scale
	var panel_width: float = 92.0 * scale
	var panel_padding: float = 3.0 * scale
	game.npc_menu_panel.size = Vector2(panel_width, panel_padding * 2.0 + row_height * game.npc_menu_labels.size())
	for index in game.npc_menu_labels.size():
		var row: Control = Panel.new()
		row.position = game.npc_menu_panel.position + Vector2(panel_padding, panel_padding + row_height * index)
		row.size = Vector2(panel_width - panel_padding * 2.0, row_height)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.z_index = game.npc_menu_panel.z_index + 1
		if index == game.npc_menu_index:
			row.add_theme_stylebox_override("panel", game._ui_box(Color(1, 1, 1, 0), Color("cf3b24"), 3))
		game.hud.add_child(row)
		game.npc_menu_widgets.append(row)

		var label: Label = Label.new()
		label.text = game.npc_menu_labels[index]
		label.position = row.position
		label.size = row.size
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = game.npc_menu_panel.z_index + 2
		label.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
		label.add_theme_font_size_override("font_size", maxi(12, int(round(15.0 * scale))))
		label.add_theme_color_override("font_color", Color("302f2b"))
		game.hud.add_child(label)
		game.npc_menu_widgets.append(label)

func _position_npc_menu() -> void:
	if not game.npc_menu_panel or not game.map_context or game.nearby_npc_id.is_empty():
		return
	var npc_tile: Vector2 = game.player_tile + game.facing
	for object in game.map_context.npc_objects():
		var properties: Dictionary = object.get("properties", {})
		if str(properties.get("npcId", "")) == game.nearby_npc_id:
			npc_tile = Vector2i(int(floor(float(object.get("x", 0)) / game.map_context.tile_width)), int(floor(float(object.get("y", 0)) / game.map_context.tile_height)))
			break
	var npc_world_position := Vector2(npc_tile) * Vector2(game.map_context.tile_width, game.map_context.tile_height)
	var npc_screen_position: Vector2 = game._world_to_screen(npc_world_position)
	var npc_source := NpcSystem.sprite_region(game.nearby_npc_id)
	var render_scale: float = game._render_scale()
	var npc_rect := Rect2(
		npc_screen_position + Vector2(1.0, -npc_source.size.y + 16.0) * render_scale,
		npc_source.size * render_scale,
	)
	var menu_size: Vector2 = game.npc_menu_panel.size
	var view_rect: Rect2 = game._game_view_rect()
	var gap: float = 6.0 * game._display_scale()
	var inset: float = 4.0 * game._display_scale()
	var candidates: Array[Vector2] = [
		Vector2(npc_rect.end.x + gap, npc_rect.position.y),
		Vector2(npc_rect.position.x - menu_size.x - gap, npc_rect.position.y),
		Vector2(npc_rect.end.x + gap, npc_rect.end.y - menu_size.y),
		Vector2(npc_rect.position.x - menu_size.x - gap, npc_rect.end.y - menu_size.y),
	]
	var menu_position: Vector2 = candidates[0]
	for candidate in candidates:
		var candidate_rect := Rect2(candidate, menu_size)
		if view_rect.encloses(candidate_rect):
			menu_position = candidate
			break
	var min_position: Vector2 = view_rect.position + Vector2(inset, inset)
	var max_position: Vector2 = view_rect.end - menu_size - Vector2(inset, inset)
	game.npc_menu_panel.position = Vector2(
		clampf(menu_position.x, min_position.x, max_position.x),
		clampf(menu_position.y, min_position.y, max_position.y),
	)
	_sync_npc_menu_widgets()

func _sync_npc_menu_widgets() -> void:
	if game.npc_menu_widgets.is_empty():
		return
	var scale: float = game._display_scale()
	var row_height: float = 27.0 * scale
	var panel_padding: float = 3.0 * scale
	for index in game.npc_menu_labels.size():
		var row_index: int = index * 2
		if row_index + 1 >= game.npc_menu_widgets.size():
			break
		var row_position: Vector2 = game.npc_menu_panel.position + Vector2(panel_padding, panel_padding + row_height * index)
		var row: Control = game.npc_menu_widgets[row_index]
		var label: Label = game.npc_menu_widgets[row_index + 1]
		row.position = row_position
		label.position = row_position
