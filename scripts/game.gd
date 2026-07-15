extends "res://scripts/game/game_context.gd"
# 初始化ready相关逻辑，并保持调用方状态一致。
func _ready() -> void:
	battle_ui = GAME_BATTLE_UI.new(self)
	hud_layout._build_detail_huds()
	# 任务槽、冷却、环计数与动态悬赏均为本局内存态，不随存档恢复。
	QuestSystem.reset_runtime()
	# NPC 击杀隐藏同样只在一次 Game 场景存续期间有效；重新进入即全部恢复。
	NpcSystem.clear_defeated()
	MOBILE_ORIENTATION.apply()
	_install_virtual_controls()
	_apply_hud_theme()
	world_renderer.load_player_sprite_regions()
	get_viewport().size_changed.connect(_layout_game_view)
	_layout_game_view()
	dialogue_controller.update_auto_close()
	menu_content.text = ""
	map_transition_controller.load_initial_map()
	queue_redraw()

# 处理detail、hud相关逻辑，并保持调用方状态一致。
func _use_detail_hud(kind: String, show := true) -> void:
	hud_layout._use_detail_hud(kind, show)

# 处理process相关逻辑，并保持调用方状态一致。
func _process(delta: float) -> void:
	game_runtime_controller._process(delta)

# 应用facing、input相关逻辑，并保持调用方状态一致。
func _apply_facing_input(direction: Vector2) -> Vector2i:
	return game_runtime_controller._apply_facing_input(direction)

# 更新continuous、skill、actions相关逻辑，并保持调用方状态一致。
func _update_continuous_skill_actions(delta: float) -> void:
	game_runtime_controller._update_continuous_skill_actions(delta)

# 接收输入input相关逻辑，并保持调用方状态一致。
func _input(event: InputEvent) -> void:
	game_runtime_controller._input(event)

# 处理virtual、controls相关逻辑，并保持调用方状态一致。
func _install_virtual_controls() -> void:
	game_runtime_controller._install_virtual_controls()

# 处理virtual、key、down相关逻辑，并保持调用方状态一致。
func _on_virtual_key_down(keycode: int) -> void:
	game_runtime_controller._on_virtual_key_down(keycode)

# 处理virtual、key、up相关逻辑，并保持调用方状态一致。
func _on_virtual_key_up(keycode: int) -> void:
	game_runtime_controller._on_virtual_key_up(keycode)

# 判断是否具备modal、input相关逻辑，并保持调用方状态一致。
func _has_modal_input() -> bool:
	return game_runtime_controller._has_modal_input()

# 处理virtual、key相关逻辑，并保持调用方状态一致。
func _dispatch_virtual_key(keycode: int) -> void:
	game_runtime_controller._dispatch_virtual_key(keycode)

# 处理interact相关逻辑，并保持调用方状态一致。
func _interact() -> void:
	interaction_controller._interact()

# 处理display、name相关逻辑，并保持调用方状态一致。
func _prop_display_name(object: Dictionary) -> String:
	return interaction_controller._prop_display_name(object)

# 显示delete、confirm相关逻辑，并保持调用方状态一致。
func _show_delete_confirm() -> void:
	interaction_controller._show_delete_confirm()

# 处理delete、confirm相关逻辑，并保持调用方状态一致。
func _layout_delete_confirm() -> void:
	interaction_controller._layout_delete_confirm()

# 处理delete、confirm、key相关逻辑，并保持调用方状态一致。
func _handle_delete_confirm_key(key: Key) -> void:
	interaction_controller._handle_delete_confirm_key(key)

# 关闭delete、confirm相关逻辑，并保持调用方状态一致。
func _close_delete_confirm() -> void:
	interaction_controller._close_delete_confirm()

# 判断是否具备front、interactable相关逻辑，并保持调用方状态一致。
func _has_front_interactable() -> bool:
	return interaction_controller._has_front_interactable()

# 处理npc、menu、key相关逻辑，并保持调用方状态一致。
func _handle_npc_menu_key(key: Key) -> void:
	interaction_controller._handle_npc_menu_key(key)

# 清理npc、menu、widgets相关逻辑，并保持调用方状态一致。
func _clear_npc_menu_widgets() -> void:
	interaction_controller._clear_npc_menu_widgets()

# 关闭npc、menu相关逻辑，并保持调用方状态一致。
func _close_npc_menu() -> void:
	interaction_controller._close_npc_menu()

# 处理npc、menu相关逻辑，并保持调用方状态一致。
func _position_npc_menu() -> void:
	interaction_controller._position_npc_menu()

# 处理trade、key相关逻辑，并保持调用方状态一致。
func _handle_trade_key(key: Key) -> void:
	trade_controller.handle_key(key)

# 处理category相关逻辑，并保持调用方状态一致。
func _item_category(item_id: String) -> String:
	return trade_controller.item_category(item_id)

# 处理trade、categories相关逻辑，并保持调用方状态一致。
func _rebuild_trade_categories(reset_focus := true) -> void:
	trade_controller.rebuild_categories(reset_focus)

# 刷新trade、items相关逻辑，并保持调用方状态一致。
func _refresh_trade_items() -> void:
	trade_controller.refresh_items()

# 处理learn、key相关逻辑，并保持调用方状态一致。
func _handle_learn_key(key: Key) -> void:
	learning_controller.handle_key(key)

# 刷新learn、list相关逻辑，并保持调用方状态一致。
func _refresh_learn_list() -> void:
	learning_controller.render()

# 渲染learning、progress相关逻辑，并保持调用方状态一致。
func _render_learning_progress() -> void:
	learning_controller.render_progress()

# 清理learning、progress、widgets相关逻辑，并保持调用方状态一致。
func _clear_learning_progress_widgets() -> void:
	learning_controller.clear_progress()

# 处理learn、categories相关逻辑，并保持调用方状态一致。
func _rebuild_learn_categories() -> void:
	learning_controller.rebuild_categories()

# 打开practice相关逻辑，并保持调用方状态一致。
func _open_practice() -> void:
	practice_controller.open()

# 处理practice、key相关逻辑，并保持调用方状态一致。
func _handle_practice_key(key: Key) -> void:
	practice_controller.handle_key(key)

# 刷新practice相关逻辑，并保持调用方状态一致。
func _refresh_practice() -> void:
	practice_controller.render()

# 刷新nearby、npc相关逻辑，并保持调用方状态一致。
func _refresh_nearby_npc() -> void:
	npc_world_controller.refresh_nearby()

# 处理occupies、tile相关逻辑，并保持调用方状态一致。
func _npc_occupies_tile(tile: Vector2i) -> bool:
	return npc_world_controller.occupies_tile(tile)

# 绘制npcs相关逻辑，并保持调用方状态一致。
func _draw_npcs() -> void:
	npc_world_controller.draw_npcs()

# 切换menu相关逻辑，并保持调用方状态一致。
func _toggle_menu() -> void:
	menu_controller._toggle_menu()

# 处理menu、key相关逻辑，并保持调用方状态一致。
func _handle_menu_key(key: Key) -> void:
	menu_controller._handle_menu_key(key)

# 刷新menu相关逻辑，并保持调用方状态一致。
func _refresh_menu() -> void:
	menu_controller._refresh_menu()

# 选择skill、menu相关逻辑，并保持调用方状态一致。
func _select_skill_menu() -> void:
	menu_controller._select_skill_menu()

# 处理meditation、key相关逻辑，并保持调用方状态一致。
func _handle_meditation_key(key: Key) -> void:
	menu_controller._handle_meditation_key(key)

# 渲染meditation、progress相关逻辑，并保持调用方状态一致。
func _render_meditation_progress() -> void:
	menu_controller._render_meditation_progress()

# 处理meditation、widgets相关逻辑，并保持调用方状态一致。
func _layout_meditation_widgets() -> void:
	menu_controller._layout_meditation_widgets()

# 处理top、progress、meter相关逻辑，并保持调用方状态一致。
func _layout_top_progress_meter(meter: Control) -> void:
	menu_controller._layout_top_progress_meter(meter)

# 清理meditation、widgets相关逻辑，并保持调用方状态一致。
func _clear_meditation_widgets() -> void:
	menu_controller._clear_meditation_widgets()

# 关闭meditation相关逻辑，并保持调用方状态一致。
func _close_meditation() -> void:
	menu_controller._close_meditation()

# 选择system、menu相关逻辑，并保持调用方状态一致。
func _select_system_menu() -> void:
	menu_controller._select_system_menu()

# 关闭menu相关逻辑，并保持调用方状态一致。
func _close_menu() -> void:
	menu_controller._close_menu()

# 设置menu、hint相关逻辑，并保持调用方状态一致。
func _set_menu_hint(title: String, text: String) -> void:
	menu_controller._set_menu_hint(title, text)

# 处理box相关逻辑，并保持调用方状态一致。
func _ui_box(fill: Color, border: Color = Color(0.25, 0.25, 0.25, 1.0), border_width: int = 1) -> StyleBoxFlat:
	return hud_views._ui_box(fill, border, border_width)

# 应用hud、theme相关逻辑，并保持调用方状态一致。
func _apply_hud_theme() -> void:
	hud_views._apply_hud_theme()

# 清理menu、widgets相关逻辑，并保持调用方状态一致。
func _clear_menu_widgets() -> void:
	hud_views._clear_menu_widgets()

# 清理details、widgets相关逻辑，并保持调用方状态一致。
func _clear_details_widgets() -> void:
	hud_views._clear_details_widgets()

# 处理label相关逻辑，并保持调用方状态一致。
func _detail_label(text: String, rect: Rect2, size: int = 13, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, color: Color = Color(0.18, 0.18, 0.18, 1.0)) -> Label:
	return hud_views._detail_label(text, rect, size, alignment, color)

# 处理rule相关逻辑，并保持调用方状态一致。
func _detail_rule(from: Vector2, to: Vector2, color: Color = Color(0.35, 0.35, 0.35, 1.0)) -> void:
	hud_views._detail_rule(from, to, color)

# 处理selection相关逻辑，并保持调用方状态一致。
func _detail_selection(rect: Rect2) -> void:
	hud_views._detail_selection(rect)

# 显示profile、panel相关逻辑，并保持调用方状态一致。
func _show_profile_panel() -> void:
	hud_views._show_profile_panel()

# 处理profile、panel相关逻辑，并保持调用方状态一致。
func _layout_profile_panel() -> void:
	hud_views._layout_profile_panel()

# 显示npc、view、panel相关逻辑，并保持调用方状态一致。
func _show_npc_view_panel(npc: Dictionary) -> void:
	hud_views._show_npc_view_panel(npc)

# 处理npc、view、panel相关逻辑，并保持调用方状态一致。
func _layout_npc_view_panel() -> void:
	hud_views._layout_npc_view_panel()

# 处理skill、rating相关逻辑，并保持调用方状态一致。
func _npc_skill_rating(npc: Dictionary) -> String:
	return hud_views._npc_skill_rating(npc)

# 渲染inventory、widgets相关逻辑，并保持调用方状态一致。
func _render_inventory_widgets() -> void:
	hud_views._render_inventory_widgets()

# 渲染menu、widgets相关逻辑，并保持调用方状态一致。
func _render_menu_widgets() -> void:
	hud_views._render_menu_widgets()

# 处理hp相关逻辑，并保持调用方状态一致。
func _npc_hp(npc: Dictionary, is_player := false) -> int:
	return inventory_skillbook_controller._npc_hp(npc, is_player)

# 显示inventory相关逻辑，并保持调用方状态一致。
func _show_inventory() -> void:
	inventory_skillbook_controller._show_inventory()

# 处理inventory、key相关逻辑，并保持调用方状态一致。
func _handle_inventory_key(key: Key) -> void:
	inventory_skillbook_controller._handle_inventory_key(key)

# 打开skill、book相关逻辑，并保持调用方状态一致。
func _open_skill_book() -> void:
	inventory_skillbook_controller._open_skill_book()

# 处理skill、book、key相关逻辑，并保持调用方状态一致。
func _handle_skill_book_key(key: Key) -> void:
	inventory_skillbook_controller._handle_skill_book_key(key)

# 渲染skill、book、widgets相关逻辑，并保持调用方状态一致。
func _render_skill_book_widgets() -> void:
	inventory_skillbook_controller._render_skill_book_widgets()

# 处理label相关逻辑，并保持调用方状态一致。
func _gender_label(gender: String) -> String:
	return inventory_skillbook_controller._gender_label(gender)

# 处理rating相关逻辑，并保持调用方状态一致。
func _skill_rating() -> String:
	return inventory_skillbook_controller._skill_rating()

# 处理title相关逻辑，并保持调用方状态一致。
func _appearance_title(score: int, gender: String) -> String:
	return inventory_skillbook_controller._appearance_title(score, gender)

# 显示details相关逻辑，并保持调用方状态一致。
func _show_details(text: String) -> void:
	inventory_skillbook_controller._show_details(text)

# 显示dialogue相关逻辑，并保持调用方状态一致。
func _show_dialogue(speaker: String, text: String, lock_seconds: float = 0.0, after_last: Callable = Callable()) -> void:
	dialogue_controller.show(speaker, text, lock_seconds, after_last)

# 关闭dialogue相关逻辑，并保持调用方状态一致。
func _close_dialogue() -> void:
	dialogue_controller.close()

# 加载map相关逻辑，并保持调用方状态一致。
func _load_map(index: int, arrival_from := "", cyber := false) -> void:
	map_transition_controller.load_map(index, arrival_from, cyber)

## 赛博传送要求基础与门派思维功法都达到 30 级，单独一门只代表掌握部分身法。
func _handle_cyber_key(key: Key) -> void:
	cyber_teleport_controller.handle_key(key)

# 处理cyber、widgets相关逻辑，并保持调用方状态一致。
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

# 绘制draw相关逻辑，并保持调用方状态一致。
func _draw() -> void:
	world_renderer.draw()

# 处理frame、key相关逻辑，并保持调用方状态一致。
func _player_frame_key() -> String:
	return world_renderer.player_frame_key()

# 处理view、rect相关逻辑，并保持调用方状态一致。
func _game_view_rect() -> Rect2:
	return world_renderer.game_view_rect()

# 处理scale相关逻辑，并保持调用方状态一致。
func _display_scale() -> float:
	return world_renderer.display_scale()

# 渲染scale相关逻辑，并保持调用方状态一致。
func _render_scale() -> float:
	return world_renderer.render_scale()

# 判断world、tile、visible相关逻辑，并保持调用方状态一致。
func _is_world_tile_visible(tile: Vector2) -> bool:
	return world_renderer.is_world_tile_visible(tile)

# 处理to、screen相关逻辑，并保持调用方状态一致。
func _world_to_screen(world_position: Vector2) -> Vector2:
	return world_renderer.world_to_screen(world_position)

# 更新camera相关逻辑，并保持调用方状态一致。
func _update_camera() -> void:
	world_renderer.update_camera()

# 处理game、view相关逻辑，并保持调用方状态一致。
func _layout_game_view() -> void:
	hud_layout._layout_game_view()

# 处理cyber、panel相关逻辑，并保持调用方状态一致。
func _layout_cyber_panel() -> void:
	hud_layout._layout_cyber_panel()

# 处理battle、panel相关逻辑，并保持调用方状态一致。
func _layout_battle_panel() -> void:
	hud_layout._layout_battle_panel()

# 处理cursor相关逻辑，并保持调用方状态一致。
func _cursor(label: String, selected: bool) -> String:
	return "【%s】" % label if selected else "  " + label
