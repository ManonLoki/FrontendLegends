extends RefCounted
## 自主练功的可选功法、双栏焦点与进度条生命周期。

const UI_PROGRESS_METER := preload("res://scripts/ui_progress_meter.gd")

var game: Node

func _init(owner: Node) -> void:
	game = owner

func open() -> void:
	game.practice_all_items.clear()
	var sect := str(GameState.profile.get("sect", ""))
	for skill_id in DataRegistry.skills:
		var definition: Dictionary = DataRegistry.skills[skill_id]
		if str(definition.get("category", "")) == "sect" and str(definition.get("theme", "")) != "arch" and str(definition.get("sect", "")) == sect and SkillSystem.level(str(skill_id)) > 0:
			game.practice_all_items.append(str(skill_id))
	game.practice_category_index = 0
	game.practice_focus_category = true
	game.practice_index = 0
	game.practice_open = true
	game.menu_open = false
	game.menu_panel.visible = false
	refresh_items()

func refresh_items() -> void:
	game.practice_items.clear()
	var selected_theme: String = game.practice_themes[game.practice_category_index]
	for skill_id in game.practice_all_items:
		if str(DataRegistry.get_skill(skill_id).get("theme", "")) == selected_theme:
			game.practice_items.append(skill_id)
	game.practice_index = clampi(game.practice_index, 0, maxi(0, game.practice_items.size() - 1))
	render()

func handle_key(key: Key) -> void:
	if not game.practicing_skill_id.is_empty():
		if key in [KEY_ESCAPE, KEY_SPACE]:
			game.practicing_skill_id = ""
			game.practice_tick_accumulator = 0.0
			game.message = "已停止练功。"
			render()
		return
	if key == KEY_ESCAPE:
		if game.practice_focus_category:
			game.practice_open = false
			game.details_panel.visible = false
			game.menu_open = false
			game.menu_panel.visible = false
			clear_progress()
		else:
			game.practice_focus_category = true
			render()
		return
	if key == KEY_LEFT:
		game.practice_focus_category = true
	elif game.practice_focus_category and key in [KEY_UP, KEY_DOWN]:
		var delta := -1 if key == KEY_UP else 1
		game.practice_category_index = posmod(game.practice_category_index + delta, game.practice_categories.size())
		game.practice_index = 0
		refresh_items()
		return
	elif game.practice_focus_category and key in [KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		game.practice_focus_category = false
		game.practice_index = 0
	elif not game.practice_focus_category and key == KEY_UP and not game.practice_items.is_empty():
		game.practice_index = posmod(game.practice_index - 1, game.practice_items.size())
	elif not game.practice_focus_category and key == KEY_DOWN and not game.practice_items.is_empty():
		game.practice_index = posmod(game.practice_index + 1, game.practice_items.size())
	elif not game.practice_focus_category and key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and not game.practice_items.is_empty():
		game.practicing_skill_id = game.practice_items[game.practice_index]
		game.practice_tick_accumulator = 0.0
		game.message = "开始练习【%s】。" % DataRegistry.get_skill(game.practicing_skill_id).get("name", game.practicing_skill_id)
	render()

func render() -> void:
	game._use_detail_hud("practice")
	game.details_content.visible = true
	game.details_content.text = ""
	game._clear_details_widgets()
	var area: Vector2 = game.details_panel.size
	var scale: float = game._display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 30.0 * scale
	var content_top := 10.0 * scale
	var list_bottom := area.y - 46.0 * scale
	game._detail_rule(Vector2(split, content_top), Vector2(split + 1.0, list_bottom), Color("c5bfb2"))
	for category_index in game.practice_categories.size():
		var category_y: float = content_top + 8.0 * scale + row * category_index
		game._detail_label(game.practice_categories[category_index], Rect2(Vector2(pad * 1.4, category_y), Vector2(split - pad * 1.6, row)), 13)
		if game.practice_focus_category and category_index == game.practice_category_index:
			game._detail_selection(Rect2(Vector2(pad, category_y), Vector2(split - pad * 1.1, row)))
	if game.practice_items.is_empty():
		game._detail_label("（该分类尚无可练功法）", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in game.practice_items.size():
			var skill_id: String = game.practice_items[index]
			var definition: Dictionary = DataRegistry.get_skill(skill_id)
			var y: float = content_top + 8.0 * scale + row * index
			game._detail_label(str(definition.get("name", skill_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 125.0 * scale, row)), 13)
			game._detail_label("%d/%d" % [SkillSystem.level(skill_id), SkillSystem.practice_cap(skill_id)], Rect2(Vector2(area.x - 115.0 * scale, y), Vector2(90.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.55, 0.55, 0.55, 1))
			if not game.practice_focus_category and index == game.practice_index:
				game._detail_selection(Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row)))
	var footer := "练功中 · 空格/ESC 停止" if not game.practicing_skill_id.is_empty() else ("↑↓ 选分类　·　空格/→ 查看　·　ESC 返回" if game.practice_focus_category else "↑↓ 选功法　·　空格 开始练功　·　←/ESC 返回")
	game._detail_label(footer, Rect2(Vector2(pad, area.y - 40.0 * scale), Vector2(area.x - pad * 2.0, 28.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	render_progress()

func render_progress() -> void:
	if game.practicing_skill_id.is_empty():
		clear_progress()
		return
	var progress: Dictionary = SkillSystem.practice_progress(game.practicing_skill_id)
	var meter: Control
	if game.practice_progress_widgets.is_empty():
		meter = UI_PROGRESS_METER.new()
		game.hud.add_child(meter)
		game.practice_progress_widgets.append(meter)
		game._layout_top_progress_meter(meter)
		meter.set_font_size(maxi(11, int(round(12.0 * game._display_scale()))))
	else:
		meter = game.practice_progress_widgets[0]
	meter.set_progress(int(progress.get("current", 0)), int(progress.get("total", 1)))

func clear_progress() -> void:
	for widget in game.practice_progress_widgets:
		if is_instance_valid(widget):
			widget.free()
	game.practice_progress_widgets.clear()
