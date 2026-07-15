extends "res://scripts/game/game_context.gd"
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
	hud_layout._build_detail_huds()

func _use_detail_hud(kind: String, show := true) -> void:
	hud_layout._use_detail_hud(kind, show)

func _layout_active_detail_hud() -> void:
	hud_layout._layout_active_detail_hud()

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

func _interact_prop() -> bool:
	return interaction_controller._interact_prop()

func _prop_display_name(object: Dictionary) -> String:
	return interaction_controller._prop_display_name(object)

func _show_delete_confirm() -> void:
	interaction_controller._show_delete_confirm()

func _layout_delete_confirm() -> void:
	interaction_controller._layout_delete_confirm()

func _refresh_delete_confirm() -> void:
	interaction_controller._refresh_delete_confirm()

func _handle_delete_confirm_key(key: Key) -> void:
	interaction_controller._handle_delete_confirm_key(key)

func _close_delete_confirm() -> void:
	interaction_controller._close_delete_confirm()

func _has_front_interactable() -> bool:
	return interaction_controller._has_front_interactable()

func _handle_npc_menu_key(key: Key) -> void:
	interaction_controller._handle_npc_menu_key(key)

func _refresh_npc_menu() -> void:
	interaction_controller._refresh_npc_menu()

func _clear_npc_menu_widgets() -> void:
	interaction_controller._clear_npc_menu_widgets()

func _close_npc_menu() -> void:
	interaction_controller._close_npc_menu()

func _render_npc_menu_widgets() -> void:
	interaction_controller._render_npc_menu_widgets()

func _position_npc_menu() -> void:
	interaction_controller._position_npc_menu()

func _sync_npc_menu_widgets() -> void:
	interaction_controller._sync_npc_menu_widgets()

func _handle_trade_key(key: Key) -> void:
	trade_controller.handle_key(key)

func _refresh_trade_list() -> void:
	trade_controller.render_list()

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

func _render_learn_widgets() -> void:
	learning_controller.render()

func _learn_teach_cap(skill_id: String) -> int:
	return learning_controller.teach_cap(skill_id)

func _render_learning_progress() -> void:
	learning_controller.render_progress()

func _clear_learning_progress_widgets() -> void:
	learning_controller.clear_progress()

func _skill_category(skill_id: String) -> String:
	return learning_controller.skill_category(skill_id)

func _rebuild_learn_categories() -> void:
	learning_controller.rebuild_categories()

func _refresh_learn_items() -> void:
	learning_controller.refresh_items()

func _open_practice() -> void:
	practice_controller.open()

func _refresh_practice_items() -> void:
	practice_controller.refresh_items()

func _handle_practice_key(key: Key) -> void:
	practice_controller.handle_key(key)

func _refresh_practice() -> void:
	practice_controller.render()

func _render_practice_progress() -> void:
	practice_controller.render_progress()

func _clear_practice_progress_widgets() -> void:
	practice_controller.clear_progress()

func _select_npc_menu() -> void:
	npc_world_controller.select_menu_action()

func _refresh_nearby_npc() -> void:
	npc_world_controller.refresh_nearby()

func _npc_occupies_tile(tile: Vector2i) -> bool:
	return npc_world_controller.occupies_tile(tile)

func _draw_npcs() -> void:
	npc_world_controller.draw_npcs()

func _current_map_matches(map_id: String) -> bool:
	return npc_world_controller.current_map_matches(map_id)

func _bounty_tile() -> Vector2i:
	return npc_world_controller.bounty_tile()

func _toggle_menu() -> void:
	menu_controller._toggle_menu()

func _handle_menu_key(key: Key) -> void:
	menu_controller._handle_menu_key(key)

func _refresh_menu() -> void:
	menu_controller._refresh_menu()

func _select_menu() -> void:
	menu_controller._select_menu()

func _select_skill_menu() -> void:
	menu_controller._select_skill_menu()

func _open_meditation() -> void:
	menu_controller._open_meditation()

func _open_force_power() -> void:
	menu_controller._open_force_power()

func _handle_force_power_key(key: Key) -> void:
	menu_controller._handle_force_power_key(key)

func _refresh_force_power_hint() -> void:
	menu_controller._refresh_force_power_hint()

func _commit_force_power(show_confirmation: bool) -> void:
	menu_controller._commit_force_power(show_confirmation)

func _handle_meditation_key(key: Key) -> void:
	menu_controller._handle_meditation_key(key)

func _render_meditation_progress() -> void:
	menu_controller._render_meditation_progress()

func _layout_meditation_widgets() -> void:
	menu_controller._layout_meditation_widgets()

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

func _clear_menu_hint() -> void:
	menu_controller._clear_menu_hint()

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

func _layout_profile_panel() -> void:
	hud_views._layout_profile_panel()

func _show_npc_view_panel(npc: Dictionary) -> void:
	hud_views._show_npc_view_panel(npc)

func _layout_npc_view_panel() -> void:
	hud_views._layout_npc_view_panel()

func _npc_skill_rating(npc: Dictionary) -> String:
	return hud_views._npc_skill_rating(npc)

func _render_inventory_widgets() -> void:
	hud_views._render_inventory_widgets()

func _menu_label(text: String, rect: Rect2, selected: bool, host: Control) -> Label:
	return hud_views._menu_label(text, rect, selected, host)

func _render_menu_widgets() -> void:
	hud_views._render_menu_widgets()

func _npc_hp(npc: Dictionary, is_player := false) -> int:
	return inventory_skillbook_controller._npc_hp(npc, is_player)

func _show_inventory() -> void:
	inventory_skillbook_controller._show_inventory()

func _handle_inventory_key(key: Key) -> void:
	inventory_skillbook_controller._handle_inventory_key(key)

func _activate_inventory_item() -> void:
	inventory_skillbook_controller._activate_inventory_item()

func _refresh_inventory_panel() -> void:
	inventory_skillbook_controller._refresh_inventory_panel()

func _open_skill_book() -> void:
	inventory_skillbook_controller._open_skill_book()

func _handle_skill_book_key(key: Key) -> void:
	inventory_skillbook_controller._handle_skill_book_key(key)

func _refresh_skill_book_panel() -> void:
	inventory_skillbook_controller._refresh_skill_book_panel()

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

func _paginate_dialogue(text: String) -> Array[String]:
	return dialogue_controller.paginate(text)

func _render_dialogue(speaker: String) -> void:
	dialogue_controller.render(speaker)

func _advance_dialogue() -> void:
	dialogue_controller.advance()

func _close_dialogue() -> void:
	dialogue_controller.close()

func _update_dialogue_auto_close() -> void:
	dialogue_controller.update_auto_close()

func _load_initial_map() -> void:
	map_transition_controller.load_initial_map()

func _load_map(index: int, arrival_from := "", cyber := false) -> void:
	map_transition_controller.load_map(index, arrival_from, cyber)

func _try_map_transition() -> void:
	map_transition_controller.try_map_transition()

func _map_index_by_id(target: String) -> int:
	return map_transition_controller.map_index_by_id(target)

## Requires BOTH the basic and sect lightness-skill (tune theme) at level 30+, since
## either alone only gives partial mastery of movement techniques in this design.
func _try_cyber_teleport() -> void:
	cyber_teleport_controller.try_open()

func _handle_cyber_key(key: Key) -> void:
	cyber_teleport_controller.handle_key(key)

func _cyber_teleport_cost() -> int:
	return cyber_teleport_controller.cost()

func _refresh_cyber_menu(cost: int) -> void:
	cyber_teleport_controller.refresh_menu(cost)

func _build_cyber_menu() -> void:
	cyber_teleport_controller.build_menu()

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

func _load_player_sprite_regions() -> void:
	world_renderer.load_player_sprite_regions()

func _player_frame_key() -> String:
	return world_renderer.player_frame_key()

func _player_frame_region() -> Rect2:
	return world_renderer.player_frame_region()

func _player_battle_portrait_region() -> Rect2:
	return world_renderer.player_battle_portrait_region()

func _player_frame_draw_rect(player_pos: Vector2, source: Rect2 = _player_frame_region()) -> Rect2:
	return world_renderer.player_frame_draw_rect(player_pos, source)

func _game_view_rect() -> Rect2:
	return world_renderer.game_view_rect()

func _display_scale() -> float:
	return world_renderer.display_scale()

func _map_zoom() -> float:
	return world_renderer.map_zoom()

func _camera_world_size() -> Vector2:
	return world_renderer.camera_world_size()

func _render_scale() -> float:
	return world_renderer.render_scale()

func _camera_world_top_left() -> Vector2:
	return world_renderer.camera_world_top_left()

func _is_world_tile_visible(tile: Vector2) -> bool:
	return world_renderer.is_world_tile_visible(tile)

func _map_draw_origin() -> Vector2:
	return world_renderer.map_draw_origin()

func _world_to_screen(world_position: Vector2) -> Vector2:
	return world_renderer.world_to_screen(world_position)

func _update_camera() -> void:
	world_renderer.update_camera()

func _layout_game_view() -> void:
	hud_layout._layout_game_view()

func _layout_details_overlay() -> void:
	hud_layout._layout_details_overlay()

func _layout_cyber_panel() -> void:
	hud_layout._layout_cyber_panel()

func _layout_battle_panel() -> void:
	hud_layout._layout_battle_panel()

func _cursor(label: String, selected: bool) -> String:
	return "【%s】" % label if selected else "  " + label
