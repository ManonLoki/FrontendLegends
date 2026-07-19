extends RefCounted
## 按室外音乐区域选择 BGM，并用双播放器在区域之间交叉淡化。

const FADE_SECONDS := 0.8
const PLAYBACK_VOLUME_DB := -8.0
const SILENT_VOLUME_DB := -40.0

const NG_SECT_ID := "44ebb310-6990-5d82-bc23-623343b9acca"
const KAIYUAN_TOWN_ID := "25f3952d-ec39-53af-a8c1-d523c43b80b0"
const SKY_KINGDOM_ID := "da94005d-198e-5e73-8a5a-d0a8ac87911b"
const QUANTUM_SECT_ID := "891e09c1-4118-5933-ab59-4f59be8ada85"
const MIST_FOREST_ID := "e4c8dc5c-474d-58be-aa33-f092e17f1f8c"
const SHENGHUO_SECT_ID := "0c9615d7-aeba-5e40-9b22-2a4d0254b66b"
const VANILLA_SECT_ID := "46c0823c-c650-5200-a391-2cfb37761b30"
const SQUID_MANOR_ID := "f832cbde-46e4-52d6-92fb-860bee93c8a8"
const SUBURB_IDS := {
	"9b5bdbd9-3999-5e1e-aa17-5099491e841c": true,
	"294515d0-c122-5720-85d6-e5eeda2cf05d": true,
	"fb215e50-cd81-5f1a-a285-b32c09a09834": true,
	"f11a4867-c98d-5857-8c6a-e93bd568eda3": true,
}
const REGION_STREAMS := {
	NG_SECT_ID: preload("res://assets/Audio/NG神教.ogg"),
	KAIYUAN_TOWN_ID: preload("res://assets/Audio/开源镇.ogg"),
	SKY_KINGDOM_ID: preload("res://assets/Audio/空の国.ogg"),
	QUANTUM_SECT_ID: preload("res://assets/Audio/量子仙宗.ogg"),
	MIST_FOREST_ID: preload("res://assets/Audio/迷雾森林.ogg"),
	SHENGHUO_SECT_ID: preload("res://assets/Audio/笙火喵喵教.ogg"),
	VANILLA_SECT_ID: preload("res://assets/Audio/香草派.ogg"),
	SQUID_MANOR_ID: preload("res://assets/Audio/鱿鱼山庄.ogg"),
}
const SUBURB_STREAM := preload("res://assets/Audio/郊区.ogg")

var game: Node
var players: Array[AudioStreamPlayer] = []
var active_player_index := -1
var current_stream: AudioStream
var fade_tween: Tween

func _init(owner: Node) -> void:
	game = owner

func sync_for_map(map_context: TiledMapLoader) -> void:
	if map_context:
		sync_for_properties(map_context.properties)

func sync_for_properties(properties: Dictionary) -> void:
	var next_stream := stream_for_properties(properties)
	if not next_stream:
		push_warning("地图没有配置 BGM：%s" % str(properties.get("mapName", properties.get("mapId", "未知地图"))))
		return
	if next_stream == current_stream and active_player_index >= 0 and players[active_player_index].playing:
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
	var region_id := str(properties.get("parentMap", properties.get("mapId", ""))).strip_edges().to_lower()
	if SUBURB_IDS.has(region_id):
		return SUBURB_STREAM
	return REGION_STREAMS.get(region_id) as AudioStream

func track_path_for_properties(properties: Dictionary) -> String:
	var stream := stream_for_properties(properties)
	return stream.resource_path if stream else ""

func current_track_path() -> String:
	return current_stream.resource_path if current_stream else ""

func _ensure_players() -> void:
	if not players.is_empty():
		return
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "BgmPlayer%d" % (index + 1)
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
