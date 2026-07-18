extends RefCounted
## 统一解释由 world_events.json 注入的数据驱动世界事件。

var controller: RefCounted
var game: Node

func _init(owner: RefCounted, game_owner: Node) -> void:
	controller = owner
	game = game_owner

func is_interactable(object: Dictionary) -> bool:
	return not str(object.get("properties", {}).get("action", "")).is_empty()

func interact(object: Dictionary) -> bool:
	var properties: Dictionary = object.get("properties", {})
	var action := str(properties.get("action", ""))
	if action.is_empty():
		return false
	match action:
		"message":
			game.message = str(properties.get("text", "已查看。"))
		"drink":
			_drink(properties)
		"bounty_board":
			game.message = QuestSystem.bounty_board_text()
		"delete_save":
			controller._show_delete_confirm(properties)
			return true
		"quest_endpoint":
			return _interact_quest_endpoint(object, properties)
		_:
			push_warning("Unknown world event action: " + action)
			return false
	game._show_dialogue(display_name(object), game.message)
	return true

func display_name(object: Dictionary) -> String:
	var properties: Dictionary = object.get("properties", {})
	var value := str(properties.get("displayName", "")).strip_edges()
	if value.is_empty():
		value = str(object.get("name", "")).strip_edges()
	return value if not value.is_empty() else "告示"

func _drink(properties: Dictionary) -> void:
	var vitals: Dictionary = GameState.profile.get("vitals", {})
	var capacity: int = GameState.vitals_capacity()
	var amount := maxi(0, int(properties.get("amount", 20)))
	var gain := mini(amount, maxi(0, capacity - int(vitals.get("water", 0))))
	vitals.water = int(vitals.get("water", 0)) + gain
	GameState.profile.vitals = vitals
	game.message = str(properties.get("text", "你喝了些水。")) + "（饮水 +%d）" % gain

func _interact_quest_endpoint(object: Dictionary, properties: Dictionary) -> bool:
	var endpoint := str(properties.get("questEndpoint", ""))
	var detailed: Dictionary = QuestSystem.begin_novice_completion(endpoint)
	if not detailed.is_empty():
		game.message = str(detailed.get("message", ""))
		var after_last := Callable()
		if bool(detailed.get("can_finish", false)):
			after_last = func() -> String: return QuestSystem.finish_novice_completion(endpoint)
		game._show_dialogue(display_name(object), game.message, float(detailed.get("lock_seconds", 0.0)), after_last)
		return true
	game.message = QuestSystem.interact_npc(endpoint)
	game._show_dialogue(display_name(object), game.message)
	return true
