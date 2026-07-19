extends SceneTree
## 地图音乐映射、室内连续播放与跨区域交叉淡化回归。

const BGM_CONTROLLER := preload("res://scripts/game/audio/bgm_controller.gd")
const MAP_LOADER := preload("res://scripts/tiled_map_loader.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var owner := Node.new()
	root.add_child(owner)
	var controller = BGM_CONTROLLER.new(owner)
	_test_named_region_tracks(controller)
	_test_every_map_has_a_track(controller)
	await _test_playback_transitions(controller)
	if controller.fade_tween and controller.fade_tween.is_valid():
		controller.fade_tween.kill()
	for player in controller.players:
		player.stop()
		player.stream = null
	await process_frame
	owner.free()
	controller = null
	await create_timer(0.1).timeout
	if failures.is_empty():
		print("bgm_controller_test: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("bgm_controller_test: FAIL (%d)" % failures.size())
		quit(1)

func _test_named_region_tracks(controller: RefCounted) -> void:
	var expected := {
		"44ebb310-6990-5d82-bc23-623343b9acca": "NG神教.ogg",
		"25f3952d-ec39-53af-a8c1-d523c43b80b0": "开源镇.ogg",
		"da94005d-198e-5e73-8a5a-d0a8ac87911b": "空の国.ogg",
		"891e09c1-4118-5933-ab59-4f59be8ada85": "量子仙宗.ogg",
		"e4c8dc5c-474d-58be-aa33-f092e17f1f8c": "迷雾森林.ogg",
		"0c9615d7-aeba-5e40-9b22-2a4d0254b66b": "笙火喵喵教.ogg",
		"46c0823c-c650-5200-a391-2cfb37761b30": "香草派.ogg",
		"f832cbde-46e4-52d6-92fb-860bee93c8a8": "鱿鱼山庄.ogg",
	}
	for map_id in expected:
		var path: String = controller.track_path_for_properties({"mapId": map_id})
		_assert(path.ends_with(expected[map_id]), "地图 %s 应匹配 %s" % [map_id, expected[map_id]])
	for suburb_id in [
		"9b5bdbd9-3999-5e1e-aa17-5099491e841c",
		"294515d0-c122-5720-85d6-e5eeda2cf05d",
		"fb215e50-cd81-5f1a-a285-b32c09a09834",
		"f11a4867-c98d-5857-8c6a-e93bd568eda3",
	]:
		_assert(controller.track_path_for_properties({"mapId": suburb_id}).ends_with("郊区.ogg"), "四个郊区应共用郊区.ogg")
	var west_lake := {"mapId": "d1388237-5d83-5a08-a68c-41c18fe7d699", "parentMap": "0c9615d7-aeba-5e40-9b22-2a4d0254b66b"}
	_assert(controller.track_path_for_properties(west_lake).ends_with("笙火喵喵教.ogg"), "西湖灵隐应与笙火喵喵教共用 BGM")

func _test_every_map_has_a_track(controller: RefCounted) -> void:
	var data_registry: Node = root.get_node("DataRegistry")
	for map_path in data_registry.map_files:
		var context = MAP_LOADER.new()
		_assert(context.load_file(map_path), "测试应能加载地图：%s" % map_path)
		_assert(not controller.track_path_for_properties(context.properties).is_empty(), "每张地图都应解析到 BGM：%s" % map_path)

func _test_playback_transitions(controller: RefCounted) -> void:
	var town := {"mapId": "25f3952d-ec39-53af-a8c1-d523c43b80b0"}
	var house := {"mapId": "aa8f90d3-05e2-5f9a-9dee-a6adcd60db60", "parentMap": "25f3952d-ec39-53af-a8c1-d523c43b80b0"}
	controller.sync_for_properties(town)
	await process_frame
	var town_player_index: int = controller.active_player_index
	var town_player: AudioStreamPlayer = controller.players[town_player_index]
	_assert(town_player.playing, "初始地图 BGM 应开始播放")
	controller.sync_for_properties(house)
	_assert(controller.active_player_index == town_player_index, "进入房屋不得切换播放器或重启 BGM")
	_assert(controller.players[town_player_index] == town_player and town_player.playing, "房屋内应持续原有播放实例")

	controller.sync_for_properties({"mapId": "e4c8dc5c-474d-58be-aa33-f092e17f1f8c"})
	var forest_player_index: int = controller.active_player_index
	_assert(forest_player_index != town_player_index, "跨区域应换到另一播放器进行交叉淡化")
	_assert(controller.players[forest_player_index].playing and town_player.playing, "交叉淡化期间新旧 BGM 应同时播放")
	await create_timer(BGM_CONTROLLER.FADE_SECONDS + 0.1).timeout
	_assert(not town_player.playing, "交叉淡化结束后应停止旧 BGM")
	_assert(controller.players[forest_player_index].playing, "交叉淡化结束后新 BGM 应继续播放")
	_assert(controller.current_track_path().ends_with("迷雾森林.ogg"), "跨区域后当前曲目应更新")

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
