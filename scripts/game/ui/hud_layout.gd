extends RefCounted
## 详情 HUD 注册与所有 Game 场景几何布局。视觉参数保持设计坐标不变。

var game: Node

# 处理init相关逻辑，并保持调用方状态一致。
func _init(owner: Node) -> void:
	game = owner

# 构建detail、huds相关逻辑，并保持调用方状态一致。
func _build_detail_huds() -> void:
	game.detail_huds["npc_view"] = {"panel": game.details_panel, "content": game.details_content}
	game.detail_widget_sets["npc_view"] = game.details_widgets
	for kind in ["profile", "inventory", "skill_book", "learn", "practice", "cyber", "buy", "sell", "generic"]:
		var panel := PanelContainer.new()
		panel.name = "%sHUD" % kind.to_pascal_case()
		panel.visible = false
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		game.hud.add_child(panel)
		var content := Label.new()
		content.name = "Content"
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
		content.add_theme_font_size_override("font_size", 13)
		panel.add_child(content)
		game.detail_huds[kind] = {"panel": panel, "content": content}
		var widget_set: Array[Control] = []
		game.detail_widget_sets[kind] = widget_set
	_use_detail_hud("generic", false)

# 处理detail、hud相关逻辑，并保持调用方状态一致。
func _use_detail_hud(kind: String, show := true) -> void:
	if not game.detail_huds.has(kind):
		return
	for entry in game.detail_huds.values():
		(entry.get("panel") as PanelContainer).visible = false
	game.active_detail_hud = kind
	var entry: Dictionary = game.detail_huds[kind]
	game.details_panel = entry.get("panel")
	game.details_content = entry.get("content")
	game.details_widgets = game.detail_widget_sets[kind]
	_layout_active_detail_hud()
	game.details_panel.visible = show

# 处理active、detail、hud相关逻辑，并保持调用方状态一致。
func _layout_active_detail_hud() -> void:
	if game.active_detail_hud == "profile":
		game._layout_profile_panel()
	elif game.active_detail_hud == "npc_view":
		game._layout_npc_view_panel()
	elif game.active_detail_hud == "cyber":
		_layout_cyber_panel()
	else:
		_layout_details_overlay()


# 处理game、view相关逻辑，并保持调用方状态一致。
func _layout_game_view() -> void:
	game.last_layout_viewport_size = game.get_viewport_rect().size
	var view_rect: Rect2 = game._game_view_rect()
	var scale: float = game._display_scale()
	var inset: Vector2 = Vector2(8, 8) * scale
	var inset_rect := Rect2(view_rect.position + inset, view_rect.size - inset * 2.0)
	game.map_badge_panel.position = Vector2(8, 8) * scale
	game.map_badge_panel.size = Vector2(132, 34) * scale
	game.map_badge.add_theme_font_size_override("font_size", maxi(12, int(round(13.0 * scale))))
	if game.profile_panel_open:
		game._layout_profile_panel()
	elif game.npc_view_panel_open:
		game._layout_npc_view_panel()
	elif game.cyber_open and game.active_detail_hud == "cyber":
		_layout_cyber_panel()
		game._layout_cyber_widgets()
	else:
		_layout_details_overlay()
	_layout_battle_panel()
	if game.delete_confirm_open:
		game._layout_delete_confirm()
	elif game.npc_menu_open:
		game._position_npc_menu()
	else:
		game.npc_menu_panel.position = inset_rect.position
		game.npc_menu_panel.size = inset_rect.size
	game.menu_panel.position = Vector2.ZERO
	game.menu_panel.size = Vector2(game.DESIGN_SIZE.x, 32.0) * scale
	var dialogue_size: Vector2 = Vector2(minf(game.DESIGN_SIZE.x, view_rect.size.x / scale) - 16.0, 44.0) * scale
	var dialogue_bottom_margin := 28.0 if OS.has_feature("mobile") else 8.0
	game.dialogue_panel.position = Vector2(view_rect.position.x + (view_rect.size.x - dialogue_size.x) * 0.5, view_rect.end.y - dialogue_size.y - dialogue_bottom_margin * scale)
	game.dialogue_panel.size = dialogue_size
	game.dialogue_content.add_theme_font_size_override("font_size", maxi(12, int(round(12.0 * scale))))
	game.transition_overlay.position = Vector2.ZERO
	game.transition_overlay.size = game.DESIGN_SIZE
	if game.menu_open:
		game._refresh_menu()
	if game.meditation_open:
		game._layout_meditation_widgets()
	if not game.learning_progress_widgets.is_empty():
		game._layout_top_progress_meter(game.learning_progress_widgets[0])
	if not game.practice_progress_widgets.is_empty():
		game._layout_top_progress_meter(game.practice_progress_widgets[0])
	game._update_camera()

# 处理details、overlay相关逻辑，并保持调用方状态一致。
func _layout_details_overlay() -> void:
	var scale: float = game._display_scale()
	var overlay_size: Vector2 = Vector2(464.0, 304.0) * scale
	overlay_size.x = minf(overlay_size.x, game.DESIGN_SIZE.x - 16.0 * scale)
	overlay_size.y = minf(overlay_size.y, game.DESIGN_SIZE.y - 16.0 * scale)
	game.details_panel.position = (game.DESIGN_SIZE - overlay_size) * 0.5
	game.details_panel.size = overlay_size

# 处理cyber、panel相关逻辑，并保持调用方状态一致。
func _layout_cyber_panel() -> void:
	var scale: float = game._display_scale()
	var tab_width: float = 80.0 * scale
	var item_gap: float = 40.0 * scale
	var group_width: float = tab_width * game.MENU_ITEMS.size() + item_gap * (game.MENU_ITEMS.size() - 1)
	var group_x: float = (game.menu_panel.size.x - group_width) * 0.5
	var panel_width: float = 184.0 * scale
	var system_tab_x: float = group_x + (tab_width + item_gap) * 3.0
	var panel_x: float = system_tab_x - (panel_width - tab_width) * 0.5
	var row_height: float = 24.0 * scale
	game.details_panel.position = Vector2(panel_x, game.menu_panel.position.y + game.menu_panel.size.y)
	game.details_panel.size = Vector2(panel_width, row_height * maxi(1, game.cyber_maps.size()))

# 处理battle、panel相关逻辑，并保持调用方状态一致。
func _layout_battle_panel() -> void:
	var scale: float = game._display_scale()
	var inset: Vector2 = Vector2(8.0, 8.0) * scale
	game.battle_panel.position = inset
	game.battle_panel.size = game.DESIGN_SIZE - inset * 2.0
