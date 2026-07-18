extends RefCounted
## 师门学习的分类、焦点、进度条与详情内容。

const UI_PROGRESS_METER := preload("res://scripts/ui_progress_meter.gd")
const UI_WIDGETS := preload("res://scripts/game/ui/ui_widgets.gd")
const CATEGORY_ORDER: Array[String] = ["编码", "思维", "架构", "招架", "灵感"]

var game: Node

func _init(owner: Node) -> void:
	game = owner

func handle_key(key: Key) -> void:
	if not game.learning_skill_id.is_empty():
		if key in [KEY_ESCAPE, KEY_SPACE]:
			game.learning_skill_id = ""
			game.learning_tick_accumulator = 0.0
			game.message = "已停止研习。"
			clear_progress()
			render()
		return
	if key == KEY_ESCAPE:
		if game.learn_focus_category:
			game.learn_open = false
			game.details_panel.visible = false
			game.learning_skill_id = ""
			game.learning_tick_accumulator = 0.0
			clear_progress()
			game._close_npc_menu()
		else:
			game.learn_focus_category = true
			refresh_items()
		return
	elif key == KEY_LEFT:
		game.learn_focus_category = true
		refresh_items()
	elif game.learn_focus_category and key in [KEY_UP, KEY_DOWN]:
		var delta := -1 if key == KEY_UP else 1
		game.learn_category_index = posmod(game.learn_category_index + delta, maxi(1, game.learn_categories.size()))
		refresh_items()
	elif game.learn_focus_category and key in [KEY_RIGHT, KEY_SPACE]:
		if not game.learn_items.is_empty():
			game.learn_focus_category = false
			game.learn_index = 0
			render()
	elif not game.learn_focus_category and key == KEY_UP:
		game.learn_index = posmod(game.learn_index - 1, maxi(1, game.learn_items.size()))
		render()
	elif not game.learn_focus_category and key == KEY_DOWN:
		game.learn_index = posmod(game.learn_index + 1, maxi(1, game.learn_items.size()))
		render()
	elif not game.learn_focus_category and key == KEY_SPACE and not game.learn_items.is_empty():
		var selected_skill: String = game.learn_items[game.learn_index]
		var resource_failure: Dictionary = SkillSystem.learning_resource_failure(selected_skill)
		if not resource_failure.is_empty():
			game.message = str(resource_failure.get("message", "资源不足。"))
			game.learning_tick_accumulator = 0.0
			clear_progress()
			render()
			return
		game.learning_skill_id = selected_skill
		game.learning_tick_accumulator = 0.0
		game.message = "开始研习【%s】。" % DataRegistry.get_skill(game.learning_skill_id).get("name", game.learning_skill_id)
		render_progress()
	render()

func render() -> void:
	game._use_detail_hud("learn")
	game.details_content.visible = true
	game.details_content.text = ""
	game._clear_details_widgets()
	var area: Vector2 = game.details_panel.size
	var scale: float = game._display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 28.0 * scale
	var content_top := 10.0 * scale
	var list_bottom := area.y - 55.0 * scale
	game._detail_rule(Vector2(split, content_top), Vector2(split + 1.0, list_bottom), Color("77736b"))
	for index in game.learn_categories.size():
		var y: float = content_top + 8.0 * scale + row * index
		var category_rect := Rect2(Vector2(pad, y), Vector2(split - pad * 1.2, row))
		game._detail_label(game.learn_categories[index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.7, row)), 13)
		if game.learn_focus_category and index == game.learn_category_index:
			game._detail_selection(category_rect)
	if game.learn_items.is_empty():
		game._detail_label("（该分类暂无功法）", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in game.learn_items.size():
			var skill_id: String = game.learn_items[index]
			var definition: Dictionary = DataRegistry.get_skill(skill_id)
			var y: float = content_top + 8.0 * scale + row * index
			var item_rect := Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row))
			game._detail_label("□  %s" % str(definition.get("name", skill_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 125.0 * scale, row)), 13)
			game._detail_label("%d/%d" % [SkillSystem.level(skill_id), teach_cap(skill_id)], Rect2(Vector2(area.x - 105.0 * scale, y), Vector2(80.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.35, 0.35, 0.35, 1))
			if not game.learn_focus_category and index == game.learn_index:
				game._detail_selection(item_rect)
## 保留运行时调用入口；学习进度由顶部进度条呈现，无需刷新面板页脚。
func update_tick_feedback() -> void:
	pass

func teach_cap(skill_id: String) -> int:
	return SkillSystem.teach_cap(game.nearby_npc_id, skill_id)

## 每个研习 tick 都会调用；复用现有进度条节点，只更新数值（同 practice_controller）。
func render_progress() -> void:
	if game.learning_skill_id.is_empty():
		clear_progress()
		return
	var progress: Dictionary = SkillSystem.learning_progress(game.learning_skill_id)
	var meter: Control
	if game.learning_progress_widgets.is_empty():
		meter = UI_PROGRESS_METER.new()
		game.hud.add_child(meter)
		game.learning_progress_widgets.append(meter)
		game._layout_top_progress_meter(meter)
		meter.set_font_size(maxi(11, int(round(12.0 * game._display_scale()))))
	else:
		meter = game.learning_progress_widgets[0]
	meter.set_progress(int(progress.get("current", 0)), int(progress.get("total", 1)))

func clear_progress() -> void:
	UI_WIDGETS.free_all(game.learning_progress_widgets)

func skill_category(skill_id: String) -> String:
	var theme := str(DataRegistry.get_skill(skill_id).get("theme", ""))
	return {"code": "编码", "tune": "思维", "arch": "架构", "parry": "招架", "knowledge": "灵感"}.get(theme, "其他")

func rebuild_categories() -> void:
	game.learn_categories.assign(CATEGORY_ORDER)
	game.learn_category_index = clampi(game.learn_category_index, 0, game.learn_categories.size() - 1)
	game.learn_focus_category = true
	refresh_items()

func refresh_items() -> void:
	game.learn_items.clear()
	var selected: String = game.learn_categories[game.learn_category_index] if not game.learn_categories.is_empty() else "其他"
	for skill_id in game.learn_all_items:
		if skill_category(skill_id) == selected:
			game.learn_items.append(skill_id)
	game.learn_index = clampi(game.learn_index, 0, maxi(0, game.learn_items.size() - 1))
	render()
