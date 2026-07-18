extends SceneTree
## 世界事件数据、地图注入与 TMX 解耦回归。

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data_registry: Node = root.get_node("DataRegistry")
	_assert(data_registry.world_event_archetypes.size() == 6, "应加载 6 类世界事件原型")
	var event_count := 0
	var event_ids: Dictionary = {}
	for map_id in data_registry.world_event_placements:
		for placement in data_registry.world_event_placements[map_id]:
			event_count += 1
			event_ids[str(placement.get("id", ""))] = true
	_assert(event_count == 21 and event_ids.size() == 21, "应加载 21 个 ID 唯一的世界事件摆放")
	var handler = load("res://scripts/game/interaction/world_event_handler.gd").new(null, null)
	_assert(not handler.is_interactable({"properties": {"event": "drink", "text": "旧事件"}}), "旧 event/text 属性不得再被识别为世界事件")
	_assert(not handler.is_interactable({"properties": {"questGiver": "d07dc3ae-a94f-5bf5-a352-b2c487682d31"}}), "旧 questGiver 属性不得再被识别为世界事件")
	var injected_ids: Dictionary = {}
	var contexts: Dictionary = {}
	for map_id in data_registry.world_event_placements:
		contexts[map_id] = _load_map(data_registry, map_id)
		for object in contexts[map_id].objects:
			if str(object.get("type", "")) == "WorldEvent":
				injected_ids[str(object.get("properties", {}).get("worldEventId", ""))] = true
	_assert(injected_ids == event_ids, "每个数据摆放都应注入对应地图，且不得产生额外事件")

	var dark_study_map: TiledMapLoader = contexts["8f8add5e-93f8-5afe-b3e6-ba96dfc273c8"]
	var terminal: Dictionary = dark_study_map.interactable_object_at_tile(12, 6)
	_assert(str(terminal.get("properties", {}).get("action", "")) == "quest_endpoint", "DARK学电脑应由数据表注入任务终端行为")
	_assert(str(terminal.get("properties", {}).get("worldEventId", "")) == "d07dc3ae-a94f-5bf5-a352-b2c487682d31", "注入对象应保留稳定事件 ID")

	var starter_town_map: TiledMapLoader = contexts["25f3952d-ec39-53af-a8c1-d523c43b80b0"]
	_assert(str(starter_town_map.interactable_object_at_tile(5, 36).get("properties", {}).get("action", "")) == "delete_save", "歪脖树应由危险树原型提供删档行为")
	_assert(str(starter_town_map.interactable_object_at_tile(15, 36).get("properties", {}).get("action", "")) == "drink", "水井应由饮水点原型提供行为")
	_assert(str(starter_town_map.interactable_object_at_tile(39, 3).get("properties", {}).get("worldEventId", "")) == "e8e13eba-e4a5-5b42-afd9-ae66885bbfaf", "视觉路牌与事件摆放应在同一格命中")

	for map_path in data_registry.map_files:
		var file := FileAccess.open(map_path, FileAccess.READ)
		var xml := file.get_as_text() if file else ""
		_assert(not _contains_forbidden_event_property(xml), "TMX 不应继续维护事件属性：" + map_path)

	if failures.is_empty():
		print("world_event_test: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("world_event_test: FAIL (%d)" % failures.size())
		quit(1)

func _load_map(data_registry: Node, map_id: String) -> TiledMapLoader:
	for map_path in data_registry.map_files:
		var context := TiledMapLoader.new()
		if context.load_file(map_path) and context.map_id == map_id:
			_assert(true, "地图应成功加载：" + map_id)
			context.inject_objects(data_registry.world_event_objects(map_id, context.tile_width, context.tile_height))
			return context
	_assert(false, "找不到地图：" + map_id)
	return TiledMapLoader.new()

func _contains_forbidden_event_property(xml: String) -> bool:
	for property_name in ["event", "text", "questGiver"]:
		if xml.contains("name=\"%s\"" % property_name):
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
