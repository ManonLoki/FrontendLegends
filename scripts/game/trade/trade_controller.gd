extends RefCounted
## 商店分类、商品焦点、买卖输入与交易列表渲染。

const CATEGORY_ORDER := ["食物", "药物", "武器", "防具", "鞋子", "饰品", "其他"]

var game: Node

# 处理init相关逻辑，并保持调用方状态一致。
func _init(owner: Node) -> void:
	game = owner

# 处理key相关逻辑，并保持调用方状态一致。
func handle_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		if game.trade_focus_category:
			game.trade_open = false
			game.details_panel.visible = false
			game.npc_menu_open = false
			game.npc_menu_panel.visible = false
			game._clear_npc_menu_widgets()
		else:
			game.trade_focus_category = true
			refresh_items()
	elif key == KEY_LEFT:
		game.trade_focus_category = true
		refresh_items()
	elif game.trade_focus_category and key in [KEY_UP, KEY_DOWN]:
		var delta := -1 if key == KEY_UP else 1
		game.trade_category_index = posmod(game.trade_category_index + delta, maxi(1, game.trade_categories.size()))
		refresh_items()
	elif game.trade_focus_category and key in [KEY_RIGHT, KEY_SPACE]:
		if not game.trade_items.is_empty():
			game.trade_focus_category = false
			game.trade_index = 0
			render_list()
	elif not game.trade_focus_category and key == KEY_UP:
		game.trade_index = posmod(game.trade_index - 1, maxi(1, game.trade_items.size()))
		render_list()
	elif not game.trade_focus_category and key == KEY_DOWN:
		game.trade_index = posmod(game.trade_index + 1, maxi(1, game.trade_items.size()))
		render_list()
	elif not game.trade_focus_category and key == KEY_SPACE and not game.trade_items.is_empty():
		var item_id := str(game.trade_items[game.trade_index])
		var result: Dictionary = InventorySystem.buy_item(game.nearby_npc_id, item_id) if game.trade_mode == game.TRADE_MODE_BUY else InventorySystem.sell_item(item_id)
		game.message = result.message
		if game.trade_mode == game.TRADE_MODE_SELL and bool(result.get("ok", false)):
			game.trade_all_items.clear()
			for entry in InventorySystem.list_entries():
				game.trade_all_items.append(entry.get("id", ""))
		rebuild_categories(false)
	if game.trade_open:
		render_list()

# 渲染list相关逻辑，并保持调用方状态一致。
func render_list() -> void:
	game._use_detail_hud("buy" if game.trade_mode == game.TRADE_MODE_BUY else "sell")
	game.details_content.visible = true
	game.details_content.text = ""
	game._clear_details_widgets()
	var area: Vector2 = game.details_panel.size
	var scale: float = game._display_scale()
	var pad := 20.0 * scale
	var split := area.x * 0.34
	var row := 27.0 * scale
	var money := int(GameState.profile.get("vitals", {}).get("money", 0))
	game._detail_label("— %s —" % ("购买" if game.trade_mode == game.TRADE_MODE_BUY else "典当"), Rect2(Vector2(pad, 8.0 * scale), Vector2(area.x - pad * 2.0, 30.0 * scale)), 16, HORIZONTAL_ALIGNMENT_CENTER)
	game._detail_label("持有 %d Token" % money, Rect2(Vector2(pad, 37.0 * scale), Vector2(area.x - pad * 2.0, 24.0 * scale)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	var content_top := 68.0 * scale
	var list_bottom := area.y - 52.0 * scale
	game._detail_rule(Vector2(split, content_top), Vector2(split + 1.0, list_bottom), Color("77736b"))
	for category_index in game.trade_categories.size():
		var y: float = content_top + 8.0 * scale + row * category_index
		game._detail_label(game.trade_categories[category_index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.7, row)), 13)
		if game.trade_focus_category and category_index == game.trade_category_index:
			game._detail_selection(Rect2(Vector2(pad, y), Vector2(split - pad * 1.1, row)))
	if game.trade_items.is_empty():
		game._detail_label("货已售罄" if game.trade_mode == game.TRADE_MODE_BUY else "已无可卖之物", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in game.trade_items.size():
			var item_id := str(game.trade_items[index])
			var definition: Dictionary = DataRegistry.get_item(item_id)
			var price := int(definition.get("price", 0)) if game.trade_mode == game.TRADE_MODE_BUY else int(floor(float(definition.get("price", 0)) * InventorySystem.SELL_PRICE_RATE))
			var y: float = content_top + 8.0 * scale + row * index
			var item_rect := Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row))
			game._detail_label(str(definition.get("name", item_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 185.0 * scale, row)), 13)
			if game.trade_mode == game.TRADE_MODE_SELL:
				var remaining := InventorySystem.count(item_id)
				if remaining > 1:
					game._detail_label("× %d" % remaining, Rect2(Vector2(area.x - 180.0 * scale, y), Vector2(50.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.45, 0.45, 0.45, 1))
			game._detail_label("%d Token" % price, Rect2(Vector2(area.x - 120.0 * scale, y), Vector2(95.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT)
			if not game.trade_focus_category and index == game.trade_index:
				game._detail_selection(item_rect)
	var footer := "↑↓ 选分类　·　空格/→ 查看　·　ESC 返回" if game.trade_focus_category else "↑↓ 选物品　·　空格 确认　·　←/ESC 返回"
	if not game.trade_focus_category and not game.trade_items.is_empty():
		footer = str(DataRegistry.get_item(str(game.trade_items[game.trade_index])).get("description", "暂无说明"))
	var footer_label: Label = game._detail_label(footer, Rect2(Vector2(pad, list_bottom + 6.0 * scale), Vector2(area.x - pad * 2.0, area.y - list_bottom - 12.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

# 处理category相关逻辑，并保持调用方状态一致。
func item_category(item_id: String) -> String:
	var definition: Dictionary = DataRegistry.get_item(item_id)
	var kind := str(definition.get("kind", "other"))
	if kind in ["food", "water"]:
		return "食物"
	if kind in ["medicine", "elixir"]:
		return "药物"
	return {"weapon": "武器", "armor": "防具", "shoe": "鞋子", "accessory": "饰品"}.get(str(definition.get("slot", "")), "其他")

# 处理categories相关逻辑，并保持调用方状态一致。
func rebuild_categories(reset_focus := true) -> void:
	var selected_category: String = game.trade_categories[game.trade_category_index] if not game.trade_categories.is_empty() and game.trade_category_index < game.trade_categories.size() else ""
	var previous_focus: bool = game.trade_focus_category
	var present: Array[String] = []
	for item_id in game.trade_all_items:
		var category := item_category(str(item_id))
		if category not in present:
			present.append(category)
	game.trade_categories.clear()
	for category in CATEGORY_ORDER:
		if category in present:
			game.trade_categories.append(category)
	if game.trade_categories.is_empty():
		game.trade_categories.append("其他")
	if reset_focus:
		game.trade_category_index = clampi(game.trade_category_index, 0, game.trade_categories.size() - 1)
		game.trade_focus_category = true
	else:
		var preserved_index: int = game.trade_categories.find(selected_category)
		game.trade_category_index = preserved_index if preserved_index >= 0 else clampi(game.trade_category_index, 0, game.trade_categories.size() - 1)
		game.trade_focus_category = previous_focus
	refresh_items()
	if not reset_focus and game.trade_items.is_empty():
		game.trade_focus_category = true
		render_list()

# 刷新items相关逻辑，并保持调用方状态一致。
func refresh_items() -> void:
	game.trade_items.clear()
	var selected: String = game.trade_categories[game.trade_category_index] if not game.trade_categories.is_empty() else "其他"
	for item_id in game.trade_all_items:
		if item_category(str(item_id)) == selected:
			game.trade_items.append(item_id)
	if game.trade_mode == game.TRADE_MODE_BUY:
		game.trade_items.sort_custom(func(a, b): return int(DataRegistry.get_item(str(a)).get("price", 0)) < int(DataRegistry.get_item(str(b)).get("price", 0)))
	game.trade_index = clampi(game.trade_index, 0, maxi(0, game.trade_items.size() - 1))
	render_list()
