extends RefCounted
## 战斗展示层：由 game.gd 持有并通过 `game` 反向引用读写共享状态
## （message、battle_panel/battle_content 等 HUD 节点、_display_scale() 等布局辅助方法）。

const UI_PROGRESS_METER := preload("res://scripts/ui_progress_meter.gd")
const ACTIONS: Array[String] = ["攻击", "绝招", "用药", "摸鱼", "逃跑"]
const REPORT_MAX_ENTRIES := 8

var game: Node

var active := false
var enemy: Dictionary = {}
var enemy_hp := 0
var session: Dictionary = {}
var lethal := true
var submenu := ""
var submenu_index := 0
var submenu_items: Array = []
var action_index := 0
var widgets: Array[Control] = []
var ended := false
var pending_result := ""
var pending_player_died := false

func _init(owner: Node) -> void:
	game = owner

func start() -> void:
	if game.nearby_npc_id.is_empty() or not NpcSystem.can_interact(game.nearby_npc_id):
		game.message = "附近没有可战斗的 NPC"
		return
	enemy = NpcSystem.build_instance(game.nearby_npc_id)
	session = CombatSystem.create_session(game.nearby_npc_id, lethal)
	enemy_hp = int(session.get("enemy_hp", game._npc_hp(enemy)))
	action_index = 0
	ended = false
	pending_result = ""
	pending_player_died = false
	active = true
	game._layout_battle_panel()
	game.battle_panel.visible = true
	# 参照项目由思维决定先手；敌方先手时在玩家看到操作栏前先行动一次。
	if str(session.get("turn", "player")) == "enemy":
		CombatSystem.enemy_action(session)
		if _player_is_down():
			_end_defeat()
			return
	refresh()

func handle_key(key: Key) -> void:
	if ended:
		if key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			_finish_end()
		return
	if key == KEY_LEFT:
		action_index = posmod(action_index - 1, ACTIONS.size())
		refresh()
	elif key == KEY_RIGHT:
		action_index = posmod(action_index + 1, ACTIONS.size())
		refresh()
	elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_activate_action()

func _activate_action() -> void:
	match action_index:
		0:
			_attack()
		1:
			_open_submenu("ult")
		2:
			_open_submenu("item")
		3:
			_rest()
		4:
			_flee()

func _attack() -> void:
	var result: Dictionary = CombatSystem.player_attack(session)
	enemy_hp = int(session.get("enemy_hp", enemy_hp))
	if _enemy_is_down():
		_append_victory_line()
		end(BattleResolve.resolve_victory(session, lethal))
	else:
		_enemy_turn()
		if not active: return
		refresh()

func _rest() -> void:
	var rest_result: Dictionary = CombatSystem.rest(session)
	game.message = rest_result.message
	if rest_result.get("skipped", false):
		_enemy_turn()
		if not active: return
	refresh()

func _flee() -> void:
	var flee_result: Dictionary = CombatSystem.flee_action(session)
	if flee_result.get("escaped", false):
		end(BattleResolve.resolve_flee(session, lethal))
	else:
		_enemy_turn()
		if not active: return
		refresh()

func _enemy_turn() -> void:
	CombatSystem.enemy_action(session)
	enemy_hp = int(session.get("enemy_hp", enemy_hp))
	if _player_is_down():
		_end_defeat()

func _player_is_down() -> bool:
	return int(GameState.combat_state.hp) <= (0 if lethal else 1)

func _enemy_is_down() -> bool:
	return int(session.get("enemy_hp", enemy_hp)) <= (0 if lethal else 1)

func _end_defeat() -> void:
	session.log.append("你眼前一黑，倒了下去……" if lethal else "你自愧不敌，拱手认负。")
	end(BattleResolve.resolve_defeat(session, lethal), lethal)

func _append_victory_line() -> void:
	var enemy_name := str(enemy.get("display_name", game.nearby_npc_id))
	session.log.append("%s倒下了。你胜了！" % enemy_name if lethal else "%s拱手认负。你胜了！" % enemy_name)

func _open_submenu(kind: String) -> void:
	submenu = kind
	submenu_index = 0
	submenu_items = []
	if kind == "item":
		if int(GameState.combat_state.hp) >= int(session.get("player_max_hp", GameState.player_effective_hp_max())):
			submenu = ""
			game.message = "体力已满，无需用药。"
			refresh()
			return
		for entry in InventorySystem.list_entries("medicine"):
			var item_id := str(entry.get("id", ""))
			if int(DataRegistry.get_item(item_id).get("effects", {}).get("hp", 0)) > 0:
				submenu_items.append(item_id)
	else:
		for ult in SkillSystem.unlocked_ults():
			if int(GameState.combat_state.mp) >= int(ult.get("mp_cost", 0)):
				submenu_items.append(ult)
	if submenu_items.is_empty():
		submenu = ""
		game.message = "身上没有伤药。" if kind == "item" else "没有可放的绝招（精力不足或内功未到）。"
		session.log.append(game.message)
	refresh()

func handle_submenu_key(key: Key) -> void:
	if key == KEY_ESCAPE or key == KEY_LEFT:
		submenu = ""
		refresh()
		return
	if key == KEY_UP:
		submenu_index = posmod(submenu_index - 1, submenu_items.size())
	elif key == KEY_DOWN:
		submenu_index = posmod(submenu_index + 1, submenu_items.size())
	elif key == KEY_SPACE:
		if submenu == "item":
			var item_id := str(submenu_items[submenu_index])
			var item_result: Dictionary = CombatSystem.use_item(session, item_id)
			game.message = str(item_result.get("message", ""))
			submenu = ""
			if item_result.get("skipped", false):
				_enemy_turn()
				if not active: return
		else:
			var ult_result: Dictionary = CombatSystem.use_ult(session, submenu_items[submenu_index])
			if not ult_result.ok:
				game.message = str(ult_result.get("message", ""))
				if ult_result.get("skipped", false):
					_enemy_turn()
					if not active: return
				refresh()
				return
			game.message = str(ult_result.ult.get("name", "绝招"))
			submenu = ""
			enemy_hp = int(session.get("enemy_hp", enemy_hp))
			if _enemy_is_down():
				_append_victory_line()
				end(BattleResolve.resolve_victory(session, lethal))
				return
			_enemy_turn()
			if not active: return
	refresh()

func refresh() -> void:
	_clear_widgets()
	game.battle_content.text = ""
	var area: Vector2 = game.battle_panel.size
	var scale: float = game._display_scale()
	game.battle_panel.add_theme_stylebox_override("panel", game._ui_box(Color("a8cc6c"), Color("41493a"), 1))
	_color_rect(Rect2(Vector2(0.0, 176.0), Vector2(area.x, area.y - 176.0)), Color("84b451"))

	var left_x: float = area.x * 0.27
	var right_x: float = area.x * 0.73
	_label(str(GameState.profile.get("name", "玩家")), Rect2(Vector2(left_x - 90.0, 12.0), Vector2(180.0, 24.0)), 14, HORIZONTAL_ALIGNMENT_CENTER)
	_label(str(enemy.get("display_name", game.nearby_npc_id)), Rect2(Vector2(right_x - 90.0, 12.0), Vector2(180.0, 24.0)), 14, HORIZONTAL_ALIGNMENT_CENTER)
	_label("VS", Rect2(Vector2(area.x * 0.5 - 26.0, 62.0), Vector2(52.0, 32.0)), 22, HORIZONTAL_ALIGNMENT_CENTER)
	_portrait(game.player_texture, game._player_battle_portrait_region(), Vector2(left_x, 72.0), Vector2(44.0, 56.0))
	_portrait(game.npc_texture, NpcSystem.sprite_region(game.nearby_npc_id), Vector2(right_x, 72.0), Vector2(44.0, 56.0))

	var player_hp_max := int(session.get("player_max_hp", game._npc_hp(GameState.profile, true)))
	var enemy_hp_max := int(session.get("enemy_max_hp", enemy_hp))
	var player_mp_max := GameState.player_mp_max()
	var enemy_mp_max := int(session.get("enemy_mp_max", 0))
	var hp_max_percent := clampi(int(round(float(player_hp_max) / float(maxi(1, int(session.get("player_true_max_hp", GameState.player_hp_max())))) * 100.0)), 1, 100)
	var displayed_player_hp := int(session.get("player_hp", GameState.combat_state.hp)) if ended else int(GameState.combat_state.hp)
	_stat("体力", displayed_player_hp, player_hp_max, Vector2(16.0, 116.0), Color("df352d"), 150.0, "（%d%%）" % hp_max_percent)
	_stat("精力", GameState.combat_state.mp, player_mp_max, Vector2(16.0, 142.0), Color("3478d4"), 150.0)
	_stat("体力", enemy_hp, enemy_hp_max, Vector2(area.x - 212.0, 116.0), Color("df352d"), 150.0)
	_stat("精力", int(session.get("enemy_mp", 0)), enemy_mp_max, Vector2(area.x - 212.0, 142.0), Color("3478d4"), 150.0)

	if ended:
		pass
	elif submenu.is_empty():
		_render_action_bar(area, scale)
	else:
		_render_submenu(area, scale)
	var report_rect := _report_rect(area, scale)
	var report_background := Panel.new()
	report_background.position = report_rect.position
	report_background.size = report_rect.size
	report_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	report_background.add_theme_stylebox_override("panel", game._ui_box(Color(1.0, 1.0, 1.0, 0.10), Color(1.0, 1.0, 1.0, 0.0), 0))
	game.battle_content.add_child(report_background)
	widgets.append(report_background)
	var report := _report_text()
	var report_label := _label(report, report_rect.grow(-10.0 * scale), 11, HORIZONTAL_ALIGNMENT_LEFT, Color("35402e"))
	report_label.set_meta("battle_report", true)
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	report_label.clip_text = true

func _report_rect(area: Vector2, scale: float) -> Rect2:
	var top := (190.0 if ended else 233.0) * scale
	var bottom := area.y - 12.0 * scale
	if not submenu.is_empty():
		var submenu_height := (44.0 + submenu_items.size() * 26.0) * scale
		var submenu_top := area.y - submenu_height - 76.0 * scale
		var space_above_submenu := submenu_top - 8.0 * scale - top
		if space_above_submenu >= 32.0 * scale:
			bottom = submenu_top - 8.0 * scale
		else:
			top = submenu_top + submenu_height + 8.0 * scale
	return Rect2(Vector2(16.0 * scale, top), Vector2(area.x - 32.0 * scale, maxf(32.0 * scale, bottom - top)))

func _report_text() -> String:
	var log: Array = session.get("log", [])
	if log.is_empty():
		return game.message
	var first := maxi(0, log.size() - REPORT_MAX_ENTRIES)
	var recent: Array[String] = []
	for index in range(first, log.size()):
		recent.append(str(log[index]))
	return "\n".join(recent)

func _clear_widgets() -> void:
	for widget in widgets:
		if is_instance_valid(widget):
			widget.free()
	widgets.clear()

func _label(text: String, rect: Rect2, font_size: int, alignment := HORIZONTAL_ALIGNMENT_LEFT, color := Color("292b26")) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf"))
	label.add_theme_font_size_override("font_size", maxi(11, int(round(float(font_size) * game._display_scale()))))
	label.add_theme_color_override("font_color", color)
	game.battle_content.add_child(label)
	widgets.append(label)
	return label

func _color_rect(rect: Rect2, color: Color) -> void:
	var block := ColorRect.new()
	block.position = rect.position
	block.size = rect.size
	block.color = color
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.battle_content.add_child(block)
	widgets.append(block)

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
	widgets.append(portrait)

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
	widgets.append(meter)
	if not suffix.is_empty():
		_label(suffix, Rect2(position + Vector2(42.0 + meter_width, 0.0) * scale, Vector2(58.0, 22.0) * scale), 10)

func _render_action_bar(area: Vector2, scale: float) -> void:
	var bar_size := Vector2(minf(400.0, area.x - 32.0), 42.0) * scale
	var bar_position := Vector2((area.x - bar_size.x) * 0.5, 181.0 * scale)
	var background := Panel.new()
	background.position = bar_position
	background.size = bar_size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override("panel", game._ui_box(Color("faf9f5"), Color("55524c"), 1))
	game.battle_content.add_child(background)
	widgets.append(background)
	var action_width := bar_size.x / float(ACTIONS.size())
	for index in ACTIONS.size():
		var rect := Rect2(bar_position + Vector2(action_width * index, 0.0), Vector2(action_width, bar_size.y))
		_label(ACTIONS[index], rect, 12, HORIZONTAL_ALIGNMENT_CENTER)
		if index == action_index:
			var selection := Panel.new()
			selection.position = rect.position + Vector2(4.0, 5.0) * scale
			selection.size = rect.size - Vector2(8.0, 10.0) * scale
			selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
			selection.add_theme_stylebox_override("panel", game._ui_box(Color(1, 1, 1, 0), Color("cf3b24"), 2))
			game.battle_content.add_child(selection)
			widgets.append(selection)

func _render_submenu(area: Vector2, scale: float) -> void:
	var panel_size := Vector2(310.0, 44.0 + submenu_items.size() * 26.0) * scale
	var panel_position := Vector2((area.x - panel_size.x) * 0.5, area.y - panel_size.y - 76.0 * scale)
	var panel := Panel.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", game._ui_box(Color("faf9f5"), Color("55524c"), 1))
	game.battle_content.add_child(panel)
	widgets.append(panel)
	_label("%s　·　ESC 返回" % ("使用药品" if submenu == "item" else "选择绝招"), Rect2(panel_position + Vector2(10.0, 4.0) * scale, Vector2(panel_size.x - 20.0 * scale, 28.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER)
	for index in submenu_items.size():
		var item_label := ""
		if submenu == "item":
			var item_id := str(submenu_items[index])
			item_label = "%s ×%d" % [DataRegistry.get_item(item_id).get("name", item_id), InventorySystem.count(item_id)]
		else:
			item_label = _format_ult_label(submenu_items[index])
		_label(game._cursor(item_label, index == submenu_index), Rect2(panel_position + Vector2(18.0, 32.0 + index * 26.0) * scale, Vector2(panel_size.x - 36.0 * scale, 24.0 * scale)), 12)

func _format_ult_label(ult: Dictionary) -> String:
	var name_cost := "%s（耗精力 %d）" % [ult.get("name", "绝招"), int(ult.get("mp_cost", 0))]
	var tier := int(ult.get("tier", 1))
	match str(ult.get("kind", "")):
		"multi": return "%s  连击%d击（每击%d%%伤、命中-5，独立判定）" % [name_cost, 3 if tier == 1 else 5, 55 if tier == 1 else 50]
		"abnormal": return "%s  %d%%伤命中+10，%d%%令对方麻痹跳%s回合" % [name_cost, 60 if tier == 1 else 70, 80 if tier == 1 else 95, "1" if tier == 1 else "1–2"]
		"reduceMax": return "%s  %d%%伤命中+5，命中后削减体力上限%d%%（同步削血）" % [name_cost, 55 if tier == 1 else 65, 8 if tier == 1 else 15]
		"hugeDamage": return "%s  %d%%倍率伤害（命中-15）" % [name_cost, 250 if tier == 1 else 400]
	return name_cost

func end(result_message: String, player_died := false) -> void:
	ended = true
	pending_result = result_message
	pending_player_died = player_died
	submenu = ""
	submenu_items = []
	if not result_message.is_empty(): session.log.append(result_message)
	refresh()

func _finish_end() -> void:
	active = false
	ended = false
	game.battle_panel.visible = false
	_clear_widgets()
	game.message = pending_result
	if pending_player_died:
		var enemy_name := str(enemy.get("display_name", game.nearby_npc_id))
		game._show_dialogue(enemy_name, pending_result, 0.0, func() -> String:
			game.get_tree().change_scene_to_file("res://scenes/splash.tscn")
			return ""
		)
	pending_result = ""
	pending_player_died = false
