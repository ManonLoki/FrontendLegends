extends Node2D

const VIRTUAL_CONTROLS := preload("res://scripts/virtual_controls.gd")
const MOBILE_ORIENTATION := preload("res://scripts/mobile_orientation.gd")
const CAMERA_SIZE := Vector2(320.0, 320.0)
const DESIGN_SIZE := Vector2(640.0, 480.0)

var player_tile := Vector2i(8, 5)
var facing := Vector2i.RIGHT
var move_cooldown := 0.0
var message := "欢迎来到开源镇"
@onready var map_renderer: TiledMapRenderer = $MapRenderer
@onready var map_badge_panel: PanelContainer = $HUD/MapBadge
@onready var map_badge: Label = $HUD/MapBadge/Content
@onready var transition_overlay: ColorRect = $HUD/Transition
@onready var hud: CanvasLayer = $HUD
@onready var menu_panel: PanelContainer = $HUD/Menu
@onready var menu_content: Label = $HUD/Menu/Content
@onready var battle_panel: PanelContainer = $HUD/Battle
@onready var battle_content: Label = $HUD/Battle/Content
@onready var details_panel: PanelContainer = $HUD/Details
@onready var details_content: Label = $HUD/Details/Content
@onready var npc_portrait: TextureRect = $HUD/Details/Content/Portrait
@onready var dialogue_panel: PanelContainer = $HUD/Dialogue
@onready var dialogue_content: Label = $HUD/Dialogue/Content
@onready var npc_menu_panel: PanelContainer = $HUD/NpcMenu
@onready var npc_menu_content: Label = $HUD/NpcMenu/Content
var nearby_npc_id := ""
var map_context: TiledMapLoader
var menu_open := false
var menu_index := 0
var system_open := false
var system_index := 0
var skill_open := false
var skill_index := 0
var menu_widgets: Array[Control] = []
var details_widgets: Array[Control] = []
var profile_panel_open := false
var npc_view_panel_open := false
var battle_active := false
var battle_enemy: Dictionary = {}
var battle_enemy_hp := 0
var battle_session: Dictionary = {}
var battle_lethal := true
var battle_submenu := ""
var battle_submenu_index := 0
var battle_submenu_items: Array = []
var cyber_open := false
var cyber_index := 0
var cyber_maps: Array[int] = []
var npc_menu_open := false
var npc_menu_index := 0
var npc_menu_actions: Array[String] = []
var npc_menu_labels: Array[String] = []
var npc_menu_widgets: Array[Control] = []
var trade_open := false
var trade_mode := "buy"
var trade_index := 0
var trade_items: Array = []
var trade_all_items: Array = []
var trade_categories: Array[String] = []
var trade_category_index := 0
var trade_focus_category := true
var learn_open := false
var learn_index := 0
var learn_items: Array[String] = []
var learn_all_items: Array[String] = []
var learn_categories: Array[String] = []
var learn_category_index := 0
var learn_focus_category := true
var inventory_open := false
var inventory_items: Array[String] = []
var inventory_categories: Array[String] = ["食物", "药物", "武器", "防具", "鞋子", "饰品", "其他", "丢弃"]
var inventory_category_index := 0
var inventory_index := 0
var inventory_focus_category := true
var practice_open := false
var practice_index := 0
var practice_items: Array[String] = []
var skill_book_open := false
var skill_book_categories: Array[String] = ["编码", "思维", "架构", "招架", "灵感"]
var skill_book_category_index := 0
var skill_book_focus_category := true
var skill_book_items: Array[String] = []
var skill_book_index := 0
var SKILL_BOOK_THEMES: Array[String] = ["code", "tune", "arch", "parry", "knowledge"]
var dialogue_open := false
var dialogue_pages: Array[String] = []
var dialogue_page_index := 0
var dialogue_speaker := ""
var dialogue_locked_until_msec := 0
var map_transitioning := false
var has_loaded_map := false
var delete_confirm_open := false
var delete_confirm_index := 1
const NPC_MENU_ITEMS := ["交谈", "查看", "切磋", "战斗", "购买", "典当", "拜师", "学习"]
var map_index := 0
var player_texture: Texture2D = preload("res://assets/Texture/player.png")
var npc_texture: Texture2D = preload("res://assets/Texture/NPC.png")
var player_sprite_regions: Dictionary = {}
var animation_timer := 0.0
var animation_frame := 0
var player_moving := false
var virtual_direction := Vector2.ZERO
var accept_requested := false
var cancel_requested := false
var auto_save_timer := 0.0
const MENU_ITEMS := ["查看", "背包", "技能", "系统"]
const SKILL_ITEMS := ["冥想", "练功", "加力", "功法"]
const SYSTEM_ITEMS := ["赛博传送", "摸鱼", "疗伤", "保存", "退出"]

func _ready() -> void:
	MOBILE_ORIENTATION.apply()
	_install_virtual_controls()
	_apply_hud_theme()
	_load_player_sprite_regions()
	get_viewport().size_changed.connect(_layout_game_view)
	_layout_game_view()
	menu_content.text = ""
	_load_initial_map()
	queue_redraw()

func _process(delta: float) -> void:
	# Re-sync HUD panel geometry every frame instead of relying solely on the
	# viewport size_changed signal, which can miss web/mobile resizes that happen
	# after _ready() (e.g. fullscreen-on-gesture in mobile_orientation.gd) and
	# leave panels frozen at a stale size/position from an earlier viewport reading.
	_layout_game_view()
	# HUDs are modal: freeze world simulation, including the player's held direction,
	# while menus, dialogue, battle, or detail panels are visible.
	if _has_modal_input():
		player_moving = false
		virtual_direction = Vector2.ZERO
		return
	move_cooldown -= delta
	animation_timer += delta
	if animation_timer >= 0.15 and player_moving:
		animation_timer = 0.0
		animation_frame = (animation_frame + 1) % 6
		queue_redraw()
	elif not player_moving and animation_frame != 0:
		animation_timer = 0.0
		animation_frame = 0
		queue_redraw()
	GameState.advance_time(delta)
	auto_save_timer += delta
	if auto_save_timer >= 30.0:
		auto_save_timer = 0.0
		GameState.save_game()
	NpcSystem.sweep_defeated()
	if map_transitioning:
		player_moving = false
		return
	if npc_menu_open:
		_position_npc_menu()
	if move_cooldown <= 0.0:
		var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") + virtual_direction
		if direction.length() > 0.0:
			player_moving = true
			var step := Vector2i(signi(int(direction.x)), signi(int(direction.y)))
			if step.x != 0: step.y = 0
			# Turn to face the pressed direction immediately, even if the tile
			# ahead turns out to be blocked (e.g. by an NPC) — otherwise the
			# early return below skips facing/sprite updates entirely and the
			# player can never turn toward a stationary NPC to interact with it.
			if facing != step:
				facing = step
				_refresh_nearby_npc()
				queue_redraw()
			var next_tile := player_tile + step
			if map_context and not map_context.is_walkable(next_tile.x, next_tile.y):
				message = "前方不可通行"
				_refresh_status()
				return
			player_tile = next_tile
			_refresh_nearby_npc()
			_try_map_transition()
			move_cooldown = 0.15
			message = "当前位置: %s" % player_tile
			_update_camera()
			queue_redraw()
		else:
			player_moving = false
	if accept_requested:
		accept_requested = false
		if not nearby_npc_id.is_empty() or _has_front_interactable():
			_interact()
		elif not menu_open and not battle_active:
			_start_battle()
	if cancel_requested:
		cancel_requested = false
		if battle_active:
			_end_battle("你离开了战斗")
		else:
			_toggle_menu()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		MOBILE_ORIENTATION.request_from_user_gesture()
		if map_transitioning:
			return
		if delete_confirm_open:
			_handle_delete_confirm_key(event.keycode)
			return
		if dialogue_open:
			if event.keycode == KEY_SPACE:
				if Time.get_ticks_msec() < dialogue_locked_until_msec:
					return
				_advance_dialogue()
			elif event.keycode == KEY_ESCAPE:
				_close_dialogue()
			return
		if trade_open:
			_handle_trade_key(event.keycode)
			return
		if inventory_open:
			_handle_inventory_key(event.keycode)
			return
		if learn_open:
			_handle_learn_key(event.keycode)
			return
		if practice_open:
			_handle_practice_key(event.keycode)
			return
		if skill_book_open:
			_handle_skill_book_key(event.keycode)
			return
		if cyber_open:
			_handle_cyber_key(event.keycode)
			return
		if npc_menu_open:
			_handle_npc_menu_key(event.keycode)
			return
		if battle_active:
			if not battle_submenu.is_empty():
				_handle_battle_submenu_key(event.keycode)
			else:
				_handle_battle_key(event.keycode)
			return
		if details_panel.visible:
			if event.keycode == KEY_ESCAPE:
				details_panel.visible = false
			return
		if menu_open:
			_handle_menu_key(event.keycode)
			return
		if event.keycode == KEY_SPACE:
			accept_requested = true
		elif event.keycode == KEY_ESCAPE:
			cancel_requested = true

func _install_virtual_controls() -> void:
	var controls = VIRTUAL_CONTROLS.new()
	add_child(controls)
	controls.key_down.connect(_on_virtual_key_down)
	controls.key_up.connect(_on_virtual_key_up)

func _on_virtual_key_down(keycode: int) -> void:
	if keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and not _has_modal_input():
		if keycode == KEY_UP: virtual_direction.y = -1.0
		elif keycode == KEY_DOWN: virtual_direction.y = 1.0
		elif keycode == KEY_LEFT: virtual_direction.x = -1.0
		elif keycode == KEY_RIGHT: virtual_direction.x = 1.0
		return
	_dispatch_virtual_key(keycode)

func _on_virtual_key_up(keycode: int) -> void:
	if keycode == KEY_UP or keycode == KEY_DOWN:
		virtual_direction.y = 0.0
	elif keycode == KEY_LEFT or keycode == KEY_RIGHT:
		virtual_direction.x = 0.0

func _has_modal_input() -> bool:
	return delete_confirm_open or dialogue_open or trade_open or inventory_open or learn_open or practice_open or skill_book_open or cyber_open or npc_menu_open or battle_active or menu_open or details_panel.visible or dialogue_panel.visible

func _dispatch_virtual_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_input(event)

func _interact() -> void:
	if nearby_npc_id.is_empty():
		if not _interact_prop():
			message = "面前没有可交互对象"
			_refresh_status()
	else:
		npc_menu_open = true
		npc_menu_index = 0
		npc_menu_panel.visible = true
		_position_npc_menu()
		_refresh_npc_menu()

func _interact_prop() -> bool:
	if not map_context:
		return false
	var object: Dictionary = map_context.interactable_object_at_tile(player_tile.x + facing.x, player_tile.y + facing.y)
	var properties: Dictionary = object.get("properties", {})
	if object.is_empty() or (str(properties.get("event", "")).is_empty() and str(properties.get("text", "")).is_empty() and str(properties.get("questGiver", "")).is_empty()):
		return false
	var event := str(properties.get("event", ""))
	if event == "drink":
		var vitals: Dictionary = GameState.profile.get("vitals", {})
		var capacity := 200 + int(GameState.profile.get("attributes", {}).get("strength", 25)) * 10
		var gain := mini(20, maxi(0, capacity - int(vitals.get("water", 0))))
		vitals.water = int(vitals.get("water", 0)) + gain
		GameState.profile.vitals = vitals
		message = str(properties.get("text", "你喝了些水。")) + "（饮水 +%d）" % gain
	elif event == "bountyBoard":
		message = QuestSystem.bounty_board_text()
	elif event == "deleteSave":
		_show_delete_confirm()
		return true
	elif not str(properties.get("questGiver", "")).is_empty():
		message = QuestSystem.interact_npc(str(properties.get("questGiver", "")))
	else:
		message = str(properties.get("text", "已查看。"))
	if event != "deleteSave" and (not str(properties.get("text", "")).is_empty() or not str(properties.get("questGiver", "")).is_empty() or event == "bountyBoard"):
		_show_dialogue(str(properties.get("displayName", "告示")), message, 5.0 if not str(properties.get("questGiver", "")).is_empty() else 0.0)
	else:
		_show_details(message)
	_refresh_status()
	return true

func _show_delete_confirm() -> void:
	delete_confirm_open = true
	delete_confirm_index = 1
	npc_menu_open = false
	npc_menu_panel.visible = true
	_layout_delete_confirm()
	_refresh_delete_confirm()

func _layout_delete_confirm() -> void:
	var scale := _display_scale()
	var panel_size := Vector2(360.0, 118.0) * scale
	npc_menu_panel.position = (get_viewport_rect().size - panel_size) * 0.5
	npc_menu_panel.size = panel_size
	npc_menu_content.add_theme_font_size_override("font_size", maxi(12, int(round(13.0 * scale))))
	npc_menu_content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	npc_menu_content.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _refresh_delete_confirm() -> void:
	npc_menu_content.text = "这棵歪脖树正合上吊。真要吊死吗？（存档将被删除）\n\n%s    %s" % [_cursor("吊死", delete_confirm_index == 0), _cursor("再想想", delete_confirm_index == 1)]

func _handle_delete_confirm_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		_close_delete_confirm()
	elif key in [KEY_LEFT, KEY_UP]:
		delete_confirm_index = 0
		_refresh_delete_confirm()
	elif key in [KEY_RIGHT, KEY_DOWN]:
		delete_confirm_index = 1
		_refresh_delete_confirm()
	elif key == KEY_SPACE:
		if delete_confirm_index == 0:
			GameState.delete_save()
			get_tree().change_scene_to_file("res://scenes/splash.tscn")
		else:
			_close_delete_confirm()

func _close_delete_confirm() -> void:
	delete_confirm_open = false
	npc_menu_panel.visible = false
	npc_menu_content.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	npc_menu_content.vertical_alignment = VERTICAL_ALIGNMENT_TOP

func _has_front_interactable() -> bool:
	if not map_context:
		return false
	var object: Dictionary = map_context.interactable_object_at_tile(player_tile.x + facing.x, player_tile.y + facing.y)
	if object.is_empty():
		return false
	var properties: Dictionary = object.get("properties", {})
	return not str(properties.get("event", "")).is_empty() or not str(properties.get("text", "")).is_empty() or not str(properties.get("questGiver", "")).is_empty()

func _handle_npc_menu_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		npc_menu_open = false
		npc_menu_panel.visible = false
		_clear_npc_menu_widgets()
		return
	if key == KEY_UP:
		npc_menu_index = posmod(npc_menu_index - 1, maxi(1, npc_menu_actions.size()))
		_refresh_npc_menu()
	elif key == KEY_DOWN:
		npc_menu_index = posmod(npc_menu_index + 1, maxi(1, npc_menu_actions.size()))
		_refresh_npc_menu()
	elif key == KEY_SPACE:
		_select_npc_menu()
		if npc_menu_open:
			_refresh_npc_menu()
	return

func _refresh_npc_menu() -> void:
	var npc: Dictionary = NpcSystem.build_instance(nearby_npc_id)
	var roles: Array = npc.get("roles", [])
	if "static" in roles:
		npc_menu_actions = ["view"]
		npc_menu_labels = ["查看"]
		npc_menu_index = 0
	else:
		npc_menu_actions = ["talk", "view", "spar", "fight"]
		npc_menu_labels = ["交谈", "查看", "切磋", "战斗"]
		if "vendor" in roles:
			npc_menu_actions.append("buy")
			npc_menu_labels.append("购买")
		if "pawn" in roles:
			npc_menu_actions.append("sell")
			npc_menu_labels.append("典当")
		var teach_options := SkillSystem.learn_options_for_npc(nearby_npc_id)
		if SkillSystem.can_join(nearby_npc_id):
			npc_menu_actions.append("join")
			npc_menu_labels.append("拜师")
		if not teach_options.is_empty():
			npc_menu_actions.append("learn")
			npc_menu_labels.append("学习")
	npc_menu_index = clampi(npc_menu_index, 0, maxi(0, npc_menu_actions.size() - 1))
	_render_npc_menu_widgets()
	_position_npc_menu()

func _clear_npc_menu_widgets() -> void:
	for widget in npc_menu_widgets:
		if is_instance_valid(widget):
			widget.free()
	npc_menu_widgets.clear()

func _close_npc_menu() -> void:
	npc_menu_open = false
	npc_menu_panel.visible = false
	_clear_npc_menu_widgets()

func _render_npc_menu_widgets() -> void:
	# Keep this menu small enough to sit beside the NPC. Its position is chosen
	# from the NPC's visible sprite rect in _position_npc_menu().
	_clear_npc_menu_widgets()
	npc_menu_content.visible = false
	var scale := _display_scale()
	var row_height := 27.0 * scale
	var panel_width := 92.0 * scale
	var panel_padding := 3.0 * scale
	npc_menu_panel.size = Vector2(panel_width, panel_padding * 2.0 + row_height * npc_menu_labels.size())
	for index in npc_menu_labels.size():
		var row := Panel.new()
		row.position = npc_menu_panel.position + Vector2(panel_padding, panel_padding + row_height * index)
		row.size = Vector2(panel_width - panel_padding * 2.0, row_height)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.z_index = npc_menu_panel.z_index + 1
		if index == npc_menu_index:
			row.add_theme_stylebox_override("panel", _ui_box(Color(1, 1, 1, 0), Color("cf3b24"), 3))
		hud.add_child(row)
		npc_menu_widgets.append(row)

		var label := Label.new()
		label.text = npc_menu_labels[index]
		label.position = row.position
		label.size = row.size
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.z_index = npc_menu_panel.z_index + 2
		label.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
		label.add_theme_font_size_override("font_size", maxi(12, int(round(15.0 * scale))))
		label.add_theme_color_override("font_color", Color("302f2b"))
		hud.add_child(label)
		npc_menu_widgets.append(label)

func _position_npc_menu() -> void:
	if not npc_menu_panel or not map_context or nearby_npc_id.is_empty():
		return
	var npc_tile := player_tile + facing
	for object in map_context.npc_objects():
		var properties: Dictionary = object.get("properties", {})
		if str(properties.get("npcId", "")) == nearby_npc_id:
			npc_tile = Vector2i(int(floor(float(object.get("x", 0)) / map_context.tile_width)), int(floor(float(object.get("y", 0)) / map_context.tile_height)))
			break
	var npc_world_position := Vector2(npc_tile) * Vector2(map_context.tile_width, map_context.tile_height)
	var npc_screen_position := _world_to_screen(npc_world_position)
	var npc_source := NpcSystem.sprite_region(nearby_npc_id)
	var render_scale := _render_scale()
	var npc_rect := Rect2(
		npc_screen_position + Vector2(1.0, -npc_source.size.y + 16.0) * render_scale,
		npc_source.size * render_scale,
	)
	var menu_size := npc_menu_panel.size
	var view_rect := _game_view_rect()
	var gap := 6.0 * _display_scale()
	var inset := 4.0 * _display_scale()
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
	var min_position := view_rect.position + Vector2(inset, inset)
	var max_position := view_rect.end - menu_size - Vector2(inset, inset)
	npc_menu_panel.position = Vector2(
		clampf(menu_position.x, min_position.x, max_position.x),
		clampf(menu_position.y, min_position.y, max_position.y),
	)
	_sync_npc_menu_widgets()

func _sync_npc_menu_widgets() -> void:
	if npc_menu_widgets.is_empty():
		return
	var scale := _display_scale()
	var row_height := 27.0 * scale
	var panel_padding := 3.0 * scale
	for index in npc_menu_labels.size():
		var row_index := index * 2
		if row_index + 1 >= npc_menu_widgets.size():
			break
		var row_position := npc_menu_panel.position + Vector2(panel_padding, panel_padding + row_height * index)
		var row := npc_menu_widgets[row_index]
		var label := npc_menu_widgets[row_index + 1]
		row.position = row_position
		label.position = row_position

func _handle_trade_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		if trade_focus_category:
			trade_open = false
			npc_menu_open = true
			_refresh_npc_menu()
		else:
			trade_focus_category = true
			_refresh_trade_items()
	elif key == KEY_LEFT:
		trade_focus_category = true
		_refresh_trade_items()
	elif trade_focus_category and key in [KEY_UP, KEY_DOWN]:
		var delta := -1 if key == KEY_UP else 1
		trade_category_index = posmod(trade_category_index + delta, maxi(1, trade_categories.size()))
		_refresh_trade_items()
	elif trade_focus_category and key in [KEY_RIGHT, KEY_SPACE]:
		if not trade_items.is_empty():
			trade_focus_category = false
			trade_index = 0
			_refresh_trade_list()
	elif not trade_focus_category and key == KEY_UP:
		trade_index = posmod(trade_index - 1, maxi(1, trade_items.size()))
		_refresh_trade_list()
	elif not trade_focus_category and key == KEY_DOWN:
		trade_index = posmod(trade_index + 1, maxi(1, trade_items.size()))
		_refresh_trade_list()
	elif not trade_focus_category and key == KEY_SPACE:
		if not trade_items.is_empty():
			var item_id := str(trade_items[trade_index])
			var result: Dictionary = InventorySystem.buy_item(nearby_npc_id, item_id) if trade_mode == "buy" else InventorySystem.sell_item(item_id)
			message = result.message
			_rebuild_trade_categories()
	_refresh_trade_list()

func _refresh_trade_list() -> void:
	npc_menu_content.visible = true
	var money := int(GameState.profile.get("vitals", {}).get("money", 0))
	var lines := ["— %s —" % ("购买" if trade_mode == "buy" else "典当"), "持有 %d Token" % money, "左栏分类 · 右栏物品 · ↑↓选择 · 空格确认", ""]
	for category_index in trade_categories.size():
		lines.append(_cursor(trade_categories[category_index], category_index == trade_category_index))
	lines.append("")
	if trade_items.is_empty():
		lines.append("货已售罄" if trade_mode == "buy" else "已无可卖之物")
	else:
		for index in trade_items.size():
			var item_id := str(trade_items[index])
			var definition: Dictionary = DataRegistry.get_item(item_id)
			var price := int(definition.get("price", 0)) if trade_mode == "buy" else int(floor(float(definition.get("price", 0)) * 0.25))
			lines.append(_cursor("%s (%d Token)" % [definition.get("name", item_id), price], not trade_focus_category and index == trade_index))
	if not trade_focus_category and not trade_items.is_empty():
		lines.append("")
		lines.append(str(DataRegistry.get_item(str(trade_items[trade_index])).get("description", "暂无说明")))
	npc_menu_content.text = "\n".join(lines)

func _item_category(item_id: String) -> String:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	var kind := str(definition.get("kind", "other"))
	if kind in ["food", "water"]: return "食物"
	if kind in ["medicine", "elixir"]: return "药物"
	var slot := str(definition.get("slot", ""))
	return {"weapon": "武器", "armor": "防具", "shoe": "鞋子", "accessory": "饰品"}.get(slot, "其他")

const TRADE_CATEGORY_ORDER := ["食物", "药物", "武器", "防具", "鞋子", "饰品", "其他"]

func _rebuild_trade_categories() -> void:
	var present: Array[String] = []
	for item_id in trade_all_items:
		var category := _item_category(str(item_id))
		if category not in present:
			present.append(category)
	trade_categories.clear()
	for category in TRADE_CATEGORY_ORDER:
		if category in present:
			trade_categories.append(category)
	if trade_categories.is_empty():
		trade_categories.append("其他")
	trade_category_index = clampi(trade_category_index, 0, trade_categories.size() - 1)
	trade_focus_category = true
	_refresh_trade_items()

func _refresh_trade_items() -> void:
	trade_items = []
	var selected := trade_categories[trade_category_index] if not trade_categories.is_empty() else "其他"
	for item_id in trade_all_items:
		if _item_category(str(item_id)) == selected:
			trade_items.append(item_id)
	if trade_mode == "buy":
		trade_items.sort_custom(func(a, b): return int(DataRegistry.get_item(str(a)).get("price", 0)) < int(DataRegistry.get_item(str(b)).get("price", 0)))
	trade_index = clampi(trade_index, 0, maxi(0, trade_items.size() - 1))
	_refresh_trade_list()

func _handle_learn_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		if learn_focus_category:
			learn_open = false
			npc_menu_open = true
			_refresh_npc_menu()
		else:
			learn_focus_category = true
			_refresh_learn_items()
	elif key == KEY_LEFT:
		learn_focus_category = true
		_refresh_learn_items()
	elif learn_focus_category and key in [KEY_UP, KEY_DOWN]:
		var delta := -1 if key == KEY_UP else 1
		learn_category_index = posmod(learn_category_index + delta, maxi(1, learn_categories.size()))
		_refresh_learn_items()
	elif learn_focus_category and key in [KEY_RIGHT, KEY_SPACE]:
		if not learn_items.is_empty():
			learn_focus_category = false
			learn_index = 0
			_refresh_learn_list()
	elif not learn_focus_category and key == KEY_UP:
		learn_index = posmod(learn_index - 1, maxi(1, learn_items.size()))
		_refresh_learn_list()
	elif not learn_focus_category and key == KEY_DOWN:
		learn_index = posmod(learn_index + 1, maxi(1, learn_items.size()))
		_refresh_learn_list()
	elif not learn_focus_category and key == KEY_SPACE:
		if not learn_items.is_empty():
			var result: Dictionary = SkillSystem.learn_tick(nearby_npc_id, learn_items[learn_index])
			message = result.message
	_refresh_learn_list()

func _refresh_learn_list() -> void:
	npc_menu_content.visible = true
	var lines := ["学习功法", "左栏分类 · 右栏技能 · ↑↓选择 · 空格学习", ""]
	for category_index in learn_categories.size():
		lines.append(_cursor(learn_categories[category_index], category_index == learn_category_index))
	lines.append("")
	if learn_items.is_empty():
		lines.append("（暂无可学习功法）")
	else:
		for index in learn_items.size():
			var skill_id := learn_items[index]
			var definition: Dictionary = DataRegistry.get_skill(skill_id)
			lines.append(_cursor("%s Lv.%d" % [definition.get("name", skill_id), SkillSystem.level(skill_id)], not learn_focus_category and index == learn_index))
	npc_menu_content.text = "\n".join(lines)

func _skill_category(skill_id: String) -> String:
	var theme := str(DataRegistry.get_skill(skill_id).get("theme", ""))
	return {"code": "编码", "tune": "思维", "arch": "架构", "parry": "招架", "knowledge": "灵感"}.get(theme, "其他")

func _rebuild_learn_categories() -> void:
	learn_categories.clear()
	for skill_id in learn_all_items:
		var category := _skill_category(skill_id)
		if category not in learn_categories:
			learn_categories.append(category)
	if learn_categories.is_empty(): learn_categories.append("其他")
	learn_category_index = clampi(learn_category_index, 0, learn_categories.size() - 1)
	learn_focus_category = true
	_refresh_learn_items()

func _refresh_learn_items() -> void:
	learn_items = []
	var selected := learn_categories[learn_category_index] if not learn_categories.is_empty() else "其他"
	for skill_id in learn_all_items:
		if _skill_category(skill_id) == selected:
			learn_items.append(skill_id)
	learn_index = clampi(learn_index, 0, maxi(0, learn_items.size() - 1))
	_refresh_learn_list()

func _open_practice() -> void:
	practice_items = []
	var sect := str(GameState.profile.get("sect", ""))
	for skill_id in DataRegistry.skills:
		var definition: Dictionary = DataRegistry.skills[skill_id]
		if str(definition.get("category", "")) == "sect" and str(definition.get("theme", "")) != "arch" and str(definition.get("sect", "")) == sect and SkillSystem.level(str(skill_id)) > 0:
			practice_items.append(str(skill_id))
	practice_index = 0
	practice_open = true
	menu_open = false
	menu_panel.visible = false
	details_panel.visible = true
	_refresh_practice()

func _handle_practice_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		practice_open = false
		details_panel.visible = false
		menu_open = true
		menu_panel.visible = true
		_refresh_menu()
	elif key == KEY_UP and not practice_items.is_empty():
		practice_index = posmod(practice_index - 1, practice_items.size())
	elif key == KEY_DOWN and not practice_items.is_empty():
		practice_index = posmod(practice_index + 1, practice_items.size())
	elif key == KEY_SPACE and not practice_items.is_empty():
		message = SkillSystem.practice_tick(practice_items[practice_index]).message
	_refresh_practice()

func _refresh_practice() -> void:
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	var area := details_content.size
	var scale := _display_scale()
	var pad := 22.0 * scale
	var row := 31.0 * scale
	var content_top := _detail_chrome("练功", "PRACTICE / 门派功法")
	if practice_items.is_empty():
		_detail_label("（需先拜师并学会门派非架构功法）", Rect2(Vector2(pad, content_top + 14.0 * scale), Vector2(area.x - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in practice_items.size():
			var skill_id := practice_items[index]
			var definition: Dictionary = DataRegistry.get_skill(skill_id)
			var y := content_top + 10.0 * scale + row * index
			_detail_label(str(definition.get("name", skill_id)), Rect2(Vector2(pad * 2.0, y), Vector2(area.x - pad * 5.0, row)), 13)
			_detail_label("%d/%d" % [SkillSystem.level(skill_id), int(definition.get("maxLevel", 100))], Rect2(Vector2(area.x - 115.0 * scale, y), Vector2(90.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.55, 0.55, 0.55, 1))
			if index == practice_index:
				_detail_selection(Rect2(Vector2(pad, y), Vector2(area.x - pad * 2.0, row)))
	_detail_label("空格 开始练功　·　ESC 返回", Rect2(Vector2(pad, area.y - 40.0 * scale), Vector2(area.x - pad * 2.0, 28.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))

func _select_npc_menu() -> void:
	var npc: Dictionary = NpcSystem.build_instance(nearby_npc_id)
	if npc_menu_actions.is_empty():
		return
	var action := npc_menu_actions[npc_menu_index]
	_close_npc_menu()
	match action:
		"talk":
			var quest_message := QuestSystem.interact_npc(nearby_npc_id)
			var dialogue := quest_message if not quest_message.is_empty() else NpcSystem.dialogue(nearby_npc_id)
			_show_dialogue(str(npc.get("display_name", nearby_npc_id)), dialogue, 5.0 if not quest_message.is_empty() else 0.0)
		"view":
			_show_npc_view_panel(npc)
		"spar":
			battle_lethal = false
			_start_battle()
			return
		"fight":
			battle_lethal = true
			_start_battle()
			return
		"buy":
			var stock := DataRegistry.list_vendor_stock(nearby_npc_id)
			trade_all_items = stock
			trade_mode = "buy"
			trade_category_index = 0
			trade_open = true
			_rebuild_trade_categories()
			return
		"sell":
			trade_all_items = []
			for entry in InventorySystem.list_entries():
				trade_all_items.append(entry.get("id", ""))
			trade_mode = "sell"
			trade_category_index = 0
			trade_open = true
			_rebuild_trade_categories()
			return
		"join":
			_show_details(SkillSystem.join_npc(nearby_npc_id).message)
		"learn":
			learn_all_items = SkillSystem.learn_options_for_npc(nearby_npc_id)
			learn_category_index = 0
			learn_open = true
			_rebuild_learn_categories()
			return
	_refresh_status()

func _refresh_nearby_npc() -> void:
	if not map_context:
		return
	nearby_npc_id = ""
	var object: Dictionary = map_context.npc_object_at_tile(player_tile.x + facing.x, player_tile.y + facing.y)
	var candidate := str(object.get("properties", {}).get("npcId", ""))
	if not candidate.is_empty() and NpcSystem.can_interact(candidate):
		nearby_npc_id = candidate
	var bounty: Dictionary = QuestSystem.get_bounty_target()
	if not bounty.is_empty() and _current_map_matches(str(bounty.get("map_id", ""))):
		var target_tile := _bounty_tile()
		if player_tile + facing == target_tile:
			nearby_npc_id = str(bounty.get("target_id", ""))
	var active_target: Dictionary = QuestSystem.get_active_target()
	if not active_target.is_empty() and _current_map_matches(str(active_target.get("map_id", ""))):
		if player_tile + facing == _active_target_tile():
			nearby_npc_id = str(active_target.get("target_id", ""))

func _draw_npcs() -> void:
	if not map_context:
		return
	for object in map_context.npc_objects():
		var npc_id := str(object.get("properties", {}).get("npcId", ""))
		if npc_id.is_empty():
			continue
		if NpcSystem.is_defeated(npc_id):
			continue
		var tile := Vector2(floor(float(object.get("x", 0)) / map_context.tile_width), floor(float(object.get("y", 0)) / map_context.tile_height))
		if not _is_world_tile_visible(tile):
			continue
		var position := _world_to_screen(tile * Vector2(map_context.tile_width, map_context.tile_height))
		var source := NpcSystem.sprite_region(npc_id)
		var zoom := _render_scale()
		draw_texture_rect_region(npc_texture, Rect2(position + Vector2(1, -source.size.y + 16) * zoom, source.size * zoom), source)
	var bounty: Dictionary = QuestSystem.get_bounty_target()
	if not bounty.is_empty() and _current_map_matches(str(bounty.get("map_id", ""))):
		var bounty_tile := Vector2(_bounty_tile())
		if _is_world_tile_visible(bounty_tile):
			var target_position := _world_to_screen(bounty_tile * Vector2(map_context.tile_width, map_context.tile_height))
			var target_source := NpcSystem.sprite_region(str(bounty.get("target_id", "")))
			draw_texture_rect_region(npc_texture, Rect2(target_position + Vector2(1, -target_source.size.y + 16) * _render_scale(), target_source.size * _render_scale()), target_source)
	var active_target: Dictionary = QuestSystem.get_active_target()
	if not active_target.is_empty() and _current_map_matches(str(active_target.get("map_id", ""))) and active_target.get("target_id", "") != bounty.get("target_id", ""):
		var active_tile := Vector2(_active_target_tile())
		if _is_world_tile_visible(active_tile):
			var target_position := _world_to_screen(active_tile * Vector2(map_context.tile_width, map_context.tile_height))
			var target_source := NpcSystem.sprite_region(str(active_target.get("target_id", "")))
			draw_texture_rect_region(npc_texture, Rect2(target_position + Vector2(1, -target_source.size.y + 16) * _render_scale(), target_source.size * _render_scale()), target_source)

func _current_map_matches(map_id: String) -> bool:
	return not map_id.is_empty() and map_context and (map_context.map_id.to_lower() == map_id.to_lower() or map_context.map_id.to_lower().contains(map_id.to_lower()))

func _bounty_tile() -> Vector2i:
	return Vector2i(clampi(map_context.width / 2, 1, map_context.width - 2), clampi(map_context.height / 2, 1, map_context.height - 2))

func _active_target_tile() -> Vector2i:
	return Vector2i(clampi(map_context.width / 2 + 1, 1, map_context.width - 2), clampi(map_context.height / 2, 1, map_context.height - 2))

func _toggle_menu() -> void:
	menu_open = not menu_open
	menu_panel.visible = menu_open
	if menu_open:
		details_panel.visible = false
		menu_index = 0
		system_open = false
		skill_open = false
		_refresh_menu()
	else:
		_clear_menu_hint()
		_clear_menu_widgets()

func _handle_menu_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		if system_open or skill_open:
			system_open = false
			skill_open = false
			_refresh_menu()
		else:
			_toggle_menu()
	elif system_open and key in [KEY_UP, KEY_LEFT]:
		system_index = posmod(system_index - 1, SYSTEM_ITEMS.size())
		_refresh_menu()
	elif system_open and key in [KEY_DOWN, KEY_RIGHT]:
		system_index = posmod(system_index + 1, SYSTEM_ITEMS.size())
		_refresh_menu()
	elif system_open and key == KEY_SPACE:
		_select_system_menu()
	elif skill_open and key in [KEY_UP, KEY_LEFT]:
		skill_index = posmod(skill_index - 1, SKILL_ITEMS.size())
		_refresh_menu()
	elif skill_open and key in [KEY_DOWN, KEY_RIGHT]:
		skill_index = posmod(skill_index + 1, SKILL_ITEMS.size())
		_refresh_menu()
	elif skill_open and key == KEY_SPACE:
		_select_skill_menu()
	elif key in [KEY_LEFT, KEY_UP]:
		menu_index = posmod(menu_index - 1, MENU_ITEMS.size())
		_refresh_menu()
	elif key in [KEY_RIGHT, KEY_DOWN]:
		menu_index = posmod(menu_index + 1, MENU_ITEMS.size())
		_refresh_menu()
	elif key == KEY_SPACE:
		_select_menu()

func _refresh_menu() -> void:
	_render_menu_widgets()
	if skill_open:
		var skill_hints := ["冥想：静坐调息，恢复精力。", "练功：选择已学会的门派功法修炼。", "加力：调整本次攻击额外消耗的精力与伤害。", "功法：查看已经学会的基础与门派功法。"]
		_set_menu_hint(SKILL_ITEMS[skill_index], skill_hints[skill_index])
	elif system_open:
		var system_hints := ["赛博传送将消耗精力。选择目的地后立即传送。", "摸鱼：消磨时间并恢复体力。", "疗伤：消耗资源治疗伤势。", "保存：将当前进度写入存档。", "退出：保存后返回创建角色页面。"]
		_set_menu_hint(SYSTEM_ITEMS[system_index], system_hints[system_index])
	else:
		_clear_menu_hint()

func _select_menu() -> void:
	match menu_index:
		0:
			_close_menu()
			_show_profile_panel()
			return
		1:
			_close_menu()
			_show_inventory()
			return
		2:
			skill_open = true
			system_open = false
			skill_index = 0
			_refresh_menu()
			return
		3:
			system_open = true
			skill_open = false
			system_index = 0
			_refresh_menu()
			return
	_close_menu()
	_refresh_status()

func _select_skill_menu() -> void:
	match skill_index:
		0:
			message = str(SkillSystem.meditate_tick().get("message", "冥想结束"))
			_close_menu()
		1:
			_close_menu()
			_open_practice()
			return
		2:
			var result := SkillSystem.set_force_power(SkillSystem.force_power() + 1)
			message = str(result.get("message", "加力已调整"))
			_close_menu()
		3:
			_close_menu()
			_open_skill_book()
			return
	_refresh_status()

func _select_system_menu() -> void:
	match system_index:
		0:
			system_open = false
			menu_open = false
			menu_panel.visible = false
			_try_cyber_teleport()
		1:
			message = SkillSystem.channel_hp().message
		2:
			message = SkillSystem.heal_injury().message
		3:
			GameState.save_game()
			message = "游戏已保存"
			_close_menu()
		4:
			GameState.save_game()
			get_tree().change_scene_to_file("res://scenes/character_creation.tscn")
	if menu_open:
		_refresh_menu()
	_refresh_status()

func _close_menu() -> void:
	menu_open = false
	system_open = false
	skill_open = false
	menu_panel.visible = false
	_clear_menu_hint()
	_clear_menu_widgets()

func _set_menu_hint(title: String, text: String) -> void:
	if dialogue_open:
		return
	dialogue_panel.visible = true
	dialogue_content.text = "%s：\n%s" % [title, text]
	dialogue_content.add_theme_font_size_override("font_size", maxi(12, int(round(12.0 * _display_scale()))))

func _clear_menu_hint() -> void:
	if not dialogue_open:
		dialogue_panel.visible = false

func _ui_box(fill: Color, border: Color = Color(0.25, 0.25, 0.25, 1.0), border_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.border_width_left = border_width
	box.border_width_top = border_width
	box.border_width_right = border_width
	box.border_width_bottom = border_width
	box.corner_radius_top_left = 2
	box.corner_radius_top_right = 2
	box.corner_radius_bottom_right = 2
	box.corner_radius_bottom_left = 2
	box.shadow_color = Color(0.05, 0.04, 0.03, 0.18)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	return box

func _apply_hud_theme() -> void:
	# Keep the docs' white-paper / grey-ink language, but give every modal a
	# shared card treatment so dynamically-created panels do not look detached.
	var paper := Color("f8f6ee")
	var ink := Color("4b4943")
	var warm_paper := Color("fcfbf6")
	for panel in [map_badge_panel, details_panel, npc_menu_panel, menu_panel, battle_panel]:
		panel.add_theme_stylebox_override("panel", _ui_box(paper, ink, 1))
	var dialogue_box := _ui_box(warm_paper, ink, 1)
	dialogue_box.content_margin_left = 8.0
	dialogue_box.content_margin_top = 8.0
	dialogue_box.content_margin_right = 8.0
	dialogue_box.content_margin_bottom = 8.0
	dialogue_panel.add_theme_stylebox_override("panel", dialogue_box)
	map_badge.add_theme_color_override("font_color", Color("302f2b"))
	for label in [details_content, npc_menu_content, menu_content, battle_content, dialogue_content]:
		label.add_theme_color_override("font_color", Color("302f2b"))

func _detail_chrome(title: String, subtitle: String = "") -> float:
	npc_portrait.visible = false
	var scale := _display_scale()
	var area := details_content.size
	var header := Panel.new()
	header.position = Vector2(10.0, 8.0) * scale
	header.size = Vector2(area.x / scale - 20.0, 38.0) * scale
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_stylebox_override("panel", _ui_box(Color("ebe7da"), Color("a19b8d"), 1))
	details_content.add_child(header)
	details_widgets.append(header)
	_detail_label(title, Rect2(Vector2(24.0, 10.0) * scale, Vector2(area.x / scale - 48.0, 22.0) * scale), 16, HORIZONTAL_ALIGNMENT_CENTER, Color("393731"))
	if not subtitle.is_empty():
		_detail_label(subtitle, Rect2(Vector2(22.0, 30.0) * scale, Vector2(area.x / scale - 44.0, 16.0) * scale), 9, HORIZONTAL_ALIGNMENT_CENTER, Color("817b70"))
	return 58.0 * scale

func _clear_menu_widgets() -> void:
	# _render_menu_widgets() runs every frame while the menu is open (via
	# _layout_game_view()), so deletion must be synchronous: queue_free()
	# defers removal to end-of-frame, leaving the about-to-be-freed old
	# labels and the freshly created ones overlapping as siblings for that
	# frame, which reads as a continuous flicker at 60 fps.
	for widget in menu_widgets:
		if is_instance_valid(widget):
			widget.free()
	menu_widgets.clear()

func _clear_details_widgets() -> void:
	profile_panel_open = false
	npc_view_panel_open = false
	for widget in details_widgets:
		if is_instance_valid(widget):
			widget.free()
	details_widgets.clear()

func _detail_label(text: String, rect: Rect2, size: int = 13, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, color: Color = Color(0.18, 0.18, 0.18, 1.0)) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
	label.add_theme_font_size_override("font_size", maxi(12, int(round(float(size) * _display_scale()))))
	label.add_theme_color_override("font_color", color)
	details_content.add_child(label)
	details_widgets.append(label)
	return label

func _detail_rule(from: Vector2, to: Vector2, color: Color = Color(0.35, 0.35, 0.35, 1.0)) -> void:
	var rule := ColorRect.new()
	rule.color = color
	rule.position = from
	rule.size = Vector2(maxf(1.0, to.x - from.x), maxf(1.0, to.y - from.y))
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_content.add_child(rule)
	details_widgets.append(rule)

func _detail_selection(rect: Rect2) -> void:
	var selection := Panel.new()
	selection.position = rect.position
	selection.size = rect.size
	selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection.add_theme_stylebox_override("panel", _ui_box(Color(1, 1, 1, 0), Color(0.78, 0.12, 0.06, 1), 2))
	details_content.add_child(selection)
	details_widgets.append(selection)

func _show_profile_panel() -> void:
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var attrs: Dictionary = GameState.profile.get("attributes", {})
	var base: Dictionary = GameState.profile.get("base_attributes", attrs)
	var hp_max := _npc_hp(GameState.profile, true) - int(GameState.combat_state.get("injury", 0))
	var mp_max: int = GameState.player_mp_max()
	var capacity := 200 + int(attrs.get("strength", 25)) * 10
	var appearance := int(vitals.get("appearance", 0))
	details_panel.visible = true
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	profile_panel_open = true
	_layout_profile_panel()
	var scale := _display_scale()
	var hp := int(GameState.combat_state.get("hp", 0))
	var hp_percent := int(round(float(hp) / float(maxi(1, hp_max)) * 100.0))
	var left_lines := [str(GameState.profile.get("name", "")), "年龄：%d" % int(vitals.get("age", 18)), str(GameState.profile.get("sect", "未拜师")) if not str(GameState.profile.get("sect", "")).is_empty() else "未拜师", "", "食物：%d / %d" % [vitals.get("food", 0), capacity], "体力：%d / %d（%d%%）" % [hp, hp_max, hp_percent], "编码：%d/%d" % [attrs.get("strength", 0), base.get("strength", 0)], "架构：%d/%d" % [attrs.get("constitution", 0), base.get("constitution", 0)], "", "Token：%d" % int(vitals.get("money", 0)), "经验：%d" % int(vitals.get("experience", 0))]
	var right_lines := [_gender_label(str(GameState.profile.get("gender", ""))), _appearance_title(appearance, str(GameState.profile.get("gender", "male"))), _skill_rating(), "", "饮水：%d / %d" % [vitals.get("water", 0), capacity], "精力：%d / %d" % [GameState.combat_state.get("mp", 0), mp_max], "思维：%d/%d" % [attrs.get("agility", 0), base.get("agility", 0)], "灵感：%d/%d" % [attrs.get("wisdom", 0), base.get("wisdom", 0)], "", "潜能：%d" % int(vitals.get("potential", 0))]
	var left_label := _detail_label("\n".join(left_lines), Rect2(Vector2(30.0, 30.0) * scale, Vector2(132.0, 240.0) * scale), 12)
	var right_label := _detail_label("\n".join(right_lines), Rect2(Vector2(168.0, 30.0) * scale, Vector2(132.0, 240.0) * scale), 12, HORIZONTAL_ALIGNMENT_RIGHT)
	left_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	right_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

func _layout_profile_panel() -> void:
	var scale := _display_scale()
	var panel_size := Vector2(330.0, 300.0) * scale
	panel_size.x = minf(panel_size.x, get_viewport_rect().size.x - 16.0 * scale)
	panel_size.y = minf(panel_size.y, get_viewport_rect().size.y - 16.0 * scale)
	details_panel.position = (get_viewport_rect().size - panel_size) * 0.5
	details_panel.size = panel_size

func _show_npc_view_panel(npc: Dictionary) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = npc_texture
	atlas.region = NpcSystem.sprite_region(nearby_npc_id)
	details_panel.visible = true
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	npc_view_panel_open = true
	_layout_npc_view_panel()
	var scale := _display_scale()
	var portrait_size := Vector2(48.0, 48.0) * scale
	npc_portrait.texture = atlas
	npc_portrait.position = Vector2(141.0, 16.0) * scale
	npc_portrait.size = portrait_size
	npc_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	npc_portrait.visible = true
	var equipment_names: Array[String] = []
	for item_id in npc.get("equipment", []):
		var item: Dictionary = DataRegistry.get_item(str(item_id))
		equipment_names.append(str(item.get("name", item_id)))
	var equipment_text := "、".join(equipment_names) if not equipment_names.is_empty() else "无"
	var age_text := str(int(npc.get("age", 0))) if npc.has("age") else "未知"
	var left_label := _detail_label("%s\n年龄：%s\n装备：%s" % [npc.get("display_name", nearby_npc_id), age_text, equipment_text], Rect2(Vector2(30.0, 86.0) * scale, Vector2(170.0, 58.0) * scale), 12)
	var right_label := _detail_label("%s\n%s" % [_gender_label(str(npc.get("gender", ""))), _npc_skill_rating(npc)], Rect2(Vector2(205.0, 86.0) * scale, Vector2(95.0, 58.0) * scale), 12, HORIZONTAL_ALIGNMENT_RIGHT)
	left_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	right_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var description := _detail_label(str(npc.get("description", "")), Rect2(Vector2(30.0, 154.0) * scale, Vector2(270.0, 42.0) * scale), 12, HORIZONTAL_ALIGNMENT_LEFT)
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _layout_npc_view_panel() -> void:
	var scale := _display_scale()
	var panel_size := Vector2(330.0, 220.0) * scale
	panel_size.x = minf(panel_size.x, get_viewport_rect().size.x - 16.0 * scale)
	panel_size.y = minf(panel_size.y, get_viewport_rect().size.y - 16.0 * scale)
	details_panel.position = (get_viewport_rect().size - panel_size) * 0.5
	details_panel.size = panel_size

func _npc_skill_rating(npc: Dictionary) -> String:
	var levels: Dictionary = npc.get("skillLevels", {})
	if levels.is_empty():
		return "不通武艺"
	var total := 0
	for value in levels.values():
		total += int(value)
	var average := total / maxi(1, levels.size())
	if average >= 80: return "出神入化"
	if average >= 60: return "炉火纯青"
	if average >= 40: return "登堂入室"
	if average >= 20: return "略通武艺"
	return "不通武艺"

func _render_inventory_widgets() -> void:
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	var area := details_content.size
	var scale := _display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 28.0 * scale
	var content_top := _detail_chrome("背包（%d）" % InventorySystem.list_entries().size(), "INVENTORY / 物品收纳")
	_detail_rule(Vector2(split, content_top), Vector2(split + 1.0, area.y - 48.0 * scale), Color("c5bfb2"))
	for index in inventory_categories.size():
		var y := content_top + 8.0 * scale + row * index
		_detail_label(inventory_categories[index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.7, row)), 13)
		if inventory_focus_category and index == inventory_category_index:
			_detail_selection(Rect2(Vector2(pad, y), Vector2(split - pad * 1.2, row)))
	if inventory_items.is_empty():
		_detail_label("（该分类暂无物品）", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in inventory_items.size():
			var item_id := inventory_items[index]
			var definition: Dictionary = DataRegistry.get_item(item_id)
			var y := content_top + 8.0 * scale + row * index
			var mark := ""
			if str(definition.get("kind", "")) == "equip":
				mark = "■  " if not InventorySystem.equipped_slot(item_id).is_empty() else "□  "
			_detail_label(mark + str(definition.get("name", item_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 110.0 * scale, row)), 13)
			_detail_label("× %d" % InventorySystem.count(item_id), Rect2(Vector2(area.x - 95.0 * scale, y), Vector2(70.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.55, 0.55, 0.55, 1))
			if not inventory_focus_category and index == inventory_index:
				_detail_selection(Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row)))
	var footer := "↑↓ 选分类　·　空格/→ 查看　·　ESC 返回"
	if not inventory_focus_category and not inventory_items.is_empty():
		var focused: Dictionary = DataRegistry.get_item(inventory_items[inventory_index])
		footer = str(focused.get("description", "暂无说明"))
	_detail_label(footer, Rect2(Vector2(pad, area.y - 37.0 * scale), Vector2(area.x - pad * 2.0, 28.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))

func _menu_label(text: String, rect: Rect2, selected: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
	label.add_theme_font_size_override("font_size", maxi(12, int(round(18.0 * _display_scale()))))
	label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12, 1.0))
	label.add_theme_stylebox_override("normal", _ui_box(Color(0.98, 0.98, 0.97, 1.0), Color(0.78, 0.12, 0.06, 1.0) if selected else Color(0.98, 0.98, 0.97, 1.0), 2 if selected else 0))
	hud.add_child(label)
	menu_widgets.append(label)
	return label

func _render_menu_widgets() -> void:
	_clear_menu_widgets()
	if not menu_open:
		return
	var scale := _display_scale()
	menu_panel.add_theme_stylebox_override("panel", _ui_box(Color(0.98, 0.98, 0.97, 1.0), Color(0.32, 0.32, 0.32, 1.0), 1))
	var tab_width := menu_panel.size.x / float(MENU_ITEMS.size())
	for index in MENU_ITEMS.size():
		_menu_label(MENU_ITEMS[index], Rect2(menu_panel.position + Vector2(tab_width * index, 0), Vector2(tab_width, menu_panel.size.y)), index == menu_index)
	var dropdown_items: Array[String] = []
	var dropdown_index := 0
	if skill_open:
		dropdown_items.append_array(SKILL_ITEMS)
		dropdown_index = skill_index
	elif system_open:
		dropdown_items.append_array(SYSTEM_ITEMS)
		dropdown_index = system_index
	if dropdown_items.is_empty():
		return
	var item_height := 32.0 * scale
	var dropdown_width := tab_width
	var dropdown_x := menu_panel.position.x + tab_width * menu_index
	for index in dropdown_items.size():
		_menu_label(dropdown_items[index], Rect2(Vector2(dropdown_x, menu_panel.position.y + menu_panel.size.y + item_height * index), Vector2(dropdown_width, item_height)), index == dropdown_index)

func _start_battle() -> void:
	if nearby_npc_id.is_empty() or not NpcSystem.can_interact(nearby_npc_id):
		message = "附近没有可战斗的 NPC"
		_refresh_status()
		return
	battle_enemy = NpcSystem.build_instance(nearby_npc_id)
	battle_session = CombatSystem.create_session(nearby_npc_id)
	battle_enemy_hp = int(battle_session.get("enemy_hp", _npc_hp(battle_enemy)))
	battle_active = true
	battle_panel.visible = true
	_refresh_battle()

func _handle_battle_key(key: Key) -> void:
	if key == KEY_SPACE:
		var result: Dictionary = CombatSystem.player_attack(battle_session)
		battle_enemy_hp = int(battle_session.get("enemy_hp", battle_enemy_hp))
		if result.get("skipped", false):
			message = str(result.get("message", "无法行动"))
		elif result.hit:
			message = "命中 %s，造成 %d 伤害" % ["暴击" if result.crit else "", result.damage]
		else:
			message = "攻击未命中"
		if battle_enemy_hp <= 0:
			_end_battle(BattleResolve.resolve_victory(battle_session, battle_lethal))
		else:
			var counter: Dictionary = CombatSystem.enemy_action(battle_session)
			if counter.get("damage", 0) > 0:
				message += "；敌方反击造成 %d 伤害" % counter.damage
			if GameState.combat_state.hp <= 0:
				_end_battle(BattleResolve.resolve_defeat(battle_session))
				return
			_refresh_battle()
	elif key == KEY_DOWN:
		_open_battle_submenu("item")
	elif key == KEY_UP:
		_open_battle_submenu("ult")
	elif key == KEY_RIGHT:
		var rest_result: Dictionary = CombatSystem.rest(battle_session)
		message = rest_result.message
		if rest_result.get("ok", false):
			var counter := CombatSystem.enemy_action(battle_session)
			if counter.get("damage", 0) > 0:
				message += "；敌方反击造成 %d 伤害" % counter.damage
			if GameState.combat_state.hp <= 0:
				_end_battle(BattleResolve.resolve_defeat(battle_session))
				return
		_refresh_battle()
	elif key == KEY_LEFT:
		if CombatSystem.flee(battle_session):
			_end_battle(BattleResolve.resolve_flee(battle_session, battle_lethal))
		else:
			message = "逃跑失败"
			_refresh_battle()

func _open_battle_submenu(kind: String) -> void:
	battle_submenu = kind
	battle_submenu_index = 0
	battle_submenu_items = []
	if kind == "item":
		for entry in InventorySystem.list_entries("medicine"):
			var item_id := str(entry.get("id", ""))
			if int(DataRegistry.get_item(item_id).get("effects", {}).get("hp", 0)) > 0:
				battle_submenu_items.append(item_id)
	else:
		for ult in SkillSystem.unlocked_ults():
			battle_submenu_items.append(ult)
	if battle_submenu_items.is_empty():
		battle_submenu = ""
		message = "没有可用的战斗选项"
	_refresh_battle()

func _handle_battle_submenu_key(key: Key) -> void:
	if key == KEY_ESCAPE or key == KEY_LEFT:
		battle_submenu = ""
		_refresh_battle()
		return
	if key == KEY_UP:
		battle_submenu_index = posmod(battle_submenu_index - 1, battle_submenu_items.size())
	elif key == KEY_DOWN:
		battle_submenu_index = posmod(battle_submenu_index + 1, battle_submenu_items.size())
	elif key == KEY_SPACE:
		if battle_submenu == "item":
			var item_id := str(battle_submenu_items[battle_submenu_index])
			var item_result: Dictionary = CombatSystem.use_item(battle_session, item_id)
			message = str(item_result.get("message", ""))
			battle_submenu = ""
			if item_result.get("ok", false):
				var counter := CombatSystem.enemy_action(battle_session)
				if counter.get("damage", 0) > 0:
					message += "；敌方反击造成 %d 伤害" % counter.damage
				if GameState.combat_state.hp <= 0:
					_end_battle(BattleResolve.resolve_defeat(battle_session))
					return
		else:
			var ult_result: Dictionary = CombatSystem.use_ult(battle_session, battle_submenu_index)
			if not ult_result.ok:
				message = str(ult_result.get("message", ""))
				_refresh_battle()
				return
			message = str(ult_result.ult.get("name", "绝招"))
			battle_submenu = ""
			battle_enemy_hp = int(battle_session.get("enemy_hp", battle_enemy_hp))
			if battle_enemy_hp <= 0:
				_end_battle(BattleResolve.resolve_victory(battle_session, battle_lethal))
				return
			CombatSystem.enemy_action(battle_session)
	_refresh_battle()

func _refresh_battle() -> void:
	var lines := ["战斗：%s", "我方体力：%d / %d", "敌方体力：%d / %d", "状态：%s", ""]
	if battle_submenu.is_empty():
		lines.append_array(["空格攻击", "↑绝招", "↓使用药品", "→摸鱼", "←逃跑", "ESC退出"])
	else:
		lines.append("Esc 返回")
		for index in battle_submenu_items.size():
			var label := ""
			if battle_submenu == "item":
				var item_id := str(battle_submenu_items[index])
				label = "%s ×%d" % [DataRegistry.get_item(item_id).get("name", item_id), InventorySystem.count(item_id)]
			else:
				label = str(battle_submenu_items[index].get("name", "绝招"))
			lines.append(_cursor(label, index == battle_submenu_index))
		lines[0] = "战斗：%s" % battle_enemy.get("display_name", nearby_npc_id)
		lines[1] = "我方体力：%d / %d" % [GameState.combat_state.hp, battle_session.get("player_max_hp", _npc_hp(GameState.profile, true))]
		lines[2] = "敌方体力：%d / %d" % [battle_enemy_hp, battle_session.get("enemy_max_hp", battle_enemy_hp)]
		lines[3] = "状态：%s" % battle_session.get("player_status", {})
	battle_content.text = "\n".join(lines)

func _end_battle(result_message: String) -> void:
	battle_active = false
	battle_submenu = ""
	battle_submenu_items = []
	battle_panel.visible = false
	message = result_message
	_refresh_status()

func _npc_hp(npc: Dictionary, is_player := false) -> int:
	if is_player:
		return GameState.player_hp_max()
	var attributes: Dictionary = npc.get("attributes", {})
	return GameState.hp_max_with_mp_boost(float(attributes.get("constitution", 0)), int(npc.get("mp", 0)))

func _show_inventory() -> void:
	inventory_open = true
	inventory_category_index = 0
	inventory_focus_category = true
	details_panel.visible = true
	_refresh_inventory_panel()
	message = "背包已打开"
	_refresh_status()

func _handle_inventory_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		if inventory_focus_category:
			inventory_open = false
			details_panel.visible = false
		else:
			inventory_focus_category = true
		_refresh_inventory_panel()
		return
	if key == KEY_LEFT:
		inventory_focus_category = true
	elif inventory_focus_category and key in [KEY_UP, KEY_DOWN]:
		var delta := -1 if key == KEY_UP else 1
		inventory_category_index = posmod(inventory_category_index + delta, inventory_categories.size())
	elif inventory_focus_category and key in [KEY_RIGHT, KEY_SPACE]:
		inventory_focus_category = false
		inventory_index = 0
	elif not inventory_focus_category and key == KEY_UP:
		inventory_index = posmod(inventory_index - 1, maxi(1, inventory_items.size()))
	elif not inventory_focus_category and key == KEY_DOWN:
		inventory_index = posmod(inventory_index + 1, maxi(1, inventory_items.size()))
	elif not inventory_focus_category and key == KEY_SPACE and not inventory_items.is_empty():
		var item_id := inventory_items[inventory_index]
		var definition: Dictionary = DataRegistry.get_item(item_id)
		var result: Dictionary
		if inventory_categories[inventory_category_index] == "丢弃":
			result = InventorySystem.discard_item(item_id)
		elif str(definition.get("kind", "")) == "equip":
			result = InventorySystem.unequip_item(item_id) if not InventorySystem.equipped_slot(item_id).is_empty() else InventorySystem.equip_item(item_id)
		else:
			result = InventorySystem.use_item(item_id)
		message = str(result.get("message", ""))
	_refresh_inventory_panel()

func _refresh_inventory_panel() -> void:
	var selected := inventory_categories[inventory_category_index]
	inventory_items = []
	for entry in InventorySystem.list_entries():
		var item_id := str(entry.get("id", ""))
		if selected == "丢弃" or _item_category(item_id) == selected:
			inventory_items.append(item_id)
	inventory_index = clampi(inventory_index, 0, maxi(0, inventory_items.size() - 1))
	_render_inventory_widgets()

func _profile_text() -> String:
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var appearance := int(vitals.get("appearance", 0))
	var attrs: Dictionary = GameState.profile.get("attributes", {})
	var base: Dictionary = GameState.profile.get("base_attributes", attrs)
	var hp_max := _npc_hp(GameState.profile, true) - int(GameState.combat_state.get("injury", 0))
	var mp_max: int = GameState.player_mp_max()
	var capacity := 200 + int(attrs.get("strength", 25)) * 10
	return "%s　　　　　　　　　%s\n年龄：%d　　　　　　　　%s\n%s　　　　　　　　　%s\n\n食物：%d / %d　　　　　　饮水：%d / %d\n体力：%d / %d　　　　　　精力：%d / %d\n编码：%d / %d　　　　　　思维：%d / %d\n架构：%d / %d　　　　　　灵感：%d / %d\n\nToken：%d　　　　　　　 潜能：%d\n经验：%d" % [GameState.profile.get("name", ""), _gender_label(str(GameState.profile.get("gender", ""))), vitals.get("age", 18), _appearance_title(appearance, str(GameState.profile.get("gender", "male"))), GameState.profile.get("sect", "未拜师"), _skill_rating(), vitals.get("food", 0), capacity, vitals.get("water", 0), capacity, GameState.combat_state.get("hp", 0), hp_max, GameState.combat_state.get("mp", 0), mp_max, attrs.get("strength", 0), base.get("strength", 0), attrs.get("agility", 0), base.get("agility", 0), attrs.get("constitution", 0), base.get("constitution", 0), attrs.get("wisdom", 0), base.get("wisdom", 0), vitals.get("money", 0), vitals.get("potential", 0), vitals.get("experience", 0)]

func _open_skill_book() -> void:
	skill_book_open = true
	skill_book_category_index = 0
	skill_book_focus_category = true
	details_panel.visible = true
	_refresh_skill_book_panel()

func _handle_skill_book_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		if skill_book_focus_category:
			skill_book_open = false
			details_panel.visible = false
		else:
			skill_book_focus_category = true
		_refresh_skill_book_panel()
		return
	if key == KEY_LEFT:
		skill_book_focus_category = true
	elif skill_book_focus_category and key in [KEY_UP, KEY_DOWN]:
		var delta := -1 if key == KEY_UP else 1
		skill_book_category_index = posmod(skill_book_category_index + delta, skill_book_categories.size())
	elif skill_book_focus_category and key in [KEY_RIGHT, KEY_SPACE]:
		skill_book_focus_category = false
		skill_book_index = 0
	elif not skill_book_focus_category and key == KEY_UP:
		skill_book_index = posmod(skill_book_index - 1, maxi(1, skill_book_items.size()))
	elif not skill_book_focus_category and key == KEY_DOWN:
		skill_book_index = posmod(skill_book_index + 1, maxi(1, skill_book_items.size()))
	elif not skill_book_focus_category and key == KEY_SPACE and not skill_book_items.is_empty():
		var skill_id := skill_book_items[skill_book_index]
		var theme := SKILL_BOOK_THEMES[skill_book_category_index]
		var equipped_id := str(SkillSystem.ensure_skills().get("equipped", {}).get(theme, ""))
		var result: Dictionary = SkillSystem.unequip(skill_id) if skill_id == equipped_id else SkillSystem.equip(skill_id)
		message = str(result.get("message", ""))
	_refresh_skill_book_panel()

func _refresh_skill_book_panel() -> void:
	var theme := SKILL_BOOK_THEMES[skill_book_category_index]
	var sect := str(GameState.profile.get("sect", ""))
	var levels: Dictionary = SkillSystem.ensure_skills().get("levels", {})
	skill_book_items = []
	var basic_id := str(SkillSystem.THEME_BASIC_SKILL.get(theme, ""))
	if int(levels.get(basic_id, 0)) > 0:
		skill_book_items.append(basic_id)
	for skill_id in levels:
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		if str(definition.get("category", "")) == "sect" and str(definition.get("theme", "")) == theme and str(definition.get("sect", "")) == sect and int(levels[skill_id]) > 0:
			skill_book_items.append(str(skill_id))
	skill_book_index = clampi(skill_book_index, 0, maxi(0, skill_book_items.size() - 1))
	_render_skill_book_widgets()

func _render_skill_book_widgets() -> void:
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	var area := details_content.size
	var scale := _display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 30.0 * scale
	var content_top := _detail_chrome("功法", "SKILLS / 装备与修习")
	_detail_rule(Vector2(split, content_top), Vector2(split + 1.0, area.y - 46.0 * scale), Color("c5bfb2"))
	for index in skill_book_categories.size():
		var y := content_top + 8.0 * scale + row * index
		_detail_label(skill_book_categories[index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.6, row)), 13)
		if skill_book_focus_category and index == skill_book_category_index:
			_detail_selection(Rect2(Vector2(pad, y), Vector2(split - pad * 1.1, row)))
	var theme := SKILL_BOOK_THEMES[skill_book_category_index]
	var equipped_id := str(SkillSystem.ensure_skills().get("equipped", {}).get(theme, ""))
	if skill_book_items.is_empty():
		_detail_label("（该分类尚未学会功法）", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in skill_book_items.size():
			var skill_id := skill_book_items[index]
			var definition: Dictionary = DataRegistry.get_skill(skill_id)
			var y := content_top + 8.0 * scale + row * index
			var mark := "■  " if skill_id == equipped_id else "□  "
			_detail_label(mark + str(definition.get("name", skill_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 100.0 * scale, row)), 13)
			_detail_label("%d级" % int(SkillSystem.level(skill_id)), Rect2(Vector2(area.x - 90.0 * scale, y), Vector2(65.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.55, 0.55, 0.55, 1))
			if not skill_book_focus_category and index == skill_book_index:
				_detail_selection(Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row)))
	_detail_label("↑↓ 选分类　·　空格/→ 查看　·　空格 装备/卸下　·　ESC 返回", Rect2(Vector2(pad, area.y - 37.0 * scale), Vector2(area.x - pad * 2.0, 28.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))

func _gender_label(gender: String) -> String:
	return "女" if gender.to_lower() == "female" else "男" if gender.to_lower() == "male" else "未知"

func _skill_rating() -> String:
	var levels: Dictionary = SkillSystem.ensure_skills().get("levels", {})
	var total := 0
	for value in levels.values(): total += int(value)
	var average := total / maxi(1, levels.size())
	if average >= 80: return "出神入化"
	if average >= 50: return "炉火纯青"
	if average >= 20: return "登堂入室"
	return "不堪一击"

func _appearance_title(score: int, gender: String) -> String:
	var male := [["惨不忍睹", "面目狰狞"], ["相貌平平", "浓眉大眼"], ["五官端正", "气宇轩昂"], ["英俊潇洒", "风流倜傥"], ["玉树临风", "潘安再生"]]
	var female := [["惨不忍睹", "容貌丑陋"], ["姿色平平", "略有姿色"], ["亭亭玉立", "明眸皓齿"], ["楚楚动人", "沉鱼落雁", "闭月羞花"], ["国色天香", "倾国倾城"]]
	var tier := clampi(int(floor(float(score) / 20.0)), 0, 4)
	var options: Array = female[tier] if gender == "female" else male[tier]
	return str(options[posmod(score, options.size())])

func _show_details(text: String) -> void:
	_clear_details_widgets()
	details_content.visible = true
	details_content.text = text
	details_panel.visible = true
	npc_portrait.visible = false
	details_content.add_theme_font_size_override("font_size", maxi(12, int(round(13.0 * _display_scale()))))

func _show_dialogue(speaker: String, text: String, lock_seconds: float = 0.0) -> void:
	dialogue_speaker = speaker
	dialogue_locked_until_msec = Time.get_ticks_msec() + int(maxf(0.0, lock_seconds) * 1000.0)
	dialogue_pages = _paginate_dialogue(text)
	dialogue_page_index = 0
	_render_dialogue(speaker)
	dialogue_open = true
	dialogue_panel.visible = true

func _paginate_dialogue(text: String) -> Array[String]:
	# Tiled XML attributes keep authored `\n` sequences as two literal
	# characters. Normalize them before measuring lines so they behave exactly
	# like real newlines from JSON or GDScript strings.
	var normalized := text.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n").replace("\r", "")
	var visual_lines: Array[String] = []
	for raw_line in normalized.split("\n", true):
		var line := str(raw_line)
		if line.is_empty():
			visual_lines.append("")
			continue
		while line.length() > 42:
			visual_lines.append(line.substr(0, 42))
			line = line.substr(42)
		visual_lines.append(line)

	# The speaker occupies the first row; each page has room for two dialogue
	# rows. Explicit lines and lines produced by automatic wrapping therefore
	# advance through the same repeated-space interaction.
	var pages: Array[String] = []
	for line_index in range(0, visual_lines.size(), 2):
		var page_lines := visual_lines.slice(line_index, mini(line_index + 2, visual_lines.size()))
		pages.append("\n".join(page_lines))
	return pages if not pages.is_empty() else [""]

func _render_dialogue(speaker: String) -> void:
	var page := dialogue_pages[clampi(dialogue_page_index, 0, maxi(0, dialogue_pages.size() - 1))]
	dialogue_content.text = "%s：\n%s" % [speaker, page]

func _advance_dialogue() -> void:
	if dialogue_page_index < dialogue_pages.size() - 1:
		dialogue_page_index += 1
		_render_dialogue(dialogue_speaker)
	else:
		_close_dialogue()

func _close_dialogue() -> void:
	dialogue_open = false
	dialogue_speaker = ""
	dialogue_locked_until_msec = 0
	dialogue_pages.clear()
	dialogue_page_index = 0
	dialogue_panel.visible = false

func _load_initial_map() -> void:
	if DataRegistry.map_files.is_empty():
		return
	for index in DataRegistry.map_files.size():
		var candidate := TiledMapLoader.new()
		if candidate.load_file(DataRegistry.map_files[index]) and not candidate.spawn_point().is_empty():
			_load_map(index)
			return
	_load_map(0)

func _load_map(index: int, arrival_from := "", cyber := false) -> void:
	if DataRegistry.map_files.is_empty():
		return
	if map_transitioning:
		return
	map_transitioning = true
	if has_loaded_map:
		var fade_in := create_tween()
		fade_in.tween_property(transition_overlay, "color:a", 1.0, 0.12)
		await fade_in.finished
	map_index = clampi(index, 0, DataRegistry.map_files.size() - 1)
	var next_context := TiledMapLoader.new()
	if not next_context.load_file(DataRegistry.map_files[map_index]):
		map_transitioning = false
		return
	_close_dialogue()
	map_context = next_context
	map_renderer.set_context(map_context)
	var display_name := str(map_context.properties.get("mapName", map_context.map_id))
	map_badge.text = display_name.replace("{playerName}", str(GameState.profile.get("name", "")))
	transition_overlay.color.a = 1.0
	player_tile = Vector2i(8, 5)
	if not arrival_from.is_empty():
		var arrival := map_context.transaction_for_arrival(arrival_from, map_context.map_id, cyber)
		if not arrival.is_empty():
			player_tile = Vector2i(int(floor(float(arrival.get("x", 0)) / map_context.tile_width)), int(floor(float(arrival.get("y", 0)) / map_context.tile_height)))
	else:
		var spawn := map_context.spawn_point()
		if not spawn.is_empty():
			player_tile = Vector2i(int(floor(float(spawn.get("x", 0)) / map_context.tile_width)), int(floor(float(spawn.get("y", 0)) / map_context.tile_height)))
			var spawn_face := str(spawn.get("properties", {}).get("faceDir", "")).to_lower()
			if spawn_face == "up": facing = Vector2i.UP
			elif spawn_face == "down": facing = Vector2i.DOWN
			elif spawn_face == "left": facing = Vector2i.LEFT
			elif spawn_face == "right": facing = Vector2i.RIGHT
	nearby_npc_id = ""
	_refresh_nearby_npc()
	message = "已加载地图：%s（%dx%d）" % [map_context.properties.get("mapName", map_context.map_id), map_context.width, map_context.height]
	_update_camera()
	queue_redraw()
	has_loaded_map = true
	var fade_out := create_tween()
	fade_out.tween_property(transition_overlay, "color:a", 0.0, 0.18)
	await fade_out.finished
	map_transitioning = false

func _try_map_transition() -> void:
	if not map_context:
		return
	var object: Dictionary = map_context.object_at_tile(player_tile.x, player_tile.y)
	if object.is_empty() or object.get("type", "") != "Transaction":
		return
	var properties: Dictionary = object.get("properties", {})
	# Every endpoint stores both directions. Only the endpoint whose `from`
	# matches the currently loaded map is a departure trigger; the other one is
	# the arrival tile and must not immediately send the player back.
	if str(properties.get("from", "")).to_lower() != map_context.map_id.to_lower():
		return
	var target := str(properties.get("to", ""))
	if target.is_empty():
		return
	for index in DataRegistry.map_files.size():
		var file_name := DataRegistry.map_files[index].get_file().get_basename().to_lower()
		if file_name == target.to_lower() or file_name.contains(target.to_lower()):
			_load_map(index, map_context.map_id, false)
			return

func _try_cyber_teleport() -> void:
	if SkillSystem.level("basicAgility") < 30 or SkillSystem.equipped_sect_skill_level("tune") < 30:
		message = "须装备基础思维与高级身法且均达到 30 级，方可赛博传送"
		_refresh_status()
		return
	var mp_max: int = GameState.player_mp_max()
	var cost := maxi(1, int(ceil(float(mp_max) / 3.0)))
	if int(GameState.combat_state.mp) < cost:
		message = "精力不足，赛博传送需要 %d 精力" % cost
		_refresh_status()
		return
	cyber_maps = []
	for index in DataRegistry.map_files.size():
		if index == map_index:
			continue
		var candidate := TiledMapLoader.new()
		if candidate.load_file(DataRegistry.map_files[index]):
			var arrival := candidate.transaction_for_arrival(map_context.map_id if map_context else "", candidate.map_id, true)
			if not arrival.is_empty():
				cyber_maps.append(index)
	if cyber_maps.is_empty():
		message = "暂无可传送的道路地图"
		_refresh_status()
		return
	cyber_open = true
	cyber_index = 0
	menu_open = false
	menu_panel.visible = false
	details_panel.visible = true
	_refresh_cyber_menu(cost)

func _handle_cyber_key(key: Key) -> void:
	var cost := maxi(1, int(ceil(float(GameState.player_mp_max()) / 3.0)))
	if key == KEY_ESCAPE:
		cyber_open = false
		details_panel.visible = false
		return
	if key == KEY_UP:
		cyber_index = posmod(cyber_index - 1, cyber_maps.size())
	elif key == KEY_DOWN:
		cyber_index = posmod(cyber_index + 1, cyber_maps.size())
	elif key == KEY_SPACE:
		if int(GameState.combat_state.mp) < cost:
			message = "精力不足，赛博传送需要 %d 精力" % cost
		else:
			GameState.combat_state.mp -= cost
			var destination := cyber_maps[cyber_index]
			cyber_open = false
			details_panel.visible = false
			_load_map(destination, map_context.map_id if map_context else "", true)
			message = "赛博传送完成，消耗 %d 精力" % cost
	_refresh_cyber_menu(cost)

func _refresh_cyber_menu(cost: int) -> void:
	var lines := ["赛博传送", "↑↓选择目的地 空格确认 ESC返回", "消耗：%d 精力" % cost, ""]
	for position in cyber_maps.size():
		var index := cyber_maps[position]
		var probe := TiledMapLoader.new()
		var label := DataRegistry.map_files[index].get_file().get_basename()
		if probe.load_file(DataRegistry.map_files[index]):
			label = str(probe.properties.get("mapName", probe.map_id))
		lines.append(_cursor(label, position == cyber_index))
	details_content.text = "\n".join(lines)

func _draw() -> void:
	var grid_origin := _map_draw_origin()
	var cell := 16.0 * _render_scale()
	if not map_context:
		for y in range(10):
			for x in range(16):
				draw_rect(Rect2(grid_origin + Vector2(x, y) * cell, Vector2(cell - 1, cell - 1)), Color("#274f45"))
	var player_pos := _world_to_screen(Vector2(player_tile) * Vector2(16, 16)) + Vector2(1, 1) * _render_scale()
	_draw_npcs()
	var source := _player_frame_region()
	var destination := Rect2(player_pos + Vector2(0, -2) * _render_scale(), source.size * _render_scale())
	draw_texture_rect_region(player_texture, destination, source)
	draw_line(player_pos + Vector2(7, 7) * _render_scale(), player_pos + (Vector2(7, 7) + Vector2(facing) * 7) * _render_scale(), Color.WHITE, 2.0 * _render_scale())

func _load_player_sprite_regions() -> void:
	var file := FileAccess.open("res://assets/Texture/atlas_regions.json", FileAccess.READ)
	if not file:
		return
	var atlas_data = JSON.parse_string(file.get_as_text())
	if not atlas_data is Dictionary:
		return
	for key in atlas_data.get("player", {}):
		var region: Array = atlas_data.player[key]
		player_sprite_regions[key] = Rect2(region[0], region[1], region[2], region[3])

func _player_frame_region() -> Rect2:
	var direction := "down"
	if facing == Vector2i.UP: direction = "up"
	elif facing == Vector2i.LEFT: direction = "left"
	elif facing == Vector2i.RIGHT: direction = "right"
	var key := "%s_%d" % [direction, animation_frame + 1]
	return player_sprite_regions.get(key, Rect2(1, 15, 13, 17))

func _run_combat_test() -> void:
	var result := GameState.resolve_attack(8.0, GameState.profile.get("attributes", {}), {"strength": 4, "agility": 4, "constitution": 4, "wisdom": 4}, 10.0)
	message = "战斗测试：未命中" if not result.hit else "战斗测试：造成 %d 点%s伤害" % [result.damage, "暴击" if result.crit else ""]
	_refresh_status()
	queue_redraw()

func _refresh_status() -> void:
	pass

func _game_view_rect() -> Rect2:
	var screen_size := CAMERA_SIZE * _display_scale()
	return Rect2((get_viewport_rect().size - screen_size) * 0.5, screen_size)

func _display_scale() -> float:
	var viewport_size := get_viewport_rect().size
	return minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)

func _map_zoom() -> float:
	if not map_context:
		return 1.0
	var map_size := Vector2(map_context.width * map_context.tile_width, map_context.height * map_context.tile_height)
	var fit_scale := minf(CAMERA_SIZE.x / map_size.x, CAMERA_SIZE.y / map_size.y)
	return maxf(1.0, fit_scale)

func _camera_world_size() -> Vector2:
	return CAMERA_SIZE / _map_zoom()

func _render_scale() -> float:
	return _map_zoom() * _display_scale()

func _camera_world_top_left() -> Vector2:
	if not map_context:
		return Vector2.ZERO
	var map_size := Vector2(map_context.width * map_context.tile_width, map_context.height * map_context.tile_height)
	var camera_world_size := _camera_world_size()
	var player_center := (Vector2(player_tile) + Vector2(0.5, 0.5)) * Vector2(map_context.tile_width, map_context.tile_height)
	return Vector2(
		0.0 if map_size.x <= camera_world_size.x else clampf(player_center.x - camera_world_size.x * 0.5, 0.0, map_size.x - camera_world_size.x),
		0.0 if map_size.y <= camera_world_size.y else clampf(player_center.y - camera_world_size.y * 0.5, 0.0, map_size.y - camera_world_size.y),
	)

func _is_world_tile_visible(tile: Vector2) -> bool:
	if not map_context:
		return false
	var tile_rect := Rect2(tile * Vector2(map_context.tile_width, map_context.tile_height), Vector2(map_context.tile_width, map_context.tile_height))
	return tile_rect.intersects(Rect2(_camera_world_top_left(), _camera_world_size()))

func _map_draw_origin() -> Vector2:
	var view_rect := _game_view_rect()
	if not map_context:
		return view_rect.position
	var map_size := Vector2(map_context.width * map_context.tile_width, map_context.height * map_context.tile_height)
	var scale := _render_scale()
	var origin := view_rect.position - _camera_world_top_left() * scale
	var scaled_map_size := map_size * scale
	if scaled_map_size.x < view_rect.size.x:
		origin.x += (view_rect.size.x - scaled_map_size.x) * 0.5
	if scaled_map_size.y < view_rect.size.y:
		origin.y += (view_rect.size.y - scaled_map_size.y) * 0.5
	return origin

func _world_to_screen(world_position: Vector2) -> Vector2:
	return _map_draw_origin() + world_position * _render_scale()

func _update_camera() -> void:
	if not map_context:
		return
	map_renderer.set_camera(_camera_world_top_left(), _map_draw_origin(), _camera_world_size(), _render_scale())
	queue_redraw()

func _layout_game_view() -> void:
	var view_rect := _game_view_rect()
	var scale := _display_scale()
	var inset := Vector2(8, 8) * scale
	var inset_rect := Rect2(view_rect.position + inset, view_rect.size - inset * 2.0)
	map_badge_panel.position = Vector2(8, 8) * scale
	map_badge_panel.size = Vector2(160, 46) * scale
	map_badge.add_theme_font_size_override("font_size", maxi(12, int(round(16.0 * scale))))
	var overlay_size := Vector2(520.0, 400.0) * scale
	overlay_size.x = minf(overlay_size.x, get_viewport_rect().size.x - 16.0 * scale)
	overlay_size.y = minf(overlay_size.y, get_viewport_rect().size.y - 16.0 * scale)
	if profile_panel_open:
		_layout_profile_panel()
	elif npc_view_panel_open:
		_layout_npc_view_panel()
	else:
		details_panel.position = (get_viewport_rect().size - overlay_size) * 0.5
		details_panel.size = overlay_size
	battle_panel.position = inset_rect.position
	battle_panel.size = inset_rect.size
	if delete_confirm_open:
		_layout_delete_confirm()
	elif npc_menu_open:
		_position_npc_menu()
	else:
		npc_menu_panel.position = inset_rect.position
		npc_menu_panel.size = inset_rect.size
	menu_panel.position = Vector2((get_viewport_rect().size.x - DESIGN_SIZE.x * scale) * 0.5, 0.0)
	menu_panel.size = Vector2(DESIGN_SIZE.x, 42.0) * scale
	var dialogue_size := Vector2(DESIGN_SIZE.x - 20.0, 56.0) * scale
	dialogue_panel.position = Vector2((get_viewport_rect().size.x - dialogue_size.x) * 0.5, get_viewport_rect().size.y - dialogue_size.y - 12.0 * scale)
	dialogue_panel.size = dialogue_size
	dialogue_content.add_theme_font_size_override("font_size", maxi(12, int(round(12.0 * scale))))
	transition_overlay.position = Vector2.ZERO
	transition_overlay.size = get_viewport_rect().size
	if menu_open:
		_refresh_menu()
	_update_camera()

func _cursor(label: String, selected: bool) -> String:
	return "【%s】" % label if selected else "  " + label
