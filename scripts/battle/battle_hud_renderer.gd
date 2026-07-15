extends RefCounted
## 战斗 HUD 的纯展示层；读取战斗界面状态并创建临时控件，不处理回合规则。

const UI_PROGRESS_METER := preload("res://scripts/ui_progress_meter.gd")
const FONT := preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")
const REPORT_MAX_ENTRIES := 8

var view: RefCounted
var game: Node

## 绑定战斗界面状态机和主场景 HUD 宿主。
func _init(battle_view: RefCounted, game_owner: Node) -> void:
	view = battle_view
	game = game_owner

## 重建一次完整战斗画面，包括头像、资源条、操作区和战报。
func refresh() -> void:
	clear_widgets()
	game.battle_content.text = ""
	var area: Vector2 = game.battle_panel.size
	var scale: float = game._display_scale()
	game.battle_panel.add_theme_stylebox_override("panel", game._ui_box(Color("a8cc6c"), Color("41493a"), 1))
	_color_rect(Rect2(Vector2(0.0, 176.0), Vector2(area.x, area.y - 176.0)), Color("84b451"))
	var left_x: float = area.x * 0.27
	var right_x: float = area.x * 0.73
	_label(str(GameState.profile.get("name", "玩家")), Rect2(Vector2(left_x - 90.0, 12.0), Vector2(180.0, 24.0)), 14, HORIZONTAL_ALIGNMENT_CENTER)
	_label(str(view.enemy.get("display_name", game.nearby_npc_id)), Rect2(Vector2(right_x - 90.0, 12.0), Vector2(180.0, 24.0)), 14, HORIZONTAL_ALIGNMENT_CENTER)
	_label("VS", Rect2(Vector2(area.x * 0.5 - 26.0, 62.0), Vector2(52.0, 32.0)), 22, HORIZONTAL_ALIGNMENT_CENTER)
	_portrait(game.player_texture, game.world_renderer.player_battle_portrait_region(), Vector2(left_x, 72.0), Vector2(44.0, 56.0))
	_portrait(game.npc_texture, NpcSystem.sprite_region(game.nearby_npc_id), Vector2(right_x, 72.0), Vector2(44.0, 56.0))
	_render_stats(area)
	if not view.ended:
		if view.submenu.is_empty():
			_render_action_bar(area, scale)
		else:
			_render_submenu(area, scale)
	_render_report(area, scale)

## 绘制双方当前体力、精力及玩家有效体力上限百分比。
func _render_stats(area: Vector2) -> void:
	var player_hp_max := int(view.session.get("player_max_hp", game._npc_hp(GameState.profile, true)))
	var enemy_hp_max := int(view.session.get("enemy_max_hp", view.enemy_hp))
	var player_mp_max := GameState.player_mp_max()
	var enemy_mp_max := int(view.session.get("enemy_mp_max", 0))
	var true_player_hp_max := maxi(1, int(view.session.get("player_true_max_hp", GameState.player_hp_max())))
	var hp_max_percent := clampi(int(round(float(player_hp_max) / float(true_player_hp_max) * 100.0)), 1, 100)
	var displayed_player_hp := int(view.session.get("player_hp", GameState.combat_state.hp)) if view.ended else int(GameState.combat_state.hp)
	_stat("体力", displayed_player_hp, player_hp_max, Vector2(16.0, 116.0), Color("df352d"), 150.0, "（%d%%）" % hp_max_percent)
	_stat("精力", GameState.combat_state.mp, player_mp_max, Vector2(16.0, 142.0), Color("3478d4"), 150.0)
	_stat("体力", view.enemy_hp, enemy_hp_max, Vector2(area.x - 212.0, 116.0), Color("df352d"), 150.0)
	_stat("精力", int(view.session.get("enemy_mp", 0)), enemy_mp_max, Vector2(area.x - 212.0, 142.0), Color("3478d4"), 150.0)

## 创建半透明战报背景和限制在报告矩形内的自动换行文字。
func _render_report(area: Vector2, scale: float) -> void:
	var rect := report_rect(area, scale)
	var background := Panel.new()
	background.position = rect.position
	background.size = rect.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override("panel", game._ui_box(Color(1.0, 1.0, 1.0, 0.10), Color(1.0, 1.0, 1.0, 0.0), 0))
	game.battle_content.add_child(background)
	view.widgets.append(background)
	var label_rect := rect.grow(-10.0 * scale)
	var label := _label(report_text(), label_rect, 11, HORIZONTAL_ALIGNMENT_LEFT, Color("35402e"))
	label.set_meta("battle_report", true)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.clip_text = true
	## 开启自动换行后重新施加矩形，防止长战报按最小宽度撑出面板。
	label.position = label_rect.position
	label.size = label_rect.size

## 计算战报可用区域；子菜单打开时优先放在菜单上方，空间不足则移到下方。
func report_rect(area: Vector2, scale: float) -> Rect2:
	var top := (190.0 if view.ended else 233.0) * scale
	var bottom := area.y - 12.0 * scale
	if not view.submenu.is_empty():
		var submenu_height: float = (44.0 + view.submenu_items.size() * 26.0) * scale
		var submenu_top: float = area.y - submenu_height - 76.0 * scale
		var space_above_submenu: float = submenu_top - 8.0 * scale - top
		if space_above_submenu >= 32.0 * scale:
			bottom = submenu_top - 8.0 * scale
		else:
			top = submenu_top + submenu_height + 8.0 * scale
	return Rect2(Vector2(16.0 * scale, top), Vector2(area.x - 32.0 * scale, maxf(32.0 * scale, bottom - top)))

## 返回最近八条战斗记录；尚无记录时显示主场景消息。
func report_text() -> String:
	var log: Array = view.session.get("log", [])
	if log.is_empty():
		return game.message
	var first := maxi(0, log.size() - REPORT_MAX_ENTRIES)
	var recent: Array[String] = []
	for index in range(first, log.size()):
		recent.append(str(log[index]))
	return "\n".join(recent)

## 释放上次刷新创建的全部临时控件。
func clear_widgets() -> void:
	for widget in view.widgets:
		if is_instance_valid(widget):
			widget.free()
	view.widgets.clear()

## 创建战斗界面统一文本标签并登记到临时控件列表。
func _label(text: String, rect: Rect2, font_size: int, alignment := HORIZONTAL_ALIGNMENT_LEFT, color := Color("292b26")) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", maxi(11, int(round(float(font_size) * game._display_scale()))))
	label.add_theme_color_override("font_color", color)
	game.battle_content.add_child(label)
	view.widgets.append(label)
	return label

## 创建纯色矩形并登记到临时控件列表。
func _color_rect(rect: Rect2, color: Color) -> void:
	var block := ColorRect.new()
	block.position = rect.position
	block.size = rect.size
	block.color = color
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.battle_content.add_child(block)
	view.widgets.append(block)

## 从图集中裁剪并绘制一张最近邻缩放的人物头像。
func _portrait(texture: Texture2D, region: Rect2, center: Vector2, portrait_size: Vector2) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	var portrait := TextureRect.new()
	portrait.texture = atlas
	portrait.position = center - portrait_size * 0.5
	portrait.size = portrait_size
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.battle_content.add_child(portrait)
	view.widgets.append(portrait)

## 绘制资源名称、进度条和可选后缀。
func _stat(title: String, value: int, maximum: int, position: Vector2, color: Color, meter_width: float = 190.0, suffix := "") -> void:
	var scale: float = game._display_scale()
	_label(title, Rect2(position, Vector2(42.0, 22.0) * scale), 11)
	var meter := UI_PROGRESS_METER.new()
	meter.position = position + Vector2(42.0 * scale, 2.0 * scale)
	meter.size = Vector2(meter_width, 18.0) * scale
	meter.set_font_size(maxi(9, int(round(10.0 * scale))))
	meter.set_colors(color, Color("f3f2ed"), Color("4b5145"))
	meter.set_progress(value, maximum)
	game.battle_content.add_child(meter)
	view.widgets.append(meter)
	if not suffix.is_empty():
		_label(suffix, Rect2(position + Vector2(42.0 + meter_width, 0.0) * scale, Vector2(58.0, 22.0) * scale), 10)

## 绘制普通战斗操作栏及当前选择边框。
func _render_action_bar(area: Vector2, scale: float) -> void:
	var bar_size := Vector2(minf(400.0, area.x - 32.0), 42.0) * scale
	var bar_position := Vector2((area.x - bar_size.x) * 0.5, 181.0 * scale)
	var background := Panel.new()
	background.position = bar_position
	background.size = bar_size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override("panel", game._ui_box(Color("faf9f5"), Color("55524c"), 1))
	game.battle_content.add_child(background)
	view.widgets.append(background)
	var action_width := bar_size.x / float(view.ACTIONS.size())
	for index in view.ACTIONS.size():
		var rect := Rect2(bar_position + Vector2(action_width * index, 0.0), Vector2(action_width, bar_size.y))
		_label(view.ACTIONS[index], rect, 12, HORIZONTAL_ALIGNMENT_CENTER)
		if index == view.action_index:
			var selection := Panel.new()
			selection.position = rect.position + Vector2(4.0, 5.0) * scale
			selection.size = rect.size - Vector2(8.0, 10.0) * scale
			selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
			selection.add_theme_stylebox_override("panel", game._ui_box(Color(1, 1, 1, 0), Color("cf3b24"), 2))
			game.battle_content.add_child(selection)
			view.widgets.append(selection)

## 绘制药品或绝招子菜单。
func _render_submenu(area: Vector2, scale: float) -> void:
	var panel_size := Vector2(310.0, 44.0 + view.submenu_items.size() * 26.0) * scale
	var panel_position := Vector2((area.x - panel_size.x) * 0.5, area.y - panel_size.y - 76.0 * scale)
	var panel := Panel.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", game._ui_box(Color("faf9f5"), Color("55524c"), 1))
	game.battle_content.add_child(panel)
	view.widgets.append(panel)
	_label("%s　·　ESC 返回" % ("使用药品" if view.submenu == "item" else "选择绝招"), Rect2(panel_position + Vector2(10.0, 4.0) * scale, Vector2(panel_size.x - 20.0 * scale, 28.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER)
	for index in view.submenu_items.size():
		var item_label := ""
		if view.submenu == "item":
			var item_id := str(view.submenu_items[index])
			item_label = "%s ×%d" % [DataRegistry.get_item(item_id).get("name", item_id), InventorySystem.count(item_id)]
		else:
			item_label = _format_ult_label(view.submenu_items[index])
		_label(game._cursor(item_label, index == view.submenu_index), Rect2(panel_position + Vector2(18.0, 32.0 + index * 26.0) * scale, Vector2(panel_size.x - 36.0 * scale, 24.0 * scale)), 12)

## 将绝招类型、倍率、命中修正和附加效果格式化为选择项文本。
func _format_ult_label(ult: Dictionary) -> String:
	var name_cost := "%s（耗精力 %d）" % [ult.get("name", "绝招"), int(ult.get("mp_cost", 0))]
	var tier := int(ult.get("tier", 1))
	match str(ult.get("kind", "")):
		"multi": return "%s  连击%d击（每击%d%%伤、命中-5，独立判定）" % [name_cost, 3 if tier == 1 else 5, 55 if tier == 1 else 50]
		"abnormal": return "%s  %d%%伤命中+10，%d%%令对方麻痹跳%s回合" % [name_cost, 60 if tier == 1 else 70, 80 if tier == 1 else 95, "1" if tier == 1 else "1–2"]
		"reduceMax": return "%s  %d%%伤命中+5，命中后削减体力上限%d%%（同步削血）" % [name_cost, 55 if tier == 1 else 65, 8 if tier == 1 else 15]
		"hugeDamage": return "%s  %d%%倍率伤害（命中-15）" % [name_cost, 250 if tier == 1 else 400]
	return name_cost
