extends RefCounted
## 顶部菜单、技能/系统二级菜单、冥想与加力状态机。

const UI_PROGRESS_METER := preload("res://scripts/ui_progress_meter.gd")
const UI_WIDGETS := preload("res://scripts/game/ui/ui_widgets.gd")

var game: Node

func _init(owner: Node) -> void:
	game = owner

func _toggle_menu() -> void:
	game.menu_open = not game.menu_open
	game.menu_panel.visible = game.menu_open
	game.map_badge_panel.visible = not game.menu_open
	if game.menu_open:
		game.details_panel.visible = false
		game.menu_index = 0
		game.system_open = false
		game.skill_open = false
		_refresh_menu()
	else:
		_clear_menu_hint()
		game._clear_menu_widgets()

# 从独立详情页返回主菜单，并恢复打开该页面时对应的菜单项。
func return_to_main_menu(selected_index: int) -> void:
	game.menu_open = true
	game.menu_panel.visible = true
	game.map_badge_panel.visible = false
	game.details_panel.visible = false
	game.system_open = false
	game.skill_open = false
	game.force_power_open = false
	game.menu_index = clampi(selected_index, 0, game.MENU_ITEMS.size() - 1)
	_refresh_menu()

func _handle_menu_key(key: Key) -> void:
	if game.force_power_open:
		_handle_force_power_key(key)
		return
	if key == KEY_ESCAPE:
		if game.system_open or game.skill_open:
			game.system_open = false
			game.skill_open = false
			_refresh_menu()
		else:
			_toggle_menu()
	elif game.system_open and key in [KEY_UP, KEY_LEFT]:
		game.system_index = posmod(game.system_index - 1, game.SYSTEM_ITEMS.size())
		_refresh_menu()
	elif game.system_open and key in [KEY_DOWN, KEY_RIGHT]:
		game.system_index = posmod(game.system_index + 1, game.SYSTEM_ITEMS.size())
		_refresh_menu()
	elif game.system_open and key == KEY_SPACE:
		_select_system_menu()
	elif game.skill_open and key in [KEY_UP, KEY_LEFT]:
		game.skill_index = posmod(game.skill_index - 1, game.SKILL_ITEMS.size())
		_refresh_menu()
	elif game.skill_open and key in [KEY_DOWN, KEY_RIGHT]:
		game.skill_index = posmod(game.skill_index + 1, game.SKILL_ITEMS.size())
		_refresh_menu()
	elif game.skill_open and key == KEY_SPACE:
		_select_skill_menu()
	elif key in [KEY_LEFT, KEY_UP]:
		game.menu_index = posmod(game.menu_index - 1, game.MENU_ITEMS.size())
		_refresh_menu()
	elif key in [KEY_RIGHT, KEY_DOWN]:
		game.menu_index = posmod(game.menu_index + 1, game.MENU_ITEMS.size())
		_refresh_menu()
	elif key == KEY_SPACE:
		_select_menu()

func _refresh_menu() -> void:
	game._render_menu_widgets()
	if game.skill_open:
		var skill_hints := ["冥想：静坐调息，恢复精力。", "练功：选择已学会的门派功法修炼。", "加力：调整本次攻击额外消耗的精力与伤害。", "功法：查看已经学会的基础与门派功法。"]
		_set_menu_hint(game.SKILL_ITEMS[game.skill_index], skill_hints[game.skill_index])
	elif game.system_open:
		var system_hints := ["赛博传送将消耗精力。选择目的地后立即传送。", "摸鱼：消磨时间并恢复体力。", "疗伤：消耗资源治疗伤势。", "保存：将当前进度写入存档。", "退出：返回标题页面，不修改当前存档。"]
		_set_menu_hint(game.SYSTEM_ITEMS[game.system_index], system_hints[game.system_index])
	else:
		_clear_menu_hint()

func _select_menu() -> void:
	match game.menu_index:
		0:
			_close_menu()
			game._show_profile_panel()
			return
		1:
			_close_menu()
			game._show_inventory()
			return
		2:
			game.skill_open = true
			game.system_open = false
			game.skill_index = 0
			_refresh_menu()
			return
		3:
			game.system_open = true
			game.skill_open = false
			game.system_index = 0
			_refresh_menu()
			return
	_close_menu()

func _select_skill_menu() -> void:
	match game.skill_index:
		0:
			_close_menu()
			_open_meditation()
			return
		1:
			_close_menu()
			game._open_practice()
			return
		2:
			_open_force_power()
			return
		3:
			_close_menu()
			game._open_skill_book()
			return

func _open_meditation() -> void:
	if not SkillSystem.can_meditate():
		game._show_dialogue("冥想", "须装备基础架构与本门架构高级功法，方可冥想。")
		return
	game.meditation_open = true
	game.meditation_tick_accumulator = 0.0
	_render_meditation_progress()

func _open_force_power() -> void:
	game.force_power_limit = SkillSystem.force_power_cap()
	if game.force_power_limit <= 0:
		_set_menu_hint("加力", "须装备内功功法后方可加力。")
		return
	game.force_power_open = true
	game.force_power_value = SkillSystem.force_power()
	_refresh_force_power_hint()

func _handle_force_power_key(key: Key) -> void:
	if key in [KEY_UP, KEY_RIGHT]:
		game.force_power_value = mini(game.force_power_limit, game.force_power_value + 1)
		_refresh_force_power_hint()
	elif key in [KEY_DOWN, KEY_LEFT]:
		game.force_power_value = maxi(0, game.force_power_value - 1)
		_refresh_force_power_hint()
	elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_commit_force_power(true)
	elif key == KEY_ESCAPE:
		_commit_force_power(false)

func _refresh_force_power_hint() -> void:
	var detail := "命中耗 %d 精力，附加 0~%d 伤害" % [game.force_power_value, game.force_power_value * 2] if game.force_power_value > 0 else "当前不加力"
	_set_menu_hint("加力", "加力 %d / %d　↑↓调整 空格确认　（%s）" % [game.force_power_value, game.force_power_limit, detail])

func _commit_force_power(show_confirmation: bool) -> void:
	var result := SkillSystem.set_force_power(game.force_power_value)
	game.force_power_open = false
	_refresh_menu()
	if show_confirmation:
		var value := int(result.get("value", 0))
		var cap := int(result.get("cap", 0))
		var confirmation := "已加力 %d / %d。战斗命中时消耗 %d 精力，附加 0~%d 点伤害。" % [value, cap, value, value * 2] if value > 0 else "已取消加力（上限 %d）。" % cap
		_set_menu_hint("加力", confirmation)

func _handle_meditation_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		_close_meditation()

## 每个冥想 tick 都会调用；复用现有进度条节点，只更新数值。
func _render_meditation_progress() -> void:
	var progress: Dictionary = SkillSystem.meditation_progress()
	var meter: Control
	if game.meditation_widgets.is_empty():
		meter = UI_PROGRESS_METER.new()
		game.hud.add_child(meter)
		game.meditation_widgets.append(meter)
		_layout_meditation_widgets()
		meter.set_font_size(maxi(11, int(round(12.0 * game._display_scale()))))
	else:
		meter = game.meditation_widgets[0]
	meter.set_progress(int(progress.get("current", 0)), int(progress.get("total", 1)))

func _layout_meditation_widgets() -> void:
	if game.meditation_widgets.is_empty():
		return
	var meter: Control = game.meditation_widgets[0]
	_layout_top_progress_meter(meter)

func _layout_top_progress_meter(meter: Control) -> void:
	var scale: float = game._display_scale()
	var view_rect: Rect2 = game._game_view_rect()
	var left := maxf(view_rect.position.x + 16.0 * scale, game.map_badge_panel.position.x + game.map_badge_panel.size.x + 8.0 * scale)
	var right := view_rect.end.x - 16.0 * scale
	# 学习、练功与冥想共用：避开左侧房间名，并向右延伸至视口边距。
	meter.position = Vector2(left, view_rect.position.y + 16.0 * scale)
	meter.size = Vector2(maxf(1.0, right - left), 28.0 * scale)

func _clear_meditation_widgets() -> void:
	UI_WIDGETS.free_all(game.meditation_widgets)

func _close_meditation() -> void:
	game.meditation_open = false
	_clear_meditation_widgets()

func _select_system_menu() -> void:
	match game.system_index:
		0:
			game.cyber_teleport_controller.try_open()
			return
		1:
			var channel_result: Dictionary = SkillSystem.channel_hp()
			_close_menu()
			game._show_dialogue("摸鱼", str(channel_result.get("message", "")))
			return
		2:
			var heal_result: Dictionary = SkillSystem.heal_injury()
			_close_menu()
			game._show_dialogue("疗伤", str(heal_result.get("message", "")))
			return
		3:
			GameState.save_game()
			game.message = "游戏已保存"
			# 保存不会生成新窗口，继续保留当前父子菜单。
			_set_menu_hint("保存", game.message)
			return
		4:
			game.get_tree().change_scene_to_file("res://scenes/splash.tscn")
	if game.menu_open:
		_refresh_menu()

func _close_menu() -> void:
	game.menu_open = false
	game.system_open = false
	game.skill_open = false
	game.force_power_open = false
	game.menu_panel.visible = false
	game.map_badge_panel.visible = true
	_clear_menu_hint()
	game._clear_menu_widgets()

func _set_menu_hint(title: String, text: String) -> void:
	if game.dialogue_open:
		return
	game.dialogue_panel.visible = true
	game.dialogue_content.text = "%s：\n%s" % [title, text]
	game.dialogue_content.add_theme_font_size_override("font_size", maxi(12, int(round(12.0 * game._display_scale()))))

func _clear_menu_hint() -> void:
	if not game.dialogue_open:
		game.dialogue_panel.visible = false
