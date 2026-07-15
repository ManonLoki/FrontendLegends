extends RefCounted
## 背包与功法册的状态、输入、内容刷新及角色展示文案。

var game: Node

func _init(owner: Node) -> void:
	game = owner

func _npc_hp(npc: Dictionary, is_player := false) -> int:
	if is_player:
		return GameState.player_hp_max()
	var attributes: Dictionary = npc.get("attributes", {})
	return GameState.hp_max_with_mp_boost(float(attributes.get("constitution", 0)), int(npc.get("mp", 0)))

func _show_inventory() -> void:
	game.inventory_open = true
	game.inventory_category_index = 0
	game.inventory_focus_category = true
	game.inventory_feedback = ""
	_refresh_inventory_panel()
	game.message = "背包已打开"

func _handle_inventory_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		if game.inventory_focus_category:
			game.inventory_open = false
			game.details_panel.visible = false
		else:
			game.inventory_focus_category = true
			game.inventory_feedback = ""
		_refresh_inventory_panel()
		return
	if key == KEY_LEFT:
		game.inventory_focus_category = true
		game.inventory_feedback = ""
	elif game.inventory_focus_category and key in [KEY_UP, KEY_DOWN]:
		game.inventory_feedback = ""
		var delta := -1 if key == KEY_UP else 1
		game.inventory_category_index = posmod(game.inventory_category_index + delta, game.inventory_categories.size())
	elif game.inventory_focus_category and key in [KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		game.inventory_focus_category = false
		game.inventory_index = 0
		game.inventory_feedback = ""
	elif not game.inventory_focus_category and key == KEY_UP:
		game.inventory_feedback = ""
		game.inventory_index = posmod(game.inventory_index - 1, maxi(1, game.inventory_items.size()))
	elif not game.inventory_focus_category and key == KEY_DOWN:
		game.inventory_feedback = ""
		game.inventory_index = posmod(game.inventory_index + 1, maxi(1, game.inventory_items.size()))
	elif not game.inventory_focus_category and key in [KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_activate_inventory_item()
	_refresh_inventory_panel()

func _activate_inventory_item() -> void:
	if game.inventory_items.is_empty():
		return
	var item_id: String = game.inventory_items[game.inventory_index]
	var definition: Dictionary = DataRegistry.get_item(item_id)
	var result: Dictionary
	if game.inventory_categories[game.inventory_category_index] == "丢弃":
		result = InventorySystem.discard_item(item_id)
	elif str(definition.get("kind", "")) == "equip":
		result = InventorySystem.unequip_item(item_id) if not InventorySystem.equipped_slot(item_id).is_empty() else InventorySystem.equip_item(item_id)
	else:
		result = InventorySystem.use_item(item_id)
	game.message = str(result.get("message", ""))
	game.inventory_feedback = game.message

func _refresh_inventory_panel() -> void:
	var selected: String = game.inventory_categories[game.inventory_category_index]
	game.inventory_items.clear()
	for entry in InventorySystem.list_entries():
		var item_id: String = str(entry.get("id", ""))
		if selected == "丢弃" or game._item_category(item_id) == selected:
			game.inventory_items.append(item_id)
	game.inventory_items.sort_custom(func(a: String, b: String) -> bool:
		return str(DataRegistry.get_item(a).get("name", a)).naturalnocasecmp_to(str(DataRegistry.get_item(b).get("name", b))) < 0
	)
	game.inventory_index = clampi(game.inventory_index, 0, maxi(0, game.inventory_items.size() - 1))
	game._render_inventory_widgets()

func _open_skill_book() -> void:
	game.skill_book_open = true
	game.skill_book_category_index = 0
	game.skill_book_focus_category = true
	_refresh_skill_book_panel()

func _handle_skill_book_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		if game.skill_book_focus_category:
			game.skill_book_open = false
			game.details_panel.visible = false
		else:
			game.skill_book_focus_category = true
		_refresh_skill_book_panel()
		return
	if key == KEY_LEFT:
		game.skill_book_focus_category = true
	elif game.skill_book_focus_category and key in [KEY_UP, KEY_DOWN]:
		var delta := -1 if key == KEY_UP else 1
		game.skill_book_category_index = posmod(game.skill_book_category_index + delta, game.skill_book_categories.size())
	elif game.skill_book_focus_category and key in [KEY_RIGHT, KEY_SPACE]:
		game.skill_book_focus_category = false
		game.skill_book_index = 0
	elif not game.skill_book_focus_category and key == KEY_UP:
		game.skill_book_index = posmod(game.skill_book_index - 1, maxi(1, game.skill_book_items.size()))
	elif not game.skill_book_focus_category and key == KEY_DOWN:
		game.skill_book_index = posmod(game.skill_book_index + 1, maxi(1, game.skill_book_items.size()))
	elif not game.skill_book_focus_category and key == KEY_SPACE and not game.skill_book_items.is_empty():
		var skill_id: String = game.skill_book_items[game.skill_book_index]
		var definition: Dictionary = DataRegistry.get_skill(skill_id)
		var theme: String = str(definition.get("theme", ""))
		var equipped_id := SkillSystem.equipped_id(theme, str(definition.get("category", "")))
		var result: Dictionary = SkillSystem.unequip(skill_id) if skill_id == equipped_id else SkillSystem.equip(skill_id)
		game.message = str(result.get("message", ""))
	_refresh_skill_book_panel()

func _refresh_skill_book_panel() -> void:
	var theme: String = game.SKILL_BOOK_THEMES[game.skill_book_category_index]
	var sect := str(GameState.profile.get("sect", ""))
	var levels: Dictionary = SkillSystem.ensure_skills().get("levels", {})
	game.skill_book_items.clear()
	var basic_id := str(SkillSystem.THEME_BASIC_SKILL.get(theme, ""))
	if int(levels.get(basic_id, 0)) > 0:
		game.skill_book_items.append(basic_id)
	for skill_id in levels:
		var definition: Dictionary = DataRegistry.get_skill(str(skill_id))
		if str(definition.get("category", "")) == "sect" and str(definition.get("theme", "")) == theme and str(definition.get("sect", "")) == sect and int(levels[skill_id]) > 0:
			game.skill_book_items.append(str(skill_id))
	game.skill_book_index = clampi(game.skill_book_index, 0, maxi(0, game.skill_book_items.size() - 1))
	_render_skill_book_widgets()

func _render_skill_book_widgets() -> void:
	game._use_detail_hud("skill_book")
	game.details_content.visible = true
	game.details_content.text = ""
	game._clear_details_widgets()
	var area: Vector2 = game.details_panel.size
	var scale: float = game._display_scale()
	var pad: float = 20.0 * scale
	var split: float = area.x * 0.34
	var row: float = 30.0 * scale
	var content_top: float = 10.0 * scale
	game._detail_rule(Vector2(split, content_top), Vector2(split + 1.0, area.y - 46.0 * scale), Color("c5bfb2"))
	for index in game.skill_book_categories.size():
		var y: float = content_top + 8.0 * scale + row * index
		game._detail_label(game.skill_book_categories[index], Rect2(Vector2(pad * 1.4, y), Vector2(split - pad * 1.6, row)), 13)
		if game.skill_book_focus_category and index == game.skill_book_category_index:
			game._detail_selection(Rect2(Vector2(pad, y), Vector2(split - pad * 1.1, row)))
	if game.skill_book_items.is_empty():
		game._detail_label("（该分类尚未学会功法）", Rect2(Vector2(split + pad, content_top + 16.0 * scale), Vector2(area.x - split - pad * 2.0, row)), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))
	else:
		for index in game.skill_book_items.size():
			var skill_id: String = game.skill_book_items[index]
			var definition: Dictionary = DataRegistry.get_skill(skill_id)
			var equipped_id := SkillSystem.equipped_id(str(definition.get("theme", "")), str(definition.get("category", "")))
			var y: float = content_top + 8.0 * scale + row * index
			var mark := "■  " if skill_id == equipped_id else "□  "
			game._detail_label(mark + str(definition.get("name", skill_id)), Rect2(Vector2(split + pad, y), Vector2(area.x - split - 100.0 * scale, row)), 13)
			game._detail_label("%d级" % int(SkillSystem.level(skill_id)), Rect2(Vector2(area.x - 90.0 * scale, y), Vector2(65.0 * scale, row)), 12, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.55, 0.55, 0.55, 1))
			if not game.skill_book_focus_category and index == game.skill_book_index:
				game._detail_selection(Rect2(Vector2(split + pad * 0.5, y), Vector2(area.x - split - pad * 1.5, row)))
	game._detail_label("↑↓ 选分类　·　空格/→ 查看　·　空格 装备/卸下　·　ESC 返回", Rect2(Vector2(pad, area.y - 37.0 * scale), Vector2(area.x - pad * 2.0, 28.0 * scale)), 11, HORIZONTAL_ALIGNMENT_CENTER, Color(0.55, 0.55, 0.55, 1))

func _gender_label(gender: String) -> String:
	return "女" if gender.to_lower() == "female" else "男" if gender.to_lower() == "male" else "未知"

func _skill_rating() -> String:
	var levels: Dictionary = SkillSystem.ensure_skills().get("levels", {})
	var total := 0
	for value in levels.values(): total += int(value)
	var average := total / maxi(1, levels.size())
	if average >= 80: return "出神入化"
	if average >= 50: return "炉火纯青"
	if average >= 20: return "登堂入室"
	return "不堪一击"

func _appearance_title(score: int, gender: String) -> String:
	var male := [["惨不忍睹", "面目狰狞"], ["相貌平平", "浓眉大眼"], ["五官端正", "气宇轩昂"], ["英俊潇洒", "风流倜傥"], ["玉树临风", "潘安再生"]]
	var female := [["惨不忍睹", "容貌丑陋"], ["姿色平平", "略有姿色"], ["亭亭玉立", "明眸皓齿"], ["楚楚动人", "沉鱼落雁", "闭月羞花"], ["国色天香", "倾国倾城"]]
	var tier := clampi(int(floor(float(score) / 20.0)), 0, 4)
	var options: Array = female[tier] if gender == "female" else male[tier]
	return str(options[posmod(score, options.size())])

func _show_details(text: String) -> void:
	game._use_detail_hud("generic")
	game._clear_details_widgets()
	game.details_content.visible = true
	game.details_content.text = text
	game.details_panel.visible = true
	game.npc_portrait.visible = false
	game.details_content.add_theme_font_size_override("font_size", maxi(12, int(round(13.0 * game._display_scale()))))
