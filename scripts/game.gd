extends Node2D

const VIRTUAL_CONTROLS := preload("res://scripts/virtual_controls.gd")
const MOBILE_ORIENTATION := preload("res://scripts/mobile_orientation.gd")
const UI_PROGRESS_METER := preload("res://scripts/ui_progress_meter.gd")
const GAME_BATTLE_UI := preload("res://scripts/game_battle_ui.gd")
const CAMERA_SIZE := Vector2(640.0, 480.0)
const DESIGN_SIZE := Vector2(640.0, 480.0)
const VITALS_BASE_CAPACITY := 200
const VITALS_CAPACITY_PER_STRENGTH := 10
const MOVE_STEP_SECONDS := 0.15
const DIALOGUE_AUTO_CLOSE_MSEC := 5000
const TRADE_MODE_BUY := "buy"
const TRADE_MODE_SELL := "sell"
const CYBER_TELEPORT_MP_DIVISOR := 5.0
const CYBER_TELEPORT_SKILL_REQUIREMENT := 30

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
@onready var menu_items: Control = $HUD/Menu/Items
@onready var skill_menu_panel: PanelContainer = $HUD/SkillMenu
@onready var skill_menu_items: Control = $HUD/SkillMenu/Items
@onready var system_menu_panel: PanelContainer = $HUD/SystemMenu
@onready var system_menu_items: Control = $HUD/SystemMenu/Items
@onready var battle_panel: PanelContainer = $HUD/Battle
@onready var battle_content: Label = $HUD/Battle/Content
@onready var details_panel: PanelContainer = $HUD/NpcViewHUD
@onready var details_content: Label = $HUD/NpcViewHUD/Content
@onready var npc_portrait: TextureRect = $HUD/NpcViewHUD/Content/Portrait
@onready var dialogue_panel: PanelContainer = $HUD/Dialogue
@onready var dialogue_content: Label = $HUD/Dialogue/Content
@onready var tree_confirm_panel: PanelContainer = $HUD/TreeConfirm
@onready var tree_confirm_content: Label = $HUD/TreeConfirm/Content
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
var force_power_open := false
var force_power_value := 0
var force_power_limit := 0
var menu_widgets: Array[Control] = []
var details_widgets: Array[Control] = []
var detail_huds: Dictionary = {}
var detail_widget_sets: Dictionary = {}
var active_detail_hud := "generic"
var profile_panel_open := false
var npc_view_panel_open := false
var battle_ui: RefCounted
var cyber_open := false
var cyber_index := 0
var cyber_maps: Array[int] = []
var cyber_labels: Array[Label] = []
var cyber_selection_widget: Panel
var npc_menu_open := false
var npc_menu_index := 0
var npc_menu_actions: Array[String] = []
var npc_menu_labels: Array[String] = []
var npc_menu_widgets: Array[Control] = []
var trade_open := false
var trade_mode := TRADE_MODE_BUY
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
var learning_skill_id := ""
var learning_tick_accumulator := 0.0
var inventory_open := false
var inventory_items: Array[String] = []
var inventory_categories: Array[String] = ["食物", "药物", "武器", "防具", "鞋子", "饰品", "其他", "丢弃"]
var inventory_category_index := 0
var inventory_index := 0
var inventory_focus_category := true
var inventory_feedback := ""
var practice_open := false
var practice_index := 0
var practice_items: Array[String] = []
var practice_all_items: Array[String] = []
var practice_categories: Array[String] = ["编码", "思维", "招架"]
var practice_themes: Array[String] = ["code", "tune", "parry"]
var practice_category_index := 0
var practice_focus_category := true
var practicing_skill_id := ""
var practice_tick_accumulator := 0.0
var skill_book_open := false
var skill_book_categories: Array[String] = ["编码", "思维", "架构", "招架", "灵感"]
var skill_book_category_index := 0
var skill_book_focus_category := true
var skill_book_items: Array[String] = []
var skill_book_index := 0
var meditation_open := false
var meditation_widgets: Array[Control] = []
var learning_progress_widgets: Array[Control] = []
var practice_progress_widgets: Array[Control] = []
var meditation_tick_accumulator := 0.0
var SKILL_BOOK_THEMES: Array[String] = ["code", "tune", "arch", "parry", "knowledge"]
var dialogue_open := false
var dialogue_pages: Array[String] = []
var dialogue_page_index := 0
var dialogue_speaker := ""
var dialogue_locked_until_msec := 0
var dialogue_auto_close_at_msec := 0
var dialogue_after_last := Callable()
var map_transitioning := false
var has_loaded_map := false
var delete_confirm_open := false
var delete_confirm_index := 1
var map_index := 0
var player_texture: Texture2D = preload("res://assets/Texture/player.png")
var npc_texture: Texture2D = preload("res://assets/Texture/NPC.png")
var player_sprite_regions: Dictionary = {}
var player_sprite_layouts: Dictionary = {}
var animation_timer := 0.0
var animation_frame := 0
var player_moving := false
var virtual_direction := Vector2.ZERO
var accept_requested := false
var cancel_requested := false
var auto_save_timer := 0.0
var last_layout_viewport_size := Vector2.ZERO
const MENU_ITEMS := ["查看", "背包", "技能", "系统"]
const SKILL_ITEMS := ["冥想", "练功", "加力", "功法"]
const SYSTEM_ITEMS := ["赛博传送", "摸鱼", "疗伤", "保存", "退出"]
const LEARN_CATEGORY_ORDER: Array[String] = ["编码", "思维", "架构", "招架", "灵感"]

func _ready() -> void:
	battle_ui = GAME_BATTLE_UI.new(self)
	_build_detail_huds()
	# 任务槽、冷却、环计数与动态悬赏均为本局内存态，不随存档恢复。
	QuestSystem.reset_runtime()
	MOBILE_ORIENTATION.apply()
	_install_virtual_controls()
	_apply_hud_theme()
	_load_player_sprite_regions()
	get_viewport().size_changed.connect(_layout_game_view)
	_layout_game_view()
	_update_dialogue_auto_close()
	menu_content.text = ""
	_load_initial_map()
	queue_redraw()

func _build_detail_huds() -> void:
	detail_huds["npc_view"] = {"panel": details_panel, "content": details_content}
	detail_widget_sets["npc_view"] = details_widgets
	for kind in ["profile", "inventory", "skill_book", "learn", "practice", "cyber", "buy", "sell", "generic"]:
		var panel := PanelContainer.new()
		panel.name = "%sHUD" % kind.to_pascal_case()
		panel.visible = false
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(panel)
		var content := Label.new()
		content.name = "Content"
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
		content.add_theme_font_size_override("font_size", 13)
		panel.add_child(content)
		detail_huds[kind] = {"panel": panel, "content": content}
		var widget_set: Array[Control] = []
		detail_widget_sets[kind] = widget_set
	_use_detail_hud("generic", false)

func _use_detail_hud(kind: String, show := true) -> void:
	if not detail_huds.has(kind):
		return
	for entry in detail_huds.values():
		(entry.get("panel") as PanelContainer).visible = false
	active_detail_hud = kind
	var entry: Dictionary = detail_huds[kind]
	details_panel = entry.get("panel")
	details_content = entry.get("content")
	details_widgets = detail_widget_sets[kind]
	_layout_active_detail_hud()
	details_panel.visible = show

func _layout_active_detail_hud() -> void:
	if active_detail_hud == "profile":
		_layout_profile_panel()
	elif active_detail_hud == "npc_view":
		_layout_npc_view_panel()
	elif active_detail_hud == "cyber":
		_layout_cyber_panel()
	else:
		_layout_details_overlay()

func _process(delta: float) -> void:
	# Re-sync HUD panel geometry every frame instead of relying solely on the
	# viewport size_changed signal, which can miss web/mobile resizes that happen
	# after _ready() (e.g. fullscreen-on-gesture in mobile_orientation.gd) and
	# leave panels frozen at a stale size/position from an earlier viewport reading.
	# 只在真实尺寸变化时重新布局。菜单节点不能每帧销毁重建，否则 Web
	# 渲染时会出现旧帧/新帧交替的闪烁。
	var viewport_size := get_viewport_rect().size
	if not viewport_size.is_equal_approx(last_layout_viewport_size):
		_layout_game_view()
	# 原项目的 PlayerSurvivalController 无论 HUD 是否打开都持续推进唯一游戏时钟；
	# 学习依赖这条基础时间轴，练功/冥想另有动作快进。
	GameState.advance_time(delta)
	_update_continuous_skill_actions(delta)
	# HUDs are modal: freeze world simulation, including the player's held direction,
	# while menus, dialogue, battle, or detail panels are visible.
	if _has_modal_input():
		player_moving = false
		virtual_direction = Vector2.ZERO
		return
	move_cooldown -= delta
	# 新图集的 idle 与 run 都各有 4 帧。静止时也推进 idle 动画，而不是
	# 永远停在第一帧；打开模态 HUD 时仍由上方分支冻结世界动画。
	animation_timer += delta
	if animation_timer >= MOVE_STEP_SECONDS:
		animation_timer = fmod(animation_timer, MOVE_STEP_SECONDS)
		animation_frame = (animation_frame + 1) % 4
		queue_redraw()
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
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") + virtual_direction
	var requested_step := _apply_facing_input(direction)
	if move_cooldown <= 0.0:
		if direction.length() > 0.0:
			player_moving = true
			var step := requested_step
			var next_tile := player_tile + step
			if map_context and (not map_context.is_walkable(next_tile.x, next_tile.y) or _npc_occupies_tile(next_tile)):
				message = "前方不可通行"
				return
			player_tile = next_tile
			_refresh_nearby_npc()
			_try_map_transition()
			move_cooldown = MOVE_STEP_SECONDS
			message = "当前位置: %s" % player_tile
			_update_camera()
			queue_redraw()
		else:
			player_moving = false
	if accept_requested:
		accept_requested = false
		# 确认键可能在移动/转向后的下一帧才消费；触发瞬间重新按当前位置与
		# 当前朝向解析面前一格，禁止使用已经失效的 NPC 缓存。
		_refresh_nearby_npc()
		if not nearby_npc_id.is_empty() or _has_front_interactable():
			_interact()
		elif not menu_open and not battle_ui.active:
			battle_ui.start()
	if cancel_requested:
		cancel_requested = false
		if battle_ui.active:
			battle_ui.end("你离开了战斗")
		else:
			_toggle_menu()

func _apply_facing_input(direction: Vector2) -> Vector2i:
	if direction.length() <= 0.0:
		return Vector2i.ZERO
	var requested_step := Vector2i(signi(int(direction.x)), signi(int(direction.y)))
	if requested_step.x != 0:
		requested_step.y = 0
	# 转向不受移动冷却限制。玩家按下方向后必须立即以新朝向解析交互，
	# 否则 0.15 秒移动冷却内仍会错误命中旧方向的对象。
	if facing != requested_step:
		facing = requested_step
		_refresh_nearby_npc()
		queue_redraw()
	return requested_step

func _update_continuous_skill_actions(delta: float) -> void:
	if learn_open and not learning_skill_id.is_empty():
		learning_tick_accumulator += maxf(0.0, delta)
		var learn_changed := false
		while learning_tick_accumulator >= SkillSystem.LEARNING_TICK_SECONDS and not learning_skill_id.is_empty():
			learning_tick_accumulator -= SkillSystem.LEARNING_TICK_SECONDS
			var result: Dictionary = SkillSystem.learn_tick(nearby_npc_id, learning_skill_id)
			message = str(result.get("message", ""))
			learn_changed = true
			# 原项目在升级成功或资源/门槛阻断时停止持续研习。
			if bool(result.get("ok", false)) or not str(result.get("reason", "")).is_empty():
				learning_skill_id = ""
		if learn_changed:
			_refresh_learn_list()
			_render_learning_progress()
	if practice_open and not practicing_skill_id.is_empty():
		practice_tick_accumulator += maxf(0.0, delta)
		while practice_tick_accumulator >= SkillSystem.PRACTICE_TICK_SECONDS and not practicing_skill_id.is_empty():
			practice_tick_accumulator -= SkillSystem.PRACTICE_TICK_SECONDS
			var before := SkillSystem.practice_progress(practicing_skill_id)
			var result: Dictionary = SkillSystem.practice_tick(practicing_skill_id)
			message = str(result.get("message", ""))
			var after := SkillSystem.practice_progress(practicing_skill_id)
			var failed := not bool(result.get("ok", false))
			if failed or (before == after and int(after.get("current", 0)) == 0):
				practicing_skill_id = ""
			_refresh_practice()
			if failed:
				_show_dialogue("练功", str(result.get("message", "练功失败。")))
	if meditation_open:
		meditation_tick_accumulator += maxf(0.0, delta)
		var meditation_changed := false
		while meditation_tick_accumulator >= SkillSystem.MEDITATION_TICK_SECONDS and meditation_open:
			meditation_tick_accumulator -= SkillSystem.MEDITATION_TICK_SECONDS
			var result: Dictionary = SkillSystem.meditate_tick()
			message = str(result.get("message", ""))
			if not bool(result.get("ok", false)):
				_close_meditation()
				_show_dialogue("冥想", message)
				break
			meditation_changed = true
		if meditation_changed and meditation_open:
			_render_meditation_progress()

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
		if meditation_open:
			_handle_meditation_key(event.keycode)
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
		if battle_ui.active:
			if not battle_ui.submenu.is_empty():
				battle_ui.handle_submenu_key(event.keycode)
			else:
				battle_ui.handle_key(event.keycode)
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
	return delete_confirm_open or dialogue_open or trade_open or inventory_open or learn_open or meditation_open or practice_open or skill_book_open or cyber_open or npc_menu_open or battle_ui.active or menu_open or details_panel.visible or dialogue_panel.visible

func _dispatch_virtual_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_input(event)

func _interact() -> void:
	# 不信任跨帧缓存；打开任何交互 HUD 前按玩家当前朝向重新解析目标。
	_refresh_nearby_npc()
	if nearby_npc_id.is_empty():
		if not _interact_prop():
			message = "面前没有可交互对象"
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
		var capacity := VITALS_BASE_CAPACITY + int(GameState.profile.get("attributes", {}).get("strength", 25)) * VITALS_CAPACITY_PER_STRENGTH
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
		var quest_endpoint := str(properties.get("questGiver", ""))
		var detailed: Dictionary = QuestSystem.begin_novice_completion(quest_endpoint)
		if not detailed.is_empty():
			message = str(detailed.get("message", ""))
			var after_last := Callable()
			if bool(detailed.get("can_finish", false)):
				after_last = func() -> String: return QuestSystem.finish_novice_completion(quest_endpoint)
			_show_dialogue(_prop_display_name(object), message, float(detailed.get("lock_seconds", 0.0)), after_last)
			return true
		message = QuestSystem.interact_npc(quest_endpoint)
	else:
		message = str(properties.get("text", "已查看。"))
	if event != "deleteSave" and (not str(properties.get("text", "")).is_empty() or not str(properties.get("questGiver", "")).is_empty() or event == "bountyBoard"):
		_show_dialogue(_prop_display_name(object), message)
	else:
		_show_details(message)
	return true

func _prop_display_name(object: Dictionary) -> String:
	var properties: Dictionary = object.get("properties", {})
	var display_name := str(properties.get("displayName", "")).strip_edges()
	if display_name.is_empty():
		display_name = str(object.get("name", "")).strip_edges()
	return display_name if not display_name.is_empty() else "告示"

func _show_delete_confirm() -> void:
	delete_confirm_open = true
	delete_confirm_index = 1
	npc_menu_open = false
	npc_menu_panel.visible = false
	tree_confirm_panel.visible = true
	_layout_delete_confirm()
	_refresh_delete_confirm()

func _layout_delete_confirm() -> void:
	var scale := _display_scale()
	var panel_size := Vector2(360.0, 118.0) * scale
	tree_confirm_panel.position = (DESIGN_SIZE - panel_size) * 0.5
	tree_confirm_panel.size = panel_size
	tree_confirm_content.add_theme_font_size_override("font_size", maxi(12, int(round(13.0 * scale))))

func _refresh_delete_confirm() -> void:
	tree_confirm_content.text = "这棵歪脖树正合上吊。真要吊死吗？（存档将被删除）\n\n%s    %s" % [_cursor("吊死", delete_confirm_index == 0), _cursor("再想想", delete_confirm_index == 1)]

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
	tree_confirm_panel.visible = false

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
	npc_menu_panel.visible = true
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
			npc_menu_actions.append(TRADE_MODE_BUY)
			npc_menu_labels.append("购买")
		if "pawn" in roles:
			npc_menu_actions.append(TRADE_MODE_SELL)
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
			details_panel.visible = false
			npc_menu_open = false
			npc_menu_panel.visible = false
			_clear_npc_menu_widgets()
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
			var result: Dictionary = InventorySystem.buy_item(nearby_npc_id, item_id) if trade_mode == TRADE_MODE_BUY else InventorySystem.sell_item(item_id)
			message = result.message
			if trade_mode == TRADE_MODE_SELL and bool(result.get("ok", false)):
				trade_all_items.clear()
				for entry in InventorySystem.list_entries():
					trade_all_items.append(entry.get("id", ""))
			_rebuild_trade_categories(false)
	if trade_open:
		_refresh_trade_list()

func _refresh_trade_list() -> void:
	_use_detail_hud("buy" if trade_mode == TRADE_MODE_BUY else "sell")
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	var area := details_panel.size
	var scale := _display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 27.0 * scale
	var money := int(GameState.profile.get("vitals", {}).get("money", 0))
	_detail_label("— %s —" % ("购买" if trade_mode == TRADE_MODE_BUY else "典当"), Rect2(Vector2(pad, 8.0 * scale), Vector2(area.x - pad * 2.0, 30.0 * scale)), 16, HORIZONTAL_ALIGNMENT_CENTER)
	_detail_label("持有 %d Token" % money, Rect2(Vector2(pad, 37.0 * scale), Vector2(area.x - pad * 2.0, 24.0 * scale)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	var content_top := 68.0 * scale
	var list_bottom := area.y - 52.0 * scale
	_detail_rule(Vector2(split, content_top), Vector2(split + 1.0, list_bottom), Color("77736b"))
	for category_index in trade_categories.size():
		var y := content_top + 8.0 * scale + row * category_index
		_detail_label(trade_categories[category_index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.7, row)), 13)
		if trade_focus_category and category_index == trade_category_index:
			_detail_selection(Rect2(Vector2(pad, y), Vector2(split - pad * 1.1, row)))
	if trade_items.is_empty():
		_detail_label("货已售罄" if trade_mode == TRADE_MODE_BUY else "已无可卖之物", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in trade_items.size():
			var item_id := str(trade_items[index])
			var definition: Dictionary = DataRegistry.get_item(item_id)
			var price := int(definition.get("price", 0)) if trade_mode == TRADE_MODE_BUY else int(floor(float(definition.get("price", 0)) * InventorySystem.SELL_PRICE_RATE))
			var y := content_top + 8.0 * scale + row * index
			var item_rect := Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row))
			_detail_label(str(definition.get("name", item_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 185.0 * scale, row)), 13)
			if trade_mode == TRADE_MODE_SELL:
				var remaining := InventorySystem.count(item_id)
				if remaining > 1:
					_detail_label("× %d" % remaining, Rect2(Vector2(area.x - 180.0 * scale, y), Vector2(50.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.45, 0.45, 0.45, 1))
			_detail_label("%d Token" % price, Rect2(Vector2(area.x - 120.0 * scale, y), Vector2(95.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT)
			if not trade_focus_category and index == trade_index:
				_detail_selection(item_rect)
	var footer := "↑↓ 选分类　·　空格/→ 查看　·　ESC 返回" if trade_focus_category else "↑↓ 选物品　·　空格 确认　·　←/ESC 返回"
	if not trade_focus_category and not trade_items.is_empty():
		footer = str(DataRegistry.get_item(str(trade_items[trade_index])).get("description", "暂无说明"))
	var footer_label := _detail_label(footer, Rect2(Vector2(pad, list_bottom + 6.0 * scale), Vector2(area.x - pad * 2.0, area.y - list_bottom - 12.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _item_category(item_id: String) -> String:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	var kind := str(definition.get("kind", "other"))
	if kind in ["food", "water"]: return "食物"
	if kind in ["medicine", "elixir"]: return "药物"
	var slot := str(definition.get("slot", ""))
	return {"weapon": "武器", "armor": "防具", "shoe": "鞋子", "accessory": "饰品"}.get(slot, "其他")

const TRADE_CATEGORY_ORDER := ["食物", "药物", "武器", "防具", "鞋子", "饰品", "其他"]

func _rebuild_trade_categories(reset_focus := true) -> void:
	var selected_category := trade_categories[trade_category_index] if not trade_categories.is_empty() and trade_category_index < trade_categories.size() else ""
	var previous_focus := trade_focus_category
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
	if reset_focus:
		trade_category_index = clampi(trade_category_index, 0, trade_categories.size() - 1)
		trade_focus_category = true
	else:
		var preserved_index := trade_categories.find(selected_category)
		trade_category_index = preserved_index if preserved_index >= 0 else clampi(trade_category_index, 0, trade_categories.size() - 1)
		trade_focus_category = previous_focus
	_refresh_trade_items()
	if not reset_focus and trade_items.is_empty():
		trade_focus_category = true
		_refresh_trade_list()

func _refresh_trade_items() -> void:
	trade_items = []
	var selected := trade_categories[trade_category_index] if not trade_categories.is_empty() else "其他"
	for item_id in trade_all_items:
		if _item_category(str(item_id)) == selected:
			trade_items.append(item_id)
	if trade_mode == TRADE_MODE_BUY:
		trade_items.sort_custom(func(a, b): return int(DataRegistry.get_item(str(a)).get("price", 0)) < int(DataRegistry.get_item(str(b)).get("price", 0)))
	trade_index = clampi(trade_index, 0, maxi(0, trade_items.size() - 1))
	_refresh_trade_list()

func _handle_learn_key(key: Key) -> void:
	if not learning_skill_id.is_empty():
		if key in [KEY_ESCAPE, KEY_SPACE]:
			learning_skill_id = ""
			learning_tick_accumulator = 0.0
			message = "已停止研习。"
			_clear_learning_progress_widgets()
			_refresh_learn_list()
		return
	if key == KEY_ESCAPE:
		if learn_focus_category:
			learn_open = false
			details_panel.visible = false
			learning_skill_id = ""
			learning_tick_accumulator = 0.0
			_clear_learning_progress_widgets()
			# 学习是独立 HUD，关闭后直接回到地图，不能重新弹出 NPC 菜单，
			# 更不能继续执行函数末尾的刷新而把两个面板叠在一起。
			_close_npc_menu()
		else:
			learn_focus_category = true
			_refresh_learn_items()
		return
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
			learning_skill_id = learn_items[learn_index]
			learning_tick_accumulator = 0.0
			message = "开始研习【%s】。" % DataRegistry.get_skill(learning_skill_id).get("name", learning_skill_id)
			_render_learning_progress()
	_refresh_learn_list()

func _refresh_learn_list() -> void:
	_render_learn_widgets()

func _render_learn_widgets() -> void:
	_use_detail_hud("learn")
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	var area := details_panel.size
	var scale := _display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 28.0 * scale
	var content_top := 10.0 * scale
	var list_bottom := area.y - 55.0 * scale
	_detail_rule(Vector2(split, content_top), Vector2(split + 1.0, list_bottom), Color("77736b"))
	for index in learn_categories.size():
		var y := content_top + 8.0 * scale + row * index
		var category_rect := Rect2(Vector2(pad, y), Vector2(split - pad * 1.2, row))
		_detail_label(learn_categories[index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.7, row)), 13)
		if learn_focus_category and index == learn_category_index:
			_detail_selection(category_rect)
	if learn_items.is_empty():
		_detail_label("（该分类暂无功法）", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in learn_items.size():
			var skill_id := learn_items[index]
			var definition: Dictionary = DataRegistry.get_skill(skill_id)
			var y := content_top + 8.0 * scale + row * index
			var item_rect := Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row))
			_detail_label("□  %s" % str(definition.get("name", skill_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 125.0 * scale, row)), 13)
			_detail_label("%d/%d" % [SkillSystem.level(skill_id), _learn_teach_cap(skill_id)], Rect2(Vector2(area.x - 105.0 * scale, y), Vector2(80.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.35, 0.35, 0.35, 1))
			if not learn_focus_category and index == learn_index:
				_detail_selection(item_rect)
	var footer := "↑↓ 选分类　·　空格/→ 查看　·　ESC 返回"
	if not learn_focus_category and not learn_items.is_empty():
		var focused_id := learn_items[learn_index]
		var focused_progress: Dictionary = SkillSystem.learning_progress(focused_id)
		footer = "研习【%s】，进度 %d/%d。　%s" % [DataRegistry.get_skill(focused_id).get("name", focused_id), focused_progress.get("current", 0), focused_progress.get("total", 1), "研习中 · 空格/ESC 停止" if learning_skill_id == focused_id else "空格 开始研习 · ←/ESC 返回"]
	_detail_label(footer, Rect2(Vector2(pad, area.y - 42.0 * scale), Vector2(area.x - pad * 2.0, 30.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))

func _learn_teach_cap(skill_id: String) -> int:
	return SkillSystem.teach_cap(nearby_npc_id, skill_id)

func _render_learning_progress() -> void:
	_clear_learning_progress_widgets()
	if learning_skill_id.is_empty():
		return
	var progress: Dictionary = SkillSystem.learning_progress(learning_skill_id)
	var meter := UI_PROGRESS_METER.new()
	hud.add_child(meter)
	learning_progress_widgets.append(meter)
	_layout_top_progress_meter(meter)
	meter.set_font_size(maxi(11, int(round(12.0 * _display_scale()))))
	meter.set_progress(int(progress.get("current", 0)), int(progress.get("total", 1)))

func _clear_learning_progress_widgets() -> void:
	for widget in learning_progress_widgets:
		if is_instance_valid(widget):
			widget.free()
	learning_progress_widgets.clear()

func _skill_category(skill_id: String) -> String:
	var theme := str(DataRegistry.get_skill(skill_id).get("theme", ""))
	return {"code": "编码", "tune": "思维", "arch": "架构", "parry": "招架", "knowledge": "灵感"}.get(theme, "其他")

func _rebuild_learn_categories() -> void:
	learn_categories.assign(LEARN_CATEGORY_ORDER)
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
	practice_all_items = []
	var sect := str(GameState.profile.get("sect", ""))
	for skill_id in DataRegistry.skills:
		var definition: Dictionary = DataRegistry.skills[skill_id]
		if str(definition.get("category", "")) == "sect" and str(definition.get("theme", "")) != "arch" and str(definition.get("sect", "")) == sect and SkillSystem.level(str(skill_id)) > 0:
			practice_all_items.append(str(skill_id))
	practice_category_index = 0
	practice_focus_category = true
	practice_index = 0
	practice_open = true
	menu_open = false
	menu_panel.visible = false
	_refresh_practice_items()

func _refresh_practice_items() -> void:
	practice_items = []
	var selected_theme := practice_themes[practice_category_index]
	for skill_id in practice_all_items:
		if str(DataRegistry.get_skill(skill_id).get("theme", "")) == selected_theme:
			practice_items.append(skill_id)
	practice_index = clampi(practice_index, 0, maxi(0, practice_items.size() - 1))
	_refresh_practice()

func _handle_practice_key(key: Key) -> void:
	if not practicing_skill_id.is_empty():
		if key in [KEY_ESCAPE, KEY_SPACE]:
			practicing_skill_id = ""
			practice_tick_accumulator = 0.0
			message = "已停止练功。"
			_refresh_practice()
		return
	if key == KEY_ESCAPE:
		if practice_focus_category:
			practice_open = false
			details_panel.visible = false
			menu_open = false
			menu_panel.visible = false
			_clear_practice_progress_widgets()
		else:
			practice_focus_category = true
			_refresh_practice()
		return
	if key == KEY_LEFT:
		practice_focus_category = true
	elif practice_focus_category and key in [KEY_UP, KEY_DOWN]:
		var delta := -1 if key == KEY_UP else 1
		practice_category_index = posmod(practice_category_index + delta, practice_categories.size())
		practice_index = 0
		_refresh_practice_items()
		return
	elif practice_focus_category and key in [KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		practice_focus_category = false
		practice_index = 0
	elif not practice_focus_category and key == KEY_UP and not practice_items.is_empty():
		practice_index = posmod(practice_index - 1, practice_items.size())
	elif not practice_focus_category and key == KEY_DOWN and not practice_items.is_empty():
		practice_index = posmod(practice_index + 1, practice_items.size())
	elif not practice_focus_category and key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and not practice_items.is_empty():
		practicing_skill_id = practice_items[practice_index]
		practice_tick_accumulator = 0.0
		message = "开始练习【%s】。" % DataRegistry.get_skill(practicing_skill_id).get("name", practicing_skill_id)
	_refresh_practice()

func _refresh_practice() -> void:
	_use_detail_hud("practice")
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	# 动态 HUD 首次显示时，PanelContainer 的子内容尺寸可能尚未完成布局；
	# 面板自身尺寸已经由 _use_detail_hud 同步确定，必须以它作为首帧布局基准。
	var area := details_panel.size
	var scale := _display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 30.0 * scale
	var content_top := 10.0 * scale
	var list_bottom := area.y - 46.0 * scale
	_detail_rule(Vector2(split, content_top), Vector2(split + 1.0, list_bottom), Color("c5bfb2"))
	for category_index in practice_categories.size():
		var category_y := content_top + 8.0 * scale + row * category_index
		_detail_label(practice_categories[category_index], Rect2(Vector2(pad * 1.4, category_y), Vector2(split - pad * 1.6, row)), 13)
		if practice_focus_category and category_index == practice_category_index:
			_detail_selection(Rect2(Vector2(pad, category_y), Vector2(split - pad * 1.1, row)))
	if practice_items.is_empty():
		_detail_label("（该分类尚无可练功法）", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in practice_items.size():
			var skill_id := practice_items[index]
			var definition: Dictionary = DataRegistry.get_skill(skill_id)
			var y := content_top + 8.0 * scale + row * index
			_detail_label(str(definition.get("name", skill_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 125.0 * scale, row)), 13)
			_detail_label("%d/%d" % [SkillSystem.level(skill_id), SkillSystem.practice_cap(skill_id)], Rect2(Vector2(area.x - 115.0 * scale, y), Vector2(90.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.55, 0.55, 0.55, 1))
			if not practice_focus_category and index == practice_index:
				_detail_selection(Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row)))
	var footer := "练功中 · 空格/ESC 停止" if not practicing_skill_id.is_empty() else ("↑↓ 选分类　·　空格/→ 查看　·　ESC 返回" if practice_focus_category else "↑↓ 选功法　·　空格 开始练功　·　←/ESC 返回")
	_detail_label(footer, Rect2(Vector2(pad, area.y - 40.0 * scale), Vector2(area.x - pad * 2.0, 28.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	_render_practice_progress()

func _render_practice_progress() -> void:
	if practicing_skill_id.is_empty():
		_clear_practice_progress_widgets()
		return
	var progress: Dictionary = SkillSystem.practice_progress(practicing_skill_id)
	var meter
	if practice_progress_widgets.is_empty():
		meter = UI_PROGRESS_METER.new()
		hud.add_child(meter)
		practice_progress_widgets.append(meter)
		_layout_top_progress_meter(meter)
		meter.set_font_size(maxi(11, int(round(12.0 * _display_scale()))))
	else:
		meter = practice_progress_widgets[0]
	meter.set_progress(int(progress.get("current", 0)), int(progress.get("total", 1)))

func _clear_practice_progress_widgets() -> void:
	for widget in practice_progress_widgets:
		if is_instance_valid(widget):
			widget.free()
	practice_progress_widgets.clear()

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
			_show_dialogue(str(npc.get("display_name", nearby_npc_id)), dialogue)
		"view":
			_show_npc_view_panel(npc)
		"spar":
			battle_ui.lethal = false
			battle_ui.start()
			return
		"fight":
			battle_ui.lethal = true
			battle_ui.start()
			return
		TRADE_MODE_BUY:
			var stock := DataRegistry.list_vendor_stock(nearby_npc_id)
			trade_all_items = stock
			trade_mode = TRADE_MODE_BUY
			trade_category_index = 0
			trade_open = true
			_rebuild_trade_categories()
			return
		TRADE_MODE_SELL:
			trade_all_items = []
			for entry in InventorySystem.list_entries():
				trade_all_items.append(entry.get("id", ""))
			trade_mode = TRADE_MODE_SELL
			trade_category_index = 0
			trade_open = true
			_rebuild_trade_categories()
			return
		"join":
			var join_result: Dictionary = SkillSystem.join_npc(nearby_npc_id)
			_show_dialogue(str(npc.get("display_name", nearby_npc_id)), str(join_result.get("message", "")))
		"learn":
			learn_all_items = SkillSystem.learn_options_for_npc(nearby_npc_id)
			learn_category_index = 0
			learn_open = true
			_rebuild_learn_categories()
			return

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

func _npc_occupies_tile(tile: Vector2i) -> bool:
	if not map_context:
		return false
	for object in map_context.npc_objects():
		var npc_id := str(object.get("properties", {}).get("npcId", ""))
		var npc_tile := Vector2i(floori(float(object.get("x", 0.0)) / map_context.tile_width), floori(float(object.get("y", 0.0)) / map_context.tile_height))
		if tile == npc_tile and not npc_id.is_empty() and not NpcSystem.is_defeated(npc_id):
			return true
	# 悬赏目标是动态生成的运行时 NPC，不在 Tiled 地图对象列表中，
	# 须单独并入碰撞检测才会挡住玩家移动。
	var bounty: Dictionary = QuestSystem.get_bounty_target()
	return not bounty.is_empty() and _current_map_matches(str(bounty.get("map_id", ""))) and tile == _bounty_tile()

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

func _current_map_matches(map_id: String) -> bool:
	return not map_id.is_empty() and map_context and (map_context.map_id.to_lower() == map_id.to_lower() or map_context.map_id.to_lower().contains(map_id.to_lower()))

## 悬赏目标的落点选定后须记忆（QuestSystem.set_bounty_target_tile），否则每次
## 调用都会重新随机，目标会在玩家眼前逐帧瞬移。
func _bounty_tile() -> Vector2i:
	var bounty: Dictionary = QuestSystem.get_bounty_target()
	var saved_tile = bounty.get("tile", Vector2i(-1, -1))
	if saved_tile is Vector2i and saved_tile.x >= 0 and saved_tile.y >= 0:
		return saved_tile
	var selected := map_context.pick_dynamic_npc_tile()
	QuestSystem.set_bounty_target_tile(selected)
	return selected

func _toggle_menu() -> void:
	menu_open = not menu_open
	menu_panel.visible = menu_open
	map_badge_panel.visible = not menu_open
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
	if force_power_open:
		_handle_force_power_key(key)
		return
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
		var system_hints := ["赛博传送将消耗精力。选择目的地后立即传送。", "摸鱼：消磨时间并恢复体力。", "疗伤：消耗资源治疗伤势。", "保存：将当前进度写入存档。", "退出：返回标题页面，不修改当前存档。"]
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

func _select_skill_menu() -> void:
	match skill_index:
		0:
			_close_menu()
			_open_meditation()
			return
		1:
			_close_menu()
			_open_practice()
			return
		2:
			_open_force_power()
			return
		3:
			_close_menu()
			_open_skill_book()
			return

func _open_meditation() -> void:
	if not SkillSystem.can_meditate():
		_show_dialogue("冥想", "须装备基础架构与本门架构高级功法，方可冥想。")
		return
	meditation_open = true
	meditation_tick_accumulator = 0.0
	_render_meditation_progress()

func _open_force_power() -> void:
	force_power_limit = SkillSystem.force_power_cap()
	if force_power_limit <= 0:
		_set_menu_hint("加力", "须装备内功功法后方可加力。")
		return
	force_power_open = true
	force_power_value = SkillSystem.force_power()
	_refresh_force_power_hint()

func _handle_force_power_key(key: Key) -> void:
	if key in [KEY_UP, KEY_RIGHT]:
		force_power_value = mini(force_power_limit, force_power_value + 1)
		_refresh_force_power_hint()
	elif key in [KEY_DOWN, KEY_LEFT]:
		force_power_value = maxi(0, force_power_value - 1)
		_refresh_force_power_hint()
	elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_commit_force_power(true)
	elif key == KEY_ESCAPE:
		_commit_force_power(false)

func _refresh_force_power_hint() -> void:
	var detail := "命中耗 %d 精力，附加 0~%d 伤害" % [force_power_value, force_power_value * 2] if force_power_value > 0 else "当前不加力"
	_set_menu_hint("加力", "加力 %d / %d　↑↓调整 空格确认　（%s）" % [force_power_value, force_power_limit, detail])

func _commit_force_power(show_confirmation: bool) -> void:
	var result := SkillSystem.set_force_power(force_power_value)
	force_power_open = false
	_refresh_menu()
	if show_confirmation:
		var value := int(result.get("value", 0))
		var cap := int(result.get("cap", 0))
		var confirmation := "已加力 %d / %d。战斗命中时消耗 %d 精力，附加 0~%d 点伤害。" % [value, cap, value, value * 2] if value > 0 else "已取消加力（上限 %d）。" % cap
		_set_menu_hint("加力", confirmation)

func _handle_meditation_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		_close_meditation()

func _render_meditation_progress() -> void:
	_clear_meditation_widgets()
	var progress: Dictionary = SkillSystem.meditation_progress()
	var meter := UI_PROGRESS_METER.new()
	hud.add_child(meter)
	meditation_widgets.append(meter)
	_layout_meditation_widgets()
	meter.set_font_size(maxi(11, int(round(12.0 * _display_scale()))))
	meter.set_progress(int(progress.get("current", 0)), int(progress.get("total", 1)))

func _layout_meditation_widgets() -> void:
	if meditation_widgets.is_empty():
		return
	var meter := meditation_widgets[0]
	_layout_top_progress_meter(meter)

func _layout_top_progress_meter(meter: Control) -> void:
	var scale := _display_scale()
	meter.size = Vector2(330.0, 28.0) * scale
	var view_rect := _game_view_rect()
	# 学习与冥想共用：相对摄像机可见区域顶部 16px，水平居中。
	meter.position = Vector2(view_rect.position.x + (view_rect.size.x - meter.size.x) * 0.5, view_rect.position.y + 16.0 * scale)

func _clear_meditation_widgets() -> void:
	for widget in meditation_widgets:
		if is_instance_valid(widget):
			widget.free()
	meditation_widgets.clear()

func _close_meditation() -> void:
	meditation_open = false
	_clear_meditation_widgets()

func _select_system_menu() -> void:
	match system_index:
		0:
			_try_cyber_teleport()
			return
		1:
			var channel_result: Dictionary = SkillSystem.channel_hp()
			_close_menu()
			_show_dialogue("摸鱼", str(channel_result.get("message", "")))
			return
		2:
			var heal_result: Dictionary = SkillSystem.heal_injury()
			_close_menu()
			_show_dialogue("疗伤", str(heal_result.get("message", "")))
			return
		3:
			GameState.save_game()
			message = "游戏已保存"
			# 保存不会生成新窗口，继续保留当前父子菜单。
			_set_menu_hint("保存", message)
			return
		4:
			get_tree().change_scene_to_file("res://scenes/splash.tscn")
	if menu_open:
		_refresh_menu()

func _close_menu() -> void:
	menu_open = false
	system_open = false
	skill_open = false
	force_power_open = false
	menu_panel.visible = false
	map_badge_panel.visible = true
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
	var themed_panels: Array = [map_badge_panel, tree_confirm_panel, npc_menu_panel, menu_panel, battle_panel]
	for entry in detail_huds.values():
		themed_panels.append(entry.get("panel"))
	for panel in themed_panels:
		panel.add_theme_stylebox_override("panel", _ui_box(paper, ink, 1))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dialogue_box := _ui_box(warm_paper, ink, 1)
	dialogue_box.content_margin_left = 8.0
	dialogue_box.content_margin_top = 8.0
	dialogue_box.content_margin_right = 8.0
	dialogue_box.content_margin_bottom = 8.0
	dialogue_panel.add_theme_stylebox_override("panel", dialogue_box)
	map_badge.add_theme_color_override("font_color", Color("302f2b"))
	map_badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	npc_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var themed_labels: Array = [tree_confirm_content, npc_menu_content, menu_content, battle_content, dialogue_content]
	for entry in detail_huds.values():
		themed_labels.append(entry.get("content"))
	for label in themed_labels:
		label.add_theme_color_override("font_color", Color("302f2b"))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _clear_menu_widgets() -> void:
	# 菜单仅在打开、切换选项或真实窗口尺寸变化时重建。同步删除保证同一次
	# 状态刷新中不会短暂叠放旧节点和新节点。
	for widget in menu_widgets:
		if is_instance_valid(widget):
			widget.free()
	menu_widgets.clear()
	skill_menu_panel.visible = false
	system_menu_panel.visible = false

func _clear_details_widgets() -> void:
	profile_panel_open = false
	npc_view_panel_open = false
	npc_portrait.visible = false
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
	_use_detail_hud("profile")
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var attrs: Dictionary = GameState.profile.get("attributes", {})
	var base: Dictionary = GameState.profile.get("base_attributes", attrs)
	var hp_max := _npc_hp(GameState.profile, true) - int(GameState.combat_state.get("injury", 0))
	var mp_max: int = GameState.player_mp_max()
	var capacity := VITALS_BASE_CAPACITY + int(attrs.get("strength", 25)) * VITALS_CAPACITY_PER_STRENGTH
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
	panel_size.x = minf(panel_size.x, DESIGN_SIZE.x - 16.0 * scale)
	panel_size.y = minf(panel_size.y, DESIGN_SIZE.y - 16.0 * scale)
	details_panel.position = (DESIGN_SIZE - panel_size) * 0.5
	details_panel.size = panel_size

func _show_npc_view_panel(npc: Dictionary) -> void:
	_use_detail_hud("npc_view")
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
	panel_size.x = minf(panel_size.x, DESIGN_SIZE.x - 16.0 * scale)
	panel_size.y = minf(panel_size.y, DESIGN_SIZE.y - 16.0 * scale)
	details_panel.position = (DESIGN_SIZE - panel_size) * 0.5
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
	_use_detail_hud("inventory")
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	# PanelContainer updates its child rect during the next layout pass. Use the
	# already-synchronous panel size so the very first visible frame is full-size.
	var area := details_panel.size
	var scale := _display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 27.0 * scale
	var content_top := 10.0 * scale
	var list_bottom := minf(content_top + row * inventory_categories.size() + 8.0 * scale, area.y - 46.0 * scale)
	_detail_rule(Vector2(split, content_top), Vector2(split + 1.0, list_bottom), Color("77736b"))
	for index in inventory_categories.size():
		var y := content_top + 8.0 * scale + row * index
		var category_rect := Rect2(Vector2(pad, y), Vector2(split - pad * 1.2, row))
		_detail_label(inventory_categories[index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.7, row)), 13)
		if inventory_focus_category and index == inventory_category_index:
			_detail_selection(category_rect)
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
			var item_rect := Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row))
			_detail_label(mark + str(definition.get("name", item_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 110.0 * scale, row)), 13)
			_detail_label("× %d" % InventorySystem.count(item_id), Rect2(Vector2(area.x - 95.0 * scale, y), Vector2(70.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.55, 0.55, 0.55, 1))
			if not inventory_focus_category and index == inventory_index:
				_detail_selection(item_rect)
	var footer := "↑↓ 选分类　·　空格/→ 查看　·　ESC 返回"
	if not inventory_focus_category and not inventory_items.is_empty():
		var focused: Dictionary = DataRegistry.get_item(inventory_items[inventory_index])
		footer = inventory_feedback if not inventory_feedback.is_empty() else str(focused.get("description", "暂无说明"))
	var footer_label := _detail_label(footer, Rect2(Vector2(pad, list_bottom + 8.0 * scale), Vector2(area.x - pad * 2.0, area.y - list_bottom - 14.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP if not inventory_focus_category else VERTICAL_ALIGNMENT_CENTER

func _menu_label(text: String, rect: Rect2, selected: bool, host: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
	label.add_theme_font_size_override("font_size", maxi(12, int(round(14.0 * _display_scale()))))
	label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12, 1.0))
	var selection := StyleBoxFlat.new()
	selection.bg_color = Color(1, 1, 1, 0)
	if selected:
		selection.border_color = Color(0.78, 0.12, 0.06, 1.0)
		selection.border_width_left = 2
		selection.border_width_top = 2
		selection.border_width_right = 2
		selection.border_width_bottom = 2
	label.add_theme_stylebox_override("normal", selection)
	host.add_child(label)
	menu_widgets.append(label)
	return label

func _render_menu_widgets() -> void:
	_clear_menu_widgets()
	if not menu_open:
		return
	var scale := _display_scale()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.988, 0.988, 0.98, 1.0)
	bar_style.border_color = Color(0.31, 0.31, 0.31, 1.0)
	bar_style.border_width_bottom = 1
	menu_panel.add_theme_stylebox_override("panel", bar_style)
	menu_content.visible = false
	# 参考版顶栏：四项在全宽白条内居中分布，高亮框只包住文字槽，
	# 而不是把整块四分之一屏幕画成巨型按钮。
	var tab_width := 80.0 * scale
	var item_gap := 40.0 * scale
	var group_width := tab_width * MENU_ITEMS.size() + item_gap * (MENU_ITEMS.size() - 1)
	var group_x := (menu_panel.size.x - group_width) * 0.5
	var row_height := 26.0 * scale
	var row_y := (menu_panel.size.y - row_height) * 0.5
	for index in MENU_ITEMS.size():
		# 参考版的红框在 80px 文字槽左右各外扩 8px。
		var highlight_pad := 8.0 * scale
		_menu_label(MENU_ITEMS[index], Rect2(Vector2(group_x + (tab_width + item_gap) * index - highlight_pad, row_y), Vector2(tab_width + highlight_pad * 2.0, row_height)), index == menu_index, menu_items)
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
	var item_height := 26.0 * scale
	var dropdown_width := 104.0 * scale
	var dropdown_x := group_x + (tab_width + item_gap) * menu_index
	dropdown_x -= (dropdown_width - tab_width) * 0.5
	var dropdown_panel := skill_menu_panel if skill_open else system_menu_panel
	var dropdown_host := skill_menu_items if skill_open else system_menu_items
	dropdown_panel.position = Vector2(dropdown_x, menu_panel.position.y + menu_panel.size.y)
	dropdown_panel.size = Vector2(dropdown_width, item_height * dropdown_items.size())
	dropdown_panel.add_theme_stylebox_override("panel", _ui_box(Color(0.988, 0.988, 0.98, 1.0), Color(0.31, 0.31, 0.31, 1.0), 1))
	dropdown_panel.visible = true
	for index in dropdown_items.size():
		_menu_label(dropdown_items[index], Rect2(Vector2(0.0, item_height * index), Vector2(dropdown_width, item_height)), index == dropdown_index, dropdown_host)

func _npc_hp(npc: Dictionary, is_player := false) -> int:
	if is_player:
		return GameState.player_hp_max()
	var attributes: Dictionary = npc.get("attributes", {})
	return GameState.hp_max_with_mp_boost(float(attributes.get("constitution", 0)), int(npc.get("mp", 0)))

func _show_inventory() -> void:
	inventory_open = true
	inventory_category_index = 0
	inventory_focus_category = true
	inventory_feedback = ""
	_refresh_inventory_panel()
	message = "背包已打开"

func _handle_inventory_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		if inventory_focus_category:
			inventory_open = false
			details_panel.visible = false
		else:
			inventory_focus_category = true
			inventory_feedback = ""
		_refresh_inventory_panel()
		return
	if key == KEY_LEFT:
		inventory_focus_category = true
		inventory_feedback = ""
	elif inventory_focus_category and key in [KEY_UP, KEY_DOWN]:
		inventory_feedback = ""
		var delta := -1 if key == KEY_UP else 1
		inventory_category_index = posmod(inventory_category_index + delta, inventory_categories.size())
	elif inventory_focus_category and key in [KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		inventory_focus_category = false
		inventory_index = 0
		inventory_feedback = ""
	elif not inventory_focus_category and key == KEY_UP:
		inventory_feedback = ""
		inventory_index = posmod(inventory_index - 1, maxi(1, inventory_items.size()))
	elif not inventory_focus_category and key == KEY_DOWN:
		inventory_feedback = ""
		inventory_index = posmod(inventory_index + 1, maxi(1, inventory_items.size()))
	elif not inventory_focus_category and key in [KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_activate_inventory_item()
	_refresh_inventory_panel()

func _activate_inventory_item() -> void:
	if inventory_items.is_empty():
		return
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
	inventory_feedback = message

func _refresh_inventory_panel() -> void:
	var selected := inventory_categories[inventory_category_index]
	inventory_items = []
	for entry in InventorySystem.list_entries():
		var item_id := str(entry.get("id", ""))
		if selected == "丢弃" or _item_category(item_id) == selected:
			inventory_items.append(item_id)
	inventory_items.sort_custom(func(a: String, b: String) -> bool:
		return str(DataRegistry.get_item(a).get("name", a)).naturalnocasecmp_to(str(DataRegistry.get_item(b).get("name", b))) < 0
	)
	inventory_index = clampi(inventory_index, 0, maxi(0, inventory_items.size() - 1))
	_render_inventory_widgets()

func _open_skill_book() -> void:
	skill_book_open = true
	skill_book_category_index = 0
	skill_book_focus_category = true
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
		var definition: Dictionary = DataRegistry.get_skill(skill_id)
		var theme := str(definition.get("theme", ""))
		var equipped_id := SkillSystem.equipped_id(theme, str(definition.get("category", "")))
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
	_use_detail_hud("skill_book")
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	var area := details_panel.size
	var scale := _display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 30.0 * scale
	var content_top := 10.0 * scale
	_detail_rule(Vector2(split, content_top), Vector2(split + 1.0, area.y - 46.0 * scale), Color("c5bfb2"))
	for index in skill_book_categories.size():
		var y := content_top + 8.0 * scale + row * index
		_detail_label(skill_book_categories[index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.6, row)), 13)
		if skill_book_focus_category and index == skill_book_category_index:
			_detail_selection(Rect2(Vector2(pad, y), Vector2(split - pad * 1.1, row)))
	if skill_book_items.is_empty():
		_detail_label("（该分类尚未学会功法）", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in skill_book_items.size():
			var skill_id := skill_book_items[index]
			var definition: Dictionary = DataRegistry.get_skill(skill_id)
			var equipped_id := SkillSystem.equipped_id(str(definition.get("theme", "")), str(definition.get("category", "")))
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
	_use_detail_hud("generic")
	_clear_details_widgets()
	details_content.visible = true
	details_content.text = text
	details_panel.visible = true
	npc_portrait.visible = false
	details_content.add_theme_font_size_override("font_size", maxi(12, int(round(13.0 * _display_scale()))))

func _show_dialogue(speaker: String, text: String, lock_seconds: float = 0.0, after_last: Callable = Callable()) -> void:
	var clean_speaker := speaker.strip_edges()
	var clean_text := text.strip_edges()
	if clean_speaker.is_empty() and clean_text.is_empty():
		_close_dialogue()
		return
	dialogue_speaker = clean_speaker
	dialogue_after_last = after_last
	dialogue_locked_until_msec = Time.get_ticks_msec() + int(maxf(0.0, lock_seconds) * 1000.0)
	dialogue_pages = _paginate_dialogue(clean_text)
	dialogue_page_index = 0
	dialogue_auto_close_at_msec = 0
	if dialogue_pages.size() == 1 and not after_last.is_valid():
		dialogue_auto_close_at_msec = Time.get_ticks_msec() + DIALOGUE_AUTO_CLOSE_MSEC
	_render_dialogue(clean_speaker)
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

	# 原对话框固定两行：第一行说话者，第二行正文；每个逻辑/折行文本独占一页。
	return visual_lines if not visual_lines.is_empty() else [""]

func _render_dialogue(speaker: String) -> void:
	var page := dialogue_pages[clampi(dialogue_page_index, 0, maxi(0, dialogue_pages.size() - 1))]
	dialogue_content.text = "%s:\n%s" % [speaker, page] if not speaker.is_empty() else page

func _advance_dialogue() -> void:
	if dialogue_page_index < dialogue_pages.size() - 1:
		dialogue_page_index += 1
		dialogue_auto_close_at_msec = 0
		_render_dialogue(dialogue_speaker)
	else:
		if dialogue_after_last.is_valid():
			var callback := dialogue_after_last
			dialogue_after_last = Callable()
			var followup := str(callback.call())
			if followup.strip_edges().is_empty():
				_close_dialogue()
			else:
				dialogue_pages = _paginate_dialogue(followup.strip_edges())
				dialogue_page_index = 0
				dialogue_locked_until_msec = 0
				dialogue_auto_close_at_msec = Time.get_ticks_msec() + DIALOGUE_AUTO_CLOSE_MSEC if dialogue_pages.size() == 1 else 0
				_render_dialogue(dialogue_speaker)
		else:
			_close_dialogue()

func _close_dialogue() -> void:
	dialogue_open = false
	dialogue_speaker = ""
	dialogue_locked_until_msec = 0
	dialogue_auto_close_at_msec = 0
	dialogue_after_last = Callable()
	dialogue_pages.clear()
	dialogue_page_index = 0
	dialogue_panel.visible = false

func _update_dialogue_auto_close() -> void:
	if dialogue_open and dialogue_auto_close_at_msec > 0 and Time.get_ticks_msec() >= dialogue_auto_close_at_msec:
		_close_dialogue()

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
	# 首次加载地图不做淡出，否则游戏一启动就会从黑屏淡入，而非直接呈现画面。
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
		elif cyber:
			# 参考版在目标图没有合格 Transaction 时回退普通出生点。
			var fallback_spawn := map_context.spawn_point()
			if not fallback_spawn.is_empty():
				player_tile = Vector2i(int(floor(float(fallback_spawn.get("x", 0)) / map_context.tile_width)), int(floor(float(fallback_spawn.get("y", 0)) / map_context.tile_height)))
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
	var target_index := _map_index_by_id(target)
	if target_index >= 0:
		_load_map(target_index, map_context.map_id, false)

func _map_index_by_id(target: String) -> int:
	var normalized_target := target.strip_edges().to_lower()
	for index in DataRegistry.map_files.size():
		var map_id := DataRegistry.map_files[index].get_file().get_basename().to_lower()
		if map_id == normalized_target:
			return index
	return -1

func _try_cyber_teleport() -> void:
	var basic_tune_id := SkillSystem.equipped_id("tune", "basic")
	if SkillSystem.level(basic_tune_id) < CYBER_TELEPORT_SKILL_REQUIREMENT or SkillSystem.equipped_sect_skill_level("tune") < CYBER_TELEPORT_SKILL_REQUIREMENT:
		message = "赛博传送需要装备的基础轻功与特殊轻功均达到 30 级。"
		_close_menu()
		_show_dialogue("赛博传送", message)
		return
	var cost := _cyber_teleport_cost()
	if int(GameState.combat_state.mp) < cost:
		message = "精力不足，赛博传送需要 %d 精力" % cost
		_close_menu()
		_show_dialogue("赛博传送", message)
		return
	cyber_maps = []
	for index in DataRegistry.map_files.size():
		var map_id := DataRegistry.map_files[index].get_file().get_basename()
		if DataRegistry.map_type(map_id) != "inDoor":
			cyber_maps.append(index)
	if cyber_maps.is_empty():
		message = "暂无可传送的野外地图。"
		_close_menu()
		_show_dialogue("赛博传送", message)
		return
	cyber_open = true
	cyber_index = 0
	system_open = false
	skill_open = false
	_refresh_menu()
	_refresh_cyber_menu(cost)

func _handle_cyber_key(key: Key) -> void:
	var cost := _cyber_teleport_cost()
	if key == KEY_ESCAPE:
		cyber_open = false
		details_panel.visible = false
		menu_open = true
		menu_panel.visible = true
		menu_index = 3
		system_open = true
		system_index = 0
		_refresh_menu()
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
			GameState.advance_time(1.0)
			var destination := cyber_maps[cyber_index]
			cyber_open = false
			details_panel.visible = false
			_close_menu()
			_load_map(destination, map_context.map_id if map_context else "", true)
			message = "赛博传送完成，消耗 %d 精力" % cost
			return
	if cyber_open:
		_refresh_cyber_menu(cost)

func _cyber_teleport_cost() -> int:
	return maxi(1, int(ceil(float(SkillSystem.meditation_max_mp_cap()) / CYBER_TELEPORT_MP_DIVISOR)))

func _refresh_cyber_menu(cost: int) -> void:
	if active_detail_hud != "cyber" or not detail_huds.cyber.panel.visible:
		_use_detail_hud("cyber")
	if not is_instance_valid(cyber_selection_widget) or cyber_labels.size() != cyber_maps.size():
		_build_cyber_menu()
	else:
		_layout_cyber_widgets()
	message = "↑↓选择目的地　空格确认　ESC返回　消耗 %d 精力" % cost
	_set_menu_hint("赛博传送", message)

func _build_cyber_menu() -> void:
	details_content.visible = true
	details_content.text = ""
	_clear_details_widgets()
	cyber_labels.clear()
	_layout_cyber_panel()
	for position in cyber_maps.size():
		var index := cyber_maps[position]
		var map_id := DataRegistry.map_files[index].get_file().get_basename()
		var label := _detail_label(DataRegistry.map_display_name(map_id), Rect2(), 13, HORIZONTAL_ALIGNMENT_CENTER)
		cyber_labels.append(label)
	cyber_selection_widget = Panel.new()
	cyber_selection_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cyber_selection_widget.add_theme_stylebox_override("panel", _ui_box(Color(1, 1, 1, 0), Color(0.78, 0.12, 0.06, 1), 2))
	details_content.add_child(cyber_selection_widget)
	details_widgets.append(cyber_selection_widget)
	_layout_cyber_widgets()

func _layout_cyber_widgets() -> void:
	var scale := _display_scale()
	var row := 24.0 * scale
	for position in cyber_labels.size():
		var label := cyber_labels[position]
		label.position = Vector2(0.0, row * position)
		label.size = Vector2(details_panel.size.x, row)
	if is_instance_valid(cyber_selection_widget):
		cyber_selection_widget.position = Vector2(1.0 * scale, row * cyber_index)
		cyber_selection_widget.size = Vector2(details_panel.size.x - 2.0 * scale, row)

func _draw() -> void:
	var grid_origin := _map_draw_origin()
	var cell := float(TiledMapLoader.DEFAULT_TILE_SIZE) * _render_scale()
	if not map_context:
		for y in range(10):
			for x in range(TiledMapLoader.DEFAULT_TILE_SIZE):
				draw_rect(Rect2(grid_origin + Vector2(x, y) * cell, Vector2(cell - 1, cell - 1)), Color("#274f45"))
	var player_pos := _world_to_screen(Vector2(player_tile) * Vector2(TiledMapLoader.DEFAULT_TILE_SIZE, TiledMapLoader.DEFAULT_TILE_SIZE)) + Vector2(1, 1) * _render_scale()
	_draw_npcs()
	var source := _player_frame_region()
	var destination := _player_frame_draw_rect(player_pos, source)
	draw_texture_rect_region(player_texture, destination, source)

func _load_player_sprite_regions() -> void:
	player_sprite_regions.clear()
	player_sprite_layouts.clear()
	var file := FileAccess.open("res://assets/Texture/player.tpsheet", FileAccess.READ)
	if not file:
		return
	var sheet = JSON.parse_string(file.get_as_text())
	if not sheet is Dictionary:
		return
	var textures: Array = sheet.get("textures", [])
	if textures.is_empty():
		return
	var maximum_canvas_size := Vector2.ZERO
	for sprite_value in textures[0].get("sprites", []):
		var sprite: Dictionary = sprite_value
		var key := str(sprite.get("filename", "")).get_file().get_basename()
		var region: Dictionary = sprite.get("region", {})
		var margin: Dictionary = sprite.get("margin", {})
		var packed_size := Vector2(float(region.get("w", 0)), float(region.get("h", 0)))
		if key.is_empty() or packed_size.x <= 0.0 or packed_size.y <= 0.0:
			continue
		player_sprite_regions[key] = Rect2(
			float(region.get("x", 0)), float(region.get("y", 0)),
			packed_size.x, packed_size.y,
		)
		var trim_offset := Vector2(float(margin.get("x", 0)), float(margin.get("y", 0)))
		var source_canvas_size := trim_offset + packed_size + Vector2(float(margin.get("w", 0)), float(margin.get("h", 0)))
		maximum_canvas_size = maximum_canvas_size.max(source_canvas_size)
		player_sprite_layouts[key] = {
			"offset": trim_offset,
			"source_canvas_size": source_canvas_size,
		}
	# 原始动画帧画布本身存在 35～40 × 31～34 的差异。统一到所有帧的
	# 最大画布，并把较小源画布居中补齐，确保性别/方向/动作切换不改变锚点。
	for key in player_sprite_layouts:
		var layout: Dictionary = player_sprite_layouts[key]
		var source_canvas_size: Vector2 = layout.source_canvas_size
		layout.offset = (maximum_canvas_size - source_canvas_size) * 0.5 + Vector2(layout.offset)
		layout.canvas_size = maximum_canvas_size
		player_sprite_layouts[key] = layout

func _player_frame_key() -> String:
	var gender := "female" if str(GameState.profile.get("gender", "male")).to_lower() == "female" else "male"
	var direction := "down"
	if facing == Vector2i.UP: direction = "up"
	elif facing == Vector2i.LEFT: direction = "left"
	elif facing == Vector2i.RIGHT: direction = "right"
	var motion := "run" if player_moving else "idle"
	return "player_%s_%s_%s_%d" % [gender, direction, motion, posmod(animation_frame, 4)]

func _player_frame_region() -> Rect2:
	var key := _player_frame_key()
	return player_sprite_regions.get(key, player_sprite_regions.get("player_male_down_idle_0", Rect2(0, 0, 1, 1)))

func _player_frame_draw_rect(player_pos: Vector2, source: Rect2 = _player_frame_region()) -> Rect2:
	var layout: Dictionary = player_sprite_layouts.get(_player_frame_key(), {})
	var canvas_size: Vector2 = layout.get("canvas_size", source.size)
	var trim_offset: Vector2 = layout.get("offset", Vector2.ZERO)
	# 以未裁切的 40×32 逻辑画布相对 16×16 地图格居中、脚底对齐；再叠加
	# TexturePacker 的 trim offset，从而让不同裁切宽高的帧保持同一锚点。
	var canvas_origin := player_pos + Vector2((TiledMapLoader.DEFAULT_TILE_SIZE - canvas_size.x) * 0.5, TiledMapLoader.DEFAULT_TILE_SIZE - canvas_size.y) * _render_scale()
	return Rect2(canvas_origin + trim_offset * _render_scale(), source.size * _render_scale())

func _game_view_rect() -> Rect2:
	return Rect2((DESIGN_SIZE - CAMERA_SIZE) * 0.5, CAMERA_SIZE)

func _display_scale() -> float:
	# ProjectSettings 负责把固定 640×480 画布等比拉伸到窗口；UI 始终使用设计坐标。
	return 1.0

func _map_zoom() -> float:
	if not map_context:
		return 1.0
	var map_size := Vector2(map_context.width * map_context.tile_width, map_context.height * map_context.tile_height)
	# 等比 cover：至少覆盖完整相机，超出的地图内容交给 640×480 视口裁切。
	var cover_scale := maxf(CAMERA_SIZE.x / map_size.x, CAMERA_SIZE.y / map_size.y)
	return maxf(1.0, cover_scale)

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
	last_layout_viewport_size = get_viewport_rect().size
	var view_rect := _game_view_rect()
	var scale := _display_scale()
	var inset := Vector2(8, 8) * scale
	var inset_rect := Rect2(view_rect.position + inset, view_rect.size - inset * 2.0)
	map_badge_panel.position = Vector2(8, 8) * scale
	map_badge_panel.size = Vector2(132, 34) * scale
	map_badge.add_theme_font_size_override("font_size", maxi(12, int(round(13.0 * scale))))
	if profile_panel_open:
		_layout_profile_panel()
	elif npc_view_panel_open:
		_layout_npc_view_panel()
	elif cyber_open and active_detail_hud == "cyber":
		_layout_cyber_panel()
		_layout_cyber_widgets()
	else:
		_layout_details_overlay()
	_layout_battle_panel()
	if delete_confirm_open:
		_layout_delete_confirm()
	elif npc_menu_open:
		_position_npc_menu()
	else:
		npc_menu_panel.position = inset_rect.position
		npc_menu_panel.size = inset_rect.size
	menu_panel.position = Vector2.ZERO
	menu_panel.size = Vector2(DESIGN_SIZE.x, 32.0) * scale
	var dialogue_size := Vector2(minf(DESIGN_SIZE.x, view_rect.size.x / scale) - 16.0, 44.0) * scale
	var dialogue_bottom_margin := 28.0 if OS.has_feature("mobile") else 8.0
	dialogue_panel.position = Vector2(view_rect.position.x + (view_rect.size.x - dialogue_size.x) * 0.5, view_rect.end.y - dialogue_size.y - dialogue_bottom_margin * scale)
	dialogue_panel.size = dialogue_size
	dialogue_content.add_theme_font_size_override("font_size", maxi(12, int(round(12.0 * scale))))
	transition_overlay.position = Vector2.ZERO
	transition_overlay.size = DESIGN_SIZE
	if menu_open:
		_refresh_menu()
	if meditation_open:
		_layout_meditation_widgets()
	if not learning_progress_widgets.is_empty():
		_layout_top_progress_meter(learning_progress_widgets[0])
	if not practice_progress_widgets.is_empty():
		_layout_top_progress_meter(practice_progress_widgets[0])
	_update_camera()

func _layout_details_overlay() -> void:
	var scale := _display_scale()
	var overlay_size := Vector2(464.0, 304.0) * scale
	overlay_size.x = minf(overlay_size.x, DESIGN_SIZE.x - 16.0 * scale)
	overlay_size.y = minf(overlay_size.y, DESIGN_SIZE.y - 16.0 * scale)
	details_panel.position = (DESIGN_SIZE - overlay_size) * 0.5
	details_panel.size = overlay_size

func _layout_cyber_panel() -> void:
	var scale := _display_scale()
	var tab_width := 80.0 * scale
	var item_gap := 40.0 * scale
	var group_width := tab_width * MENU_ITEMS.size() + item_gap * (MENU_ITEMS.size() - 1)
	var group_x := (menu_panel.size.x - group_width) * 0.5
	var panel_width := 184.0 * scale
	var system_tab_x := group_x + (tab_width + item_gap) * 3.0
	var panel_x := system_tab_x - (panel_width - tab_width) * 0.5
	var row_height := 24.0 * scale
	details_panel.position = Vector2(panel_x, menu_panel.position.y + menu_panel.size.y)
	details_panel.size = Vector2(panel_width, row_height * maxi(1, cyber_maps.size()))

func _layout_battle_panel() -> void:
	var scale := _display_scale()
	var inset := Vector2(8.0, 8.0) * scale
	battle_panel.position = inset
	battle_panel.size = DESIGN_SIZE - inset * 2.0

func _cursor(label: String, selected: bool) -> String:
	return "【%s】" % label if selected else "  " + label
