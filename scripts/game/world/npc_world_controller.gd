extends RefCounted
## NPC 行为入口、邻近检测、碰撞、悬赏目标与世界绘制。

var game: Node2D

# 处理init相关逻辑，并保持调用方状态一致。
func _init(owner: Node2D) -> void:
	game = owner

# 选择menu、action相关逻辑，并保持调用方状态一致。
func select_menu_action() -> void:
	var npc: Dictionary = NpcSystem.build_instance(game.nearby_npc_id)
	if game.npc_menu_actions.is_empty():
		return
	var action: String = game.npc_menu_actions[game.npc_menu_index]
	game._close_npc_menu()
	match action:
		"talk":
			var quest_message := QuestSystem.interact_npc(game.nearby_npc_id)
			var dialogue := quest_message if not quest_message.is_empty() else NpcSystem.dialogue(game.nearby_npc_id)
			game._show_dialogue(str(npc.get("display_name", game.nearby_npc_id)), dialogue)
		"view":
			game._show_npc_view_panel(npc)
		"spar", "fight":
			game.battle_ui.lethal = action == "fight"
			game.battle_ui.start()
		game.TRADE_MODE_BUY:
			game.trade_all_items.clear()
			game.trade_all_items.append_array(DataRegistry.list_vendor_stock(game.nearby_npc_id))
			game.trade_mode = game.TRADE_MODE_BUY
			game.trade_category_index = 0
			game.trade_open = true
			game._rebuild_trade_categories()
		game.TRADE_MODE_SELL:
			game.trade_all_items.clear()
			for entry in InventorySystem.list_entries():
				game.trade_all_items.append(entry.get("id", ""))
			game.trade_mode = game.TRADE_MODE_SELL
			game.trade_category_index = 0
			game.trade_open = true
			game._rebuild_trade_categories()
		"join":
			var join_result: Dictionary = SkillSystem.join_npc(game.nearby_npc_id)
			game._show_dialogue(str(npc.get("display_name", game.nearby_npc_id)), str(join_result.get("message", "")))
		"learn":
			game.learn_all_items.assign(SkillSystem.learn_options_for_npc(game.nearby_npc_id))
			game.learn_category_index = 0
			game.learn_open = true
			game._rebuild_learn_categories()

# 刷新nearby相关逻辑，并保持调用方状态一致。
func refresh_nearby() -> void:
	if not game.map_context:
		return
	game.nearby_npc_id = ""
	var object: Dictionary = game.map_context.npc_object_at_tile(game.player_tile.x + game.facing.x, game.player_tile.y + game.facing.y)
	var candidate := str(object.get("properties", {}).get("npcId", ""))
	if not candidate.is_empty() and NpcSystem.can_interact(candidate):
		game.nearby_npc_id = candidate
	var bounty: Dictionary = QuestSystem.get_bounty_target()
	if not bounty.is_empty() and current_map_matches(str(bounty.get("map_id", ""))) and game.player_tile + game.facing == bounty_tile():
		game.nearby_npc_id = str(bounty.get("target_id", ""))

# 处理tile相关逻辑，并保持调用方状态一致。
func occupies_tile(tile: Vector2i) -> bool:
	if not game.map_context:
		return false
	for object in game.map_context.npc_objects():
		var npc_id := str(object.get("properties", {}).get("npcId", ""))
		var npc_tile := Vector2i(floori(float(object.get("x", 0.0)) / game.map_context.tile_width), floori(float(object.get("y", 0.0)) / game.map_context.tile_height))
		if tile == npc_tile and not npc_id.is_empty() and not NpcSystem.is_defeated(npc_id):
			return true
	var bounty: Dictionary = QuestSystem.get_bounty_target()
	return not bounty.is_empty() and current_map_matches(str(bounty.get("map_id", ""))) and tile == bounty_tile()

# 绘制npcs相关逻辑，并保持调用方状态一致。
func draw_npcs() -> void:
	if not game.map_context:
		return
	for object in game.map_context.npc_objects():
		var npc_id := str(object.get("properties", {}).get("npcId", ""))
		if npc_id.is_empty() or NpcSystem.is_defeated(npc_id):
			continue
		var tile := Vector2(floor(float(object.get("x", 0)) / game.map_context.tile_width), floor(float(object.get("y", 0)) / game.map_context.tile_height))
		if not game._is_world_tile_visible(tile):
			continue
		var position: Vector2 = game._world_to_screen(tile * Vector2(game.map_context.tile_width, game.map_context.tile_height))
		var source := NpcSystem.sprite_region(npc_id)
		var zoom: float = game._render_scale()
		game.draw_texture_rect_region(game.npc_texture, Rect2(position + Vector2(1, -source.size.y + 16) * zoom, source.size * zoom), source)
	var bounty: Dictionary = QuestSystem.get_bounty_target()
	if not bounty.is_empty() and current_map_matches(str(bounty.get("map_id", ""))):
		var target_tile := Vector2(bounty_tile())
		if game._is_world_tile_visible(target_tile):
			var target_position: Vector2 = game._world_to_screen(target_tile * Vector2(game.map_context.tile_width, game.map_context.tile_height))
			var target_source := NpcSystem.sprite_region(str(bounty.get("target_id", "")))
			game.draw_texture_rect_region(game.npc_texture, Rect2(target_position + Vector2(1, -target_source.size.y + 16) * game._render_scale(), target_source.size * game._render_scale()), target_source)

# 处理map、matches相关逻辑，并保持调用方状态一致。
func current_map_matches(map_id: String) -> bool:
	return not map_id.is_empty() and game.map_context and (game.map_context.map_id.to_lower() == map_id.to_lower() or game.map_context.map_id.to_lower().contains(map_id.to_lower()))

# 处理tile相关逻辑，并保持调用方状态一致。
func bounty_tile() -> Vector2i:
	var bounty: Dictionary = QuestSystem.get_bounty_target()
	var saved_tile = bounty.get("tile", Vector2i(-1, -1))
	if saved_tile is Vector2i and saved_tile.x >= 0 and saved_tile.y >= 0:
		return saved_tile
	var selected: Vector2i = game.map_context.pick_dynamic_npc_tile()
	QuestSystem.set_bounty_target_tile(selected)
	return selected
