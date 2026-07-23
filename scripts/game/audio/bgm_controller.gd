extends RefCounted
## 按室外音乐区域选择 BGM，并用双播放器在区域之间交叉淡化。

const FADE_SECONDS := 0.8
const PLAYBACK_VOLUME_DB := -8.0
const SILENT_VOLUME_DB := -40.0

const CATALOG_PATH := "res://assets/Data/bgm_packs.json"

var game: Node
var players: Array[AudioStreamPlayer] = []
var active_player_index := -1
var current_stream: AudioStream
var fade_tween: Tween
var region_tracks: Dictionary = {}
var request_serial := 0

func _init(owner: Node) -> void:
	game = owner
	_load_catalog()

func sync_for_map(map_context: TiledMapLoader) -> void:
	if map_context:
		sync_for_properties(map_context.properties)

func sync_for_properties(properties: Dictionary) -> void:
	var track_path := track_path_for_properties(properties)
	if track_path == current_track_path() and active_player_index >= 0 and players[active_player_index].playing:
		return
	request_serial += 1
	var serial := request_serial
	if OS.has_feature("web"):
		var pack_id := pack_id_for_properties(properties)
		var pack_manager := game.get_node_or_null("/root/ContentPackManager")
		if pack_id.is_empty() or not pack_manager or not await pack_manager.ensure_pack(pack_id):
			push_warning("地图 BGM 分包不可用：%s" % pack_id)
			return
		if serial != request_serial:
			return
	var next_stream := load(track_path) as AudioStream if not track_path.is_empty() else null
	if not next_stream:
		push_warning("地图没有配置 BGM：%s" % str(properties.get("mapName", properties.get("mapId", "未知地图"))))
		return
	_ensure_players()
	_set_stream_loop(next_stream)
	if active_player_index < 0:
		active_player_index = 0
		current_stream = next_stream
		players[0].stream = next_stream
		players[0].volume_db = SILENT_VOLUME_DB
		players[0].play()
		fade_tween = game.create_tween()
		fade_tween.tween_property(players[0], "volume_db", PLAYBACK_VOLUME_DB, FADE_SECONDS)
		return
	_crossfade_to(next_stream)

func stream_for_properties(properties: Dictionary) -> AudioStream:
	var path := track_path_for_properties(properties)
	return load(path) as AudioStream if not path.is_empty() else null

func track_path_for_properties(properties: Dictionary) -> String:
	return str(_track_for_properties(properties).get("audio", ""))

func pack_id_for_properties(properties: Dictionary) -> String:
	return str(_track_for_properties(properties).get("pack_id", ""))

func current_track_path() -> String:
	return current_stream.resource_path if current_stream else ""

func _ensure_players() -> void:
	if not players.is_empty():
		return
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "BgmPlayer%d" % (index + 1)
		player.bus = SystemSettings.BGM_BUS_NAME
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.volume_db = SILENT_VOLUME_DB
		game.add_child(player)
		players.append(player)

func _crossfade_to(next_stream: AudioStream) -> void:
	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()
	var previous_player := players[active_player_index]
	var next_index := 1 - active_player_index
	var next_player := players[next_index]
	next_player.stop()
	next_player.stream = next_stream
	next_player.volume_db = SILENT_VOLUME_DB
	next_player.play()
	active_player_index = next_index
	current_stream = next_stream
	fade_tween = game.create_tween().set_parallel(true)
	fade_tween.tween_property(previous_player, "volume_db", SILENT_VOLUME_DB, FADE_SECONDS)
	fade_tween.tween_property(next_player, "volume_db", PLAYBACK_VOLUME_DB, FADE_SECONDS)
	fade_tween.chain().tween_callback(_stop_player.bind(previous_player))

func _set_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

func _stop_player(player: AudioStreamPlayer) -> void:
	player.stop()
	player.stream = null

func _track_for_properties(properties: Dictionary) -> Dictionary:
	var region_id := str(properties.get("parentMap", properties.get("mapId", ""))).strip_edges().to_lower()
	return region_tracks.get(region_id, {})

func _load_catalog() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var packs: Dictionary = parsed.get("packs", {}) if parsed is Dictionary else {}
	for pack_id_value in packs:
		var definition: Dictionary = packs[pack_id_value]
		for region_id_value in definition.get("regionIds", []):
			region_tracks[str(region_id_value).to_lower()] = {
				"pack_id": str(pack_id_value),
				"audio": str(definition.get("audio", "")),
			}
