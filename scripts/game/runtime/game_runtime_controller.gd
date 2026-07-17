extends RefCounted
## 逐帧世界更新、移动、连续技能动作与键盘/虚拟输入分发。

var game: Node2D

func _init(owner: Node2D) -> void:
	game = owner

func _process(delta: float) -> void:
	# 每帧核对 HUD 几何，弥补网页或移动端在 ready 之后全屏导致尺寸信号遗漏的问题。
	# 只在真实尺寸变化时重新布局。菜单节点不能每帧销毁重建，否则 Web
	# 渲染时会出现旧帧/新帧交替的闪烁。
	var viewport_size := game.get_viewport_rect().size
	if not viewport_size.is_equal_approx(game.last_layout_viewport_size):
		game._layout_game_view()
	# 战斗中暂停生存时钟，避免玩家停在战斗 HUD 上等待每 15 秒的被动回血与疗伤。
	# 其他菜单仍沿用统一世界时钟；学习、练功、冥想另有各自动作快进。
	if not game.battle_ui.active:
		GameState.advance_time(delta)
	_update_continuous_skill_actions(delta)
	# HUD 为模态界面；菜单、对话、战斗或详情面板显示时暂停世界模拟并清空持续方向输入。
	if _has_modal_input():
		game.player_moving = false
		game.virtual_direction = Vector2.ZERO
		return
	game.move_cooldown -= delta
	game.auto_save_timer += delta
	if game.auto_save_timer >= 30.0:
		game.auto_save_timer = 0.0
		GameState.save_game()
	NpcSystem.sweep_defeated()
	if game.map_transitioning:
		game.player_moving = false
		return
	if game.npc_menu_open:
		game._position_npc_menu()
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") + game.virtual_direction
	var requested_step := _apply_facing_input(direction)
	# 持续移动在站立帧与两张相反迈步帧之间循环；每次起步从第零帧开始，避免半步切入。
	if direction.length() > 0.0:
		if not game.player_moving:
			game.animation_frame = 0
			game.animation_timer = 0.0
			game.queue_redraw()
		game.player_moving = true
		game.animation_timer += delta
		if game.animation_timer >= game.MOVE_STEP_SECONDS:
			game.animation_timer = fmod(game.animation_timer, game.MOVE_STEP_SECONDS)
			game.animation_frame = (game.animation_frame + 1) % 4
			game.queue_redraw()
	else:
		game.player_moving = false
	if game.move_cooldown <= 0.0:
		if direction.length() > 0.0:
			var step := requested_step
			var next_tile: Vector2i = game.player_tile + step
			if game.map_context and (not game.map_context.is_walkable(next_tile.x, next_tile.y) or game._npc_occupies_tile(next_tile)):
				game.message = "前方不可通行"
				return
			game.player_tile = next_tile
			game._refresh_nearby_npc()
			game.map_transition_controller.try_map_transition()
			game.move_cooldown = game.MOVE_STEP_SECONDS
			game.message = "当前位置: %s" % game.player_tile
			game._update_camera()
			game.queue_redraw()
	if game.accept_requested:
		game.accept_requested = false
		# 确认键可能在移动/转向后的下一帧才消费；触发瞬间重新按当前位置与
		# 当前朝向解析面前一格，禁止使用已经失效的 NPC 缓存。
		game._refresh_nearby_npc()
		if not game.nearby_npc_id.is_empty() or game._has_front_interactable():
			game._interact()
		elif not game.menu_open and not game.battle_ui.active:
			game.battle_ui.start()
	if game.cancel_requested:
		game.cancel_requested = false
		if game.battle_ui.active:
			game.battle_ui.end("你离开了战斗")
		else:
			game._toggle_menu()

func _apply_facing_input(direction: Vector2) -> Vector2i:
	if direction.length() <= 0.0:
		return Vector2i.ZERO
	var requested_step := Vector2i(signi(int(direction.x)), signi(int(direction.y)))
	if requested_step.x != 0:
		requested_step.y = 0
	# 转向不受移动冷却限制。玩家按下方向后必须立即以新朝向解析交互，
	# 否则 0.15 秒移动冷却内仍会错误命中旧方向的对象。
	if game.facing != requested_step:
		game.facing = requested_step
		game._refresh_nearby_npc()
		game.queue_redraw()
	return requested_step

## 学习、练功和冥想分别使用固定时间片，通过累加器循环补算，不直接按帧间隔缩放，
## 从而保持不同帧率下速度一致，并在长帧后完整补齐多个时间片。
func _update_continuous_skill_actions(delta: float) -> void:
	if game.learn_open and not game.learning_skill_id.is_empty():
		game.learning_tick_accumulator += maxf(0.0, delta)
		var learn_changed := false
		while game.learning_tick_accumulator >= SkillSystem.LEARNING_TICK_SECONDS and not game.learning_skill_id.is_empty():
			game.learning_tick_accumulator -= SkillSystem.LEARNING_TICK_SECONDS
			var result: Dictionary = SkillSystem.learn_tick(game.nearby_npc_id, game.learning_skill_id)
			game.message = str(result.get("message", ""))
			learn_changed = true
			# 原项目在升级成功或资源/门槛阻断时停止持续研习。
			if bool(result.get("ok", false)) or not str(result.get("reason", "")).is_empty():
				game.learning_skill_id = ""
		if learn_changed:
			# 升级或阻断都会清空 learning_skill_id 并改变列表内容，需要整页重绘；
			# 普通 tick 只有页脚进度文本和进度条变化。
			if game.learning_skill_id.is_empty():
				game._refresh_learn_list()
			else:
				game.learning_controller.update_tick_feedback()
			game._render_learning_progress()
	if game.practice_open and not game.practicing_skill_id.is_empty():
		game.practice_tick_accumulator += maxf(0.0, delta)
		while game.practice_tick_accumulator >= SkillSystem.PRACTICE_TICK_SECONDS and not game.practicing_skill_id.is_empty():
			game.practice_tick_accumulator -= SkillSystem.PRACTICE_TICK_SECONDS
			var skill_id: String = game.practicing_skill_id
			var level_before := SkillSystem.level(skill_id)
			var before := SkillSystem.practice_progress(skill_id)
			var result: Dictionary = SkillSystem.practice_tick(skill_id)
			game.message = str(result.get("message", ""))
			var after := SkillSystem.practice_progress(skill_id)
			var failed := not bool(result.get("ok", false))
			if failed or (before == after and int(after.get("current", 0)) == 0):
				game.practicing_skill_id = ""
			# 列表里的等级只在升级或停止时变化；普通 tick 只需刷新进度条。
			if failed or game.practicing_skill_id.is_empty() or SkillSystem.level(skill_id) != level_before:
				game._refresh_practice()
			else:
				game.practice_controller.render_progress()
			if failed:
				game._show_dialogue("练功", str(result.get("message", "练功失败。")))
	if game.meditation_open:
		game.meditation_tick_accumulator += maxf(0.0, delta)
		var meditation_changed := false
		while game.meditation_tick_accumulator >= SkillSystem.MEDITATION_TICK_SECONDS and game.meditation_open:
			game.meditation_tick_accumulator -= SkillSystem.MEDITATION_TICK_SECONDS
			var result: Dictionary = SkillSystem.meditate_tick()
			game.message = str(result.get("message", ""))
			if not bool(result.get("ok", false)):
				game._close_meditation()
				game._show_dialogue("冥想", game.message)
				break
			meditation_changed = true
		if meditation_changed and game.meditation_open:
			game._render_meditation_progress()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		game.MOBILE_ORIENTATION.request_from_user_gesture()
		if game.map_transitioning:
			return
		if game.delete_confirm_open:
			game._handle_delete_confirm_key(event.keycode)
			return
		if game.dialogue_open:
			if event.keycode == KEY_SPACE:
				if Time.get_ticks_msec() < game.dialogue_locked_until_msec:
					return
				game.dialogue_controller.advance()
			return
		if game.trade_open:
			game._handle_trade_key(event.keycode)
			return
		if game.inventory_open:
			game._handle_inventory_key(event.keycode)
			return
		if game.learn_open:
			game._handle_learn_key(event.keycode)
			return
		if game.meditation_open:
			game._handle_meditation_key(event.keycode)
			return
		if game.practice_open:
			game._handle_practice_key(event.keycode)
			return
		if game.skill_book_open:
			game._handle_skill_book_key(event.keycode)
			return
		if game.cyber_open:
			game._handle_cyber_key(event.keycode)
			return
		if game.npc_menu_open:
			game._handle_npc_menu_key(event.keycode)
			return
		if game.battle_ui.active:
			if not game.battle_ui.submenu.is_empty():
				game.battle_ui.handle_submenu_key(event.keycode)
			else:
				game.battle_ui.handle_key(event.keycode)
			return
		if game.details_panel.visible:
			if event.keycode == KEY_ESCAPE:
				game.details_panel.visible = false
			return
		if game.menu_open:
			game._handle_menu_key(event.keycode)
			return
		if event.keycode == KEY_SPACE:
			game.accept_requested = true
		elif event.keycode == KEY_ESCAPE:
			game.cancel_requested = true

func _install_virtual_controls() -> void:
	var controls = game.VIRTUAL_CONTROLS.new()
	game.add_child(controls)
	controls.key_down.connect(_on_virtual_key_down)
	controls.key_up.connect(_on_virtual_key_up)

func _on_virtual_key_down(keycode: int) -> void:
	if keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and not _has_modal_input():
		if keycode == KEY_UP: game.virtual_direction.y = -1.0
		elif keycode == KEY_DOWN: game.virtual_direction.y = 1.0
		elif keycode == KEY_LEFT: game.virtual_direction.x = -1.0
		elif keycode == KEY_RIGHT: game.virtual_direction.x = 1.0
		return
	_dispatch_virtual_key(keycode)

func _on_virtual_key_up(keycode: int) -> void:
	if keycode == KEY_UP or keycode == KEY_DOWN:
		game.virtual_direction.y = 0.0
	elif keycode == KEY_LEFT or keycode == KEY_RIGHT:
		game.virtual_direction.x = 0.0

func _has_modal_input() -> bool:
	return game.delete_confirm_open or game.dialogue_open or game.trade_open or game.inventory_open or game.learn_open or game.meditation_open or game.practice_open or game.skill_book_open or game.cyber_open or game.npc_menu_open or game.battle_ui.active or game.menu_open or game.details_panel.visible or game.dialogue_panel.visible

func _dispatch_virtual_key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_input(event)
