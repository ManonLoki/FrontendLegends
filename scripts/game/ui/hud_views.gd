extends RefCounted

const SKILL_RATING := preload("res://scripts/skills/skill_rating.gd")
## HUD 主题、通用控件、详情视图、背包内容与顶部菜单渲染。

var game: Node

# 处理init相关逻辑，并保持调用方状态一致。
func _init(owner: Node) -> void:
	game = owner

# 处理box相关逻辑，并保持调用方状态一致。
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

# 应用hud、theme相关逻辑，并保持调用方状态一致。
func _apply_hud_theme() -> void:
	# 延续白纸灰墨的文档视觉语言，并为所有动态模态面板统一卡片样式。
	var paper := Color("f8f6ee")
	var ink := Color("4b4943")
	var warm_paper := Color("fcfbf6")
	var themed_panels: Array = [game.map_badge_panel, game.tree_confirm_panel, game.npc_menu_panel, game.menu_panel, game.battle_panel]
	for entry in game.detail_huds.values():
		themed_panels.append(entry.get("panel"))
	for panel in themed_panels:
		panel.add_theme_stylebox_override("panel", _ui_box(paper, ink, 1))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dialogue_box := _ui_box(warm_paper, ink, 1)
	dialogue_box.content_margin_left = 8.0
	dialogue_box.content_margin_top = 8.0
	dialogue_box.content_margin_right = 8.0
	dialogue_box.content_margin_bottom = 8.0
	game.dialogue_panel.add_theme_stylebox_override("panel", dialogue_box)
	game.map_badge.add_theme_color_override("font_color", Color("302f2b"))
	game.map_badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	game.map_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.npc_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var themed_labels: Array = [game.tree_confirm_content, game.npc_menu_content, game.menu_content, game.battle_content, game.dialogue_content]
	for entry in game.detail_huds.values():
		themed_labels.append(entry.get("content"))
	for label in themed_labels:
		label.add_theme_color_override("font_color", Color("302f2b"))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

# 清理menu、widgets相关逻辑，并保持调用方状态一致。
func _clear_menu_widgets() -> void:
	# 菜单仅在打开、切换选项或真实窗口尺寸变化时重建。同步删除保证同一次
	# 状态刷新中不会短暂叠放旧节点和新节点。
	for widget in game.menu_widgets:
		if is_instance_valid(widget):
			widget.free()
	game.menu_widgets.clear()
	game.skill_menu_panel.visible = false
	game.system_menu_panel.visible = false

# 清理details、widgets相关逻辑，并保持调用方状态一致。
func _clear_details_widgets() -> void:
	game.profile_panel_open = false
	game.npc_view_panel_open = false
	game.npc_portrait.visible = false
	for widget in game.details_widgets:
		if is_instance_valid(widget):
			widget.free()
	game.details_widgets.clear()

# 处理label相关逻辑，并保持调用方状态一致。
func _detail_label(text: String, rect: Rect2, size: int = 13, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, color: Color = Color(0.18, 0.18, 0.18, 1.0)) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
	label.add_theme_font_size_override("font_size", maxi(12, int(round(float(size) * game._display_scale()))))
	label.add_theme_color_override("font_color", color)
	game.details_content.add_child(label)
	game.details_widgets.append(label)
	return label

# 处理rule相关逻辑，并保持调用方状态一致。
func _detail_rule(from: Vector2, to: Vector2, color: Color = Color(0.35, 0.35, 0.35, 1.0)) -> void:
	var rule := ColorRect.new()
	rule.color = color
	rule.position = from
	rule.size = Vector2(maxf(1.0, to.x - from.x), maxf(1.0, to.y - from.y))
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.details_content.add_child(rule)
	game.details_widgets.append(rule)

# 处理selection相关逻辑，并保持调用方状态一致。
func _detail_selection(rect: Rect2) -> void:
	var selection := Panel.new()
	selection.position = rect.position
	selection.size = rect.size
	selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection.add_theme_stylebox_override("panel", _ui_box(Color(1, 1, 1, 0), Color(0.78, 0.12, 0.06, 1), 2))
	game.details_content.add_child(selection)
	game.details_widgets.append(selection)

# 显示profile、panel相关逻辑，并保持调用方状态一致。
func _show_profile_panel() -> void:
	game._use_detail_hud("profile")
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var attrs: Dictionary = GameState.profile.get("attributes", {})
	var base: Dictionary = GameState.profile.get("base_attributes", attrs)
	var hp_max: int = GameState.player_effective_hp_max()
	var mp_max: int = GameState.player_mp_max()
	var capacity: int = game.VITALS_BASE_CAPACITY + int(attrs.get("strength", 25)) * game.VITALS_CAPACITY_PER_STRENGTH
	var appearance := int(vitals.get("appearance", 0))
	game.details_panel.visible = true
	game.details_content.visible = true
	game.details_content.text = ""
	_clear_details_widgets()
	game.profile_panel_open = true
	_layout_profile_panel()
	var scale: float = game._display_scale()
	var hp := int(GameState.combat_state.get("hp", 0))
	# 括号百分比表示伤势压低上限的程度，不表示当前剩余体力比例。
	var hp_percent := GameState.player_effective_hp_percent()
	var left_lines := [str(GameState.profile.get("name", "")), "年龄：%d" % int(vitals.get("age", 18)), str(GameState.profile.get("sect", "未拜师")) if not str(GameState.profile.get("sect", "")).is_empty() else "未拜师", "", "食物：%d / %d" % [vitals.get("food", 0), capacity], "体力：%d / %d（%d%%）" % [hp, hp_max, hp_percent], "编码：%d/%d" % [attrs.get("strength", 0), base.get("strength", 0)], "架构：%d/%d" % [attrs.get("constitution", 0), base.get("constitution", 0)], "", "Token：%d" % int(vitals.get("money", 0)), "经验：%d" % int(vitals.get("experience", 0))]
	var right_lines := [game._gender_label(str(GameState.profile.get("gender", ""))), game._appearance_title(appearance, str(GameState.profile.get("gender", "male"))), game._skill_rating(), "", "饮水：%d / %d" % [vitals.get("water", 0), capacity], "精力：%d / %d" % [GameState.combat_state.get("mp", 0), mp_max], "思维：%d/%d" % [attrs.get("agility", 0), base.get("agility", 0)], "灵感：%d/%d" % [attrs.get("wisdom", 0), base.get("wisdom", 0)], "", "潜能：%d" % int(vitals.get("potential", 0))]
	var left_label := _detail_label("\n".join(left_lines), Rect2(Vector2(30.0, 30.0) * scale, Vector2(132.0, 240.0) * scale), 12)
	var right_label := _detail_label("\n".join(right_lines), Rect2(Vector2(168.0, 30.0) * scale, Vector2(132.0, 240.0) * scale), 12, HORIZONTAL_ALIGNMENT_RIGHT)
	left_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	right_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

# 处理profile、panel相关逻辑，并保持调用方状态一致。
func _layout_profile_panel() -> void:
	var scale: float = game._display_scale()
	var panel_size: Vector2 = Vector2(330.0, 300.0) * scale
	panel_size.x = minf(panel_size.x, game.DESIGN_SIZE.x - 16.0 * scale)
	panel_size.y = minf(panel_size.y, game.DESIGN_SIZE.y - 16.0 * scale)
	game.details_panel.position = (game.DESIGN_SIZE - panel_size) * 0.5
	game.details_panel.size = panel_size

# 显示npc、view、panel相关逻辑，并保持调用方状态一致。
func _show_npc_view_panel(npc: Dictionary) -> void:
	game._use_detail_hud("npc_view")
	var atlas := AtlasTexture.new()
	atlas.atlas = game.npc_texture
	atlas.region = NpcSystem.sprite_region(game.nearby_npc_id)
	game.details_panel.visible = true
	game.details_content.visible = true
	game.details_content.text = ""
	_clear_details_widgets()
	game.npc_view_panel_open = true
	_layout_npc_view_panel()
	var scale: float = game._display_scale()
	var portrait_size: Vector2 = Vector2(48.0, 48.0) * scale
	game.npc_portrait.texture = atlas
	game.npc_portrait.position = Vector2(141.0, 16.0) * scale
	game.npc_portrait.size = portrait_size
	game.npc_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	game.npc_portrait.visible = true
	var equipment_names: Array[String] = []
	for item_id in npc.get("equipment", []):
		var item: Dictionary = DataRegistry.get_item(str(item_id))
		equipment_names.append(str(item.get("name", item_id)))
	var equipment_text := "、".join(equipment_names) if not equipment_names.is_empty() else "无"
	var age_text := str(int(npc.get("age", 0))) if npc.has("age") else "未知"
	var left_label := _detail_label("%s\n年龄：%s\n装备：%s" % [npc.get("display_name", game.nearby_npc_id), age_text, equipment_text], Rect2(Vector2(30.0, 86.0) * scale, Vector2(170.0, 58.0) * scale), 12)
	var right_label := _detail_label("%s\n%s" % [game._gender_label(str(npc.get("gender", ""))), _npc_skill_rating(npc)], Rect2(Vector2(205.0, 86.0) * scale, Vector2(95.0, 58.0) * scale), 12, HORIZONTAL_ALIGNMENT_RIGHT)
	left_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	right_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var description := _detail_label(str(npc.get("description", "")), Rect2(Vector2(30.0, 154.0) * scale, Vector2(270.0, 42.0) * scale), 12, HORIZONTAL_ALIGNMENT_LEFT)
	description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

# 处理npc、view、panel相关逻辑，并保持调用方状态一致。
func _layout_npc_view_panel() -> void:
	var scale: float = game._display_scale()
	var panel_size: Vector2 = Vector2(330.0, 220.0) * scale
	panel_size.x = minf(panel_size.x, game.DESIGN_SIZE.x - 16.0 * scale)
	panel_size.y = minf(panel_size.y, game.DESIGN_SIZE.y - 16.0 * scale)
	game.details_panel.position = (game.DESIGN_SIZE - panel_size) * 0.5
	game.details_panel.size = panel_size

# 处理skill、rating相关逻辑，并保持调用方状态一致。
func _npc_skill_rating(npc: Dictionary) -> String:
	var levels: Dictionary = npc.get("skillLevels", {})
	var equipped: Array = npc.get("equippedSkillIds", [])
	return SKILL_RATING.title(SKILL_RATING.equipped_average(levels, equipped))

# 渲染inventory、widgets相关逻辑，并保持调用方状态一致。
func _render_inventory_widgets() -> void:
	game._use_detail_hud("inventory")
	game.details_content.visible = true
	game.details_content.text = ""
	_clear_details_widgets()
	# PanelContainer 下一次布局才更新子节点矩形；首帧直接采用已同步的面板尺寸，避免内容缩小。
	var area: Vector2 = game.details_panel.size
	var scale: float = game._display_scale()
	var pad: float = 20.0 * scale
	var split: float = area.x * 0.34
	var row: float = 27.0 * scale
	var content_top: float = 10.0 * scale
	var list_bottom := minf(content_top + row * game.inventory_categories.size() + 8.0 * scale, area.y - 46.0 * scale)
	_detail_rule(Vector2(split, content_top), Vector2(split + 1.0, list_bottom), Color("77736b"))
	for index in game.inventory_categories.size():
		var y: float = content_top + 8.0 * scale + row * index
		var category_rect := Rect2(Vector2(pad, y), Vector2(split - pad * 1.2, row))
		_detail_label(game.inventory_categories[index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.7, row)), 13)
		if game.inventory_focus_category and index == game.inventory_category_index:
			_detail_selection(category_rect)
	if game.inventory_items.is_empty():
		_detail_label("（该分类暂无物品）", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in game.inventory_items.size():
			var item_id: String = game.inventory_items[index]
			var definition: Dictionary = DataRegistry.get_item(item_id)
			var y: float = content_top + 8.0 * scale + row * index
			var mark := ""
			if str(definition.get("kind", "")) == "equip":
				mark = "■  " if not InventorySystem.equipped_slot(item_id).is_empty() else "□  "
			var item_rect := Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row))
			_detail_label(mark + str(definition.get("name", item_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 110.0 * scale, row)), 13)
			_detail_label("× %d" % InventorySystem.count(item_id), Rect2(Vector2(area.x - 95.0 * scale, y), Vector2(70.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.55, 0.55, 0.55, 1))
			if not game.inventory_focus_category and index == game.inventory_index:
				_detail_selection(item_rect)
	var footer := "↑↓ 选分类　·　空格/→ 查看　·　ESC 返回"
	if not game.inventory_focus_category and not game.inventory_items.is_empty():
		var focused: Dictionary = DataRegistry.get_item(game.inventory_items[game.inventory_index])
		footer = game.inventory_feedback if not game.inventory_feedback.is_empty() else str(focused.get("description", "暂无说明"))
	var footer_label := _detail_label(footer, Rect2(Vector2(pad, list_bottom + 8.0 * scale), Vector2(area.x - pad * 2.0, area.y - list_bottom - 14.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP if not game.inventory_focus_category else VERTICAL_ALIGNMENT_CENTER

# 处理label相关逻辑，并保持调用方状态一致。
func _menu_label(text: String, rect: Rect2, selected: bool, host: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
	label.add_theme_font_size_override("font_size", maxi(12, int(round(14.0 * game._display_scale()))))
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
	game.menu_widgets.append(label)
	return label

# 渲染menu、widgets相关逻辑，并保持调用方状态一致。
func _render_menu_widgets() -> void:
	_clear_menu_widgets()
	if not game.menu_open:
		return
	var scale: float = game._display_scale()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.988, 0.988, 0.98, 1.0)
	bar_style.border_color = Color(0.31, 0.31, 0.31, 1.0)
	bar_style.border_width_bottom = 1
	game.menu_panel.add_theme_stylebox_override("panel", bar_style)
	game.menu_content.visible = false
	# 参考版顶栏：四项在全宽白条内居中分布，高亮框只包住文字槽，
	# 而不是把整块四分之一屏幕画成巨型按钮。
	var tab_width: float = 80.0 * scale
	var item_gap: float = 40.0 * scale
	var group_width: float = tab_width * game.MENU_ITEMS.size() + item_gap * (game.MENU_ITEMS.size() - 1)
	var group_x: float = (game.menu_panel.size.x - group_width) * 0.5
	var row_height: float = 26.0 * scale
	var row_y: float = (game.menu_panel.size.y - row_height) * 0.5
	for index in game.MENU_ITEMS.size():
		# 参考版的红框在 80px 文字槽左右各外扩 8px。
		var highlight_pad: float = 8.0 * scale
		_menu_label(game.MENU_ITEMS[index], Rect2(Vector2(group_x + (tab_width + item_gap) * index - highlight_pad, row_y), Vector2(tab_width + highlight_pad * 2.0, row_height)), index == game.menu_index, game.menu_items)
	var dropdown_items: Array[String] = []
	var dropdown_index := 0
	if game.skill_open:
		dropdown_items.append_array(game.SKILL_ITEMS)
		dropdown_index = game.skill_index
	elif game.system_open:
		dropdown_items.append_array(game.SYSTEM_ITEMS)
		dropdown_index = game.system_index
	if dropdown_items.is_empty():
		return
	var item_height: float = 26.0 * scale
	var dropdown_width: float = 104.0 * scale
	var dropdown_x: float = group_x + (tab_width + item_gap) * game.menu_index
	dropdown_x -= (dropdown_width - tab_width) * 0.5
	var dropdown_panel: PanelContainer = game.skill_menu_panel if game.skill_open else game.system_menu_panel
	var dropdown_host: Control = game.skill_menu_items if game.skill_open else game.system_menu_items
	dropdown_panel.position = Vector2(dropdown_x, game.menu_panel.position.y + game.menu_panel.size.y)
	dropdown_panel.size = Vector2(dropdown_width, item_height * dropdown_items.size())
	dropdown_panel.add_theme_stylebox_override("panel", _ui_box(Color(0.988, 0.988, 0.98, 1.0), Color(0.31, 0.31, 0.31, 1.0), 1))
	dropdown_panel.visible = true
	for index in dropdown_items.size():
		_menu_label(dropdown_items[index], Rect2(Vector2(0.0, item_height * index), Vector2(dropdown_width, item_height)), index == dropdown_index, dropdown_host)
