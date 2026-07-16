extends "res://scripts/game/game_context.gd"
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

func _process(delta: float) -> void:
	game_runtime_controller._process(delta)

func _apply_facing_input(direction: Vector2) -> Vector2i:
	return game_runtime_controller._apply_facing_input(direction)

func _update_continuous_skill_actions(delta: float) -> void:
	game_runtime_controller._update_continuous_skill_actions(delta)

func _input(event: InputEvent) -> void:
	game_runtime_controller._input(event)

func _install_virtual_controls() -> void:
	game_runtime_controller._install_virtual_controls()

func _on_virtual_key_down(keycode: int) -> void:
	game_runtime_controller._on_virtual_key_down(keycode)

func _on_virtual_key_up(keycode: int) -> void:
	game_runtime_controller._on_virtual_key_up(keycode)

func _has_modal_input() -> bool:
	return game_runtime_controller._has_modal_input()

func _dispatch_virtual_key(keycode: int) -> void:
	game_runtime_controller._dispatch_virtual_key(keycode)

func _interact() -> void:
	interaction_controller._interact()

func _prop_display_name(object: Dictionary) -> String:
	return interaction_controller._prop_display_name(object)

func _show_delete_confirm() -> void:
	interaction_controller._show_delete_confirm()

# 处理delete、confirm相关逻辑，并保持调用方状态一致。
func _layout_delete_confirm() -> void:
	interaction_controller._layout_delete_confirm()

func _handle_delete_confirm_key(key: Key) -> void:
	interaction_controller._handle_delete_confirm_key(key)

func _close_delete_confirm() -> void:
	interaction_controller._close_delete_confirm()

func _has_front_interactable() -> bool:
	return interaction_controller._has_front_interactable()

func _handle_npc_menu_key(key: Key) -> void:
	interaction_controller._handle_npc_menu_key(key)

func _clear_npc_menu_widgets() -> void:
	interaction_controller._clear_npc_menu_widgets()

func _close_npc_menu() -> void:
	interaction_controller._close_npc_menu()

func _position_npc_menu() -> void:
	interaction_controller._position_npc_menu()

func _handle_trade_key(key: Key) -> void:
	trade_controller.handle_key(key)

func _item_category(item_id: String) -> String:
	return trade_controller.item_category(item_id)

func _rebuild_trade_categories(reset_focus := true) -> void:
	trade_controller.rebuild_categories(reset_focus)

func _refresh_trade_items() -> void:
	trade_controller.refresh_items()

func _handle_learn_key(key: Key) -> void:
	learning_controller.handle_key(key)

func _refresh_learn_list() -> void:
	learning_controller.render()

func _render_learning_progress() -> void:
	learning_controller.render_progress()

func _clear_learning_progress_widgets() -> void:
	learning_controller.clear_progress()

func _rebuild_learn_categories() -> void:
	learning_controller.rebuild_categories()

func _open_practice() -> void:
	practice_controller.open()

func _handle_practice_key(key: Key) -> void:
	practice_controller.handle_key(key)

func _refresh_practice() -> void:
	practice_controller.render()

func _refresh_nearby_npc() -> void:
	npc_world_controller.refresh_nearby()

func _npc_occupies_tile(tile: Vector2i) -> bool:
	return npc_world_controller.occupies_tile(tile)

func _draw_npcs() -> void:
	npc_world_controller.draw_npcs()

func _toggle_menu() -> void:
	menu_controller._toggle_menu()

func _handle_menu_key(key: Key) -> void:
	menu_controller._handle_menu_key(key)

func _refresh_menu() -> void:
	menu_controller._refresh_menu()

func _select_skill_menu() -> void:
	menu_controller._select_skill_menu()

func _handle_meditation_key(key: Key) -> void:
	menu_controller._handle_meditation_key(key)

func _render_meditation_progress() -> void:
	menu_controller._render_meditation_progress()

# 处理meditation、widgets相关逻辑，并保持调用方状态一致。
func _layout_meditation_widgets() -> void:
	menu_controller._layout_meditation_widgets()

# 处理top、progress、meter相关逻辑，并保持调用方状态一致。
func _layout_top_progress_meter(meter: Control) -> void:
	menu_controller._layout_top_progress_meter(meter)

func _clear_meditation_widgets() -> void:
	menu_controller._clear_meditation_widgets()

func _close_meditation() -> void:
	menu_controller._close_meditation()

func _select_system_menu() -> void:
	menu_controller._select_system_menu()

func _close_menu() -> void:
	menu_controller._close_menu()

func _set_menu_hint(title: String, text: String) -> void:
	menu_controller._set_menu_hint(title, text)

func _ui_box(fill: Color, border: Color = Color(0.25, 0.25, 0.25, 1.0), border_width: int = 1) -> StyleBoxFlat:
	return hud_views._ui_box(fill, border, border_width)

func _apply_hud_theme() -> void:
	hud_views._apply_hud_theme()

func _clear_menu_widgets() -> void:
	hud_views._clear_menu_widgets()

func _clear_details_widgets() -> void:
	hud_views._clear_details_widgets()

func _detail_label(text: String, rect: Rect2, size: int = 13, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, color: Color = Color(0.18, 0.18, 0.18, 1.0)) -> Label:
	return hud_views._detail_label(text, rect, size, alignment, color)

func _detail_rule(from: Vector2, to: Vector2, color: Color = Color(0.35, 0.35, 0.35, 1.0)) -> void:
	hud_views._detail_rule(from, to, color)

func _detail_selection(rect: Rect2) -> void:
	hud_views._detail_selection(rect)

func _show_profile_panel() -> void:
	hud_views._show_profile_panel()

# 处理profile、panel相关逻辑，并保持调用方状态一致。
func _layout_profile_panel() -> void:
	hud_views._layout_profile_panel()

func _show_npc_view_panel(npc: Dictionary) -> void:
	hud_views._show_npc_view_panel(npc)

# 处理npc、view、panel相关逻辑，并保持调用方状态一致。
func _layout_npc_view_panel() -> void:
	hud_views._layout_npc_view_panel()

func _npc_skill_rating(npc: Dictionary) -> String:
	return hud_views._npc_skill_rating(npc)

func _render_inventory_widgets() -> void:
	hud_views._render_inventory_widgets()

func _render_menu_widgets() -> void:
	hud_views._render_menu_widgets()

func _npc_hp(npc: Dictionary, is_player := false) -> int:
	return inventory_skillbook_controller._npc_hp(npc, is_player)

func _show_inventory() -> void:
	inventory_skillbook_controller._show_inventory()

func _handle_inventory_key(key: Key) -> void:
	inventory_skillbook_controller._handle_inventory_key(key)

func _open_skill_book() -> void:
	inventory_skillbook_controller._open_skill_book()

func _handle_skill_book_key(key: Key) -> void:
	inventory_skillbook_controller._handle_skill_book_key(key)

func _render_skill_book_widgets() -> void:
	inventory_skillbook_controller._render_skill_book_widgets()

func _gender_label(gender: String) -> String:
	return inventory_skillbook_controller._gender_label(gender)

func _skill_rating() -> String:
	return inventory_skillbook_controller._skill_rating()

func _appearance_title(score: int, gender: String) -> String:
	return inventory_skillbook_controller._appearance_title(score, gender)

func _show_details(text: String) -> void:
	inventory_skillbook_controller._show_details(text)

func _show_dialogue(speaker: String, text: String, lock_seconds: float = 0.0, after_last: Callable = Callable()) -> void:
	dialogue_controller.show(speaker, text, lock_seconds, after_last)

func _close_dialogue() -> void:
	dialogue_controller.close()

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

func _draw() -> void:
	world_renderer.draw()

func _player_frame_key() -> String:
	return world_renderer.player_frame_key()

func _game_view_rect() -> Rect2:
	return world_renderer.game_view_rect()

func _display_scale() -> float:
	return world_renderer.display_scale()

func _render_scale() -> float:
	return world_renderer.render_scale()

func _is_world_tile_visible(tile: Vector2) -> bool:
	return world_renderer.is_world_tile_visible(tile)

func _world_to_screen(world_position: Vector2) -> Vector2:
	return world_renderer.world_to_screen(world_position)

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

func _cursor(label: String, selected: bool) -> String:
	return "【%s】" % label if selected else "  " + label
