extends Node
## Web 地区资源包下载、版本化缓存与运行时挂载；原生平台直接使用主包资源。

signal manifest_finished(success: bool)
signal pack_finished(pack_id: String, success: bool)

const MANIFEST_PATH := "packs/manifest.json"
const CACHE_DIRECTORY := "user://content_packs"
const CATALOG_PATH := "res://assets/Data/bgm_packs.json"
const MAP_PACK_CATALOG_PATH := "res://assets/Data/map_packs.json"
const MAP_CATALOG_PATH := "res://assets/Data/maps.json"

var manifest: Dictionary = {}
var manifest_pending := false
var pending_packs: Dictionary = {}
var loaded_packs: Dictionary = {}
var map_pack_by_region: Dictionary = {}
var map_region_by_id: Dictionary = {}

func _ready() -> void:
	_load_map_catalogs()
	if OS.has_feature("web"):
		call_deferred("_prefetch_initial_pack")

func ensure_map_pack(map_id: String) -> bool:
	if not OS.has_feature("web"):
		return true
	var region_id := str(map_region_by_id.get(map_id.to_lower(), map_id)).to_lower()
	var pack_id := str(map_pack_by_region.get(region_id, ""))
	if pack_id.is_empty():
		push_warning("地图没有配置 Web 分包：%s" % map_id)
		return false
	if not await ensure_pack("map_shared"):
		return false
	return await ensure_pack(pack_id)

func ensure_pack(pack_id: String) -> bool:
	if not OS.has_feature("web"):
		return true
	if loaded_packs.has(pack_id):
		return true
	while pending_packs.has(pack_id):
		await pack_finished
		if loaded_packs.has(pack_id):
			return true
	pending_packs[pack_id] = true
	var success := await _download_and_mount(pack_id)
	if success:
		loaded_packs[pack_id] = true
	pending_packs.erase(pack_id)
	pack_finished.emit(pack_id, success)
	return success

func _download_and_mount(pack_id: String) -> bool:
	if not await _ensure_manifest():
		return false
	var packs: Dictionary = manifest.get("packs", {})
	var entry: Dictionary = packs.get(pack_id, {})
	var relative_path := str(entry.get("file", ""))
	var expected_size := int(entry.get("bytes", 0))
	if relative_path.is_empty() or expected_size <= 0:
		push_warning("Web 音频清单缺少分包：%s" % pack_id)
		return false
	var cache_path := CACHE_DIRECTORY.path_join(relative_path.get_file())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIRECTORY))
	if not _cached_file_matches(cache_path, expected_size):
		if not await _download_file(relative_path, cache_path, expected_size):
			return false
	if not ProjectSettings.load_resource_pack(cache_path, false):
		push_warning("无法挂载 Web 音频分包：%s" % cache_path)
		return false
	return true

func _ensure_manifest() -> bool:
	if not manifest.is_empty():
		return true
	if manifest_pending:
		await manifest_finished
		return not manifest.is_empty()
	manifest_pending = true
	var manifest_path := _web_manifest_path()
	var response := await _request_bytes(_web_url(manifest_path))
	var parsed = JSON.parse_string((response.get("body", PackedByteArray()) as PackedByteArray).get_string_from_utf8())
	if bool(response.get("ok", false)) and parsed is Dictionary:
		manifest = parsed
	else:
		push_warning("无法加载 Web 内容分包清单：%s（HTTP %d）" % [manifest_path, int(response.get("status", 0))])
	manifest_pending = false
	manifest_finished.emit(not manifest.is_empty())
	return not manifest.is_empty()

func _download_file(relative_path: String, cache_path: String, expected_size: int) -> bool:
	var temporary_path := cache_path + ".part"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var response := await _request_bytes(_web_url(relative_path))
	var body: PackedByteArray = response.get("body", PackedByteArray())
	if not bool(response.get("ok", false)) or body.size() != expected_size:
		push_warning("Web 音频分包下载失败：%s" % relative_path)
		return false
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if not file:
		push_warning("无法缓存 Web 音频分包：%s" % temporary_path)
		return false
	file.store_buffer(body)
	file.close()
	if FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_path))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(cache_path)) == OK

func _request_bytes(url: String) -> Dictionary:
	var request := HTTPRequest.new()
	# 浏览器已经负责 Content-Encoding 解压；关闭 Godot 的二次 gzip 解码，避免 Nginx JSON 响应解析失败。
	request.accept_gzip = false
	add_child(request)
	var request_error := request.request(url)
	if request_error != OK:
		request.queue_free()
		return {"ok": false, "body": PackedByteArray()}
	var response: Array = await request.request_completed
	request.queue_free()
	return {
		"ok": int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) == 200,
		"status": int(response[1]),
		"body": response[3],
	}

func _web_manifest_path() -> String:
	var expression := "String(window.FrontendContentPackManifest || %s)" % JSON.stringify(MANIFEST_PATH)
	var path := str(JavaScriptBridge.eval(expression))
	return path if not path.is_empty() else MANIFEST_PATH

func _cached_file_matches(path: String, expected_size: int) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and file.get_length() == expected_size

func _web_url(relative_path: String) -> String:
	var expression := "new URL(%s, window.location.href).href" % JSON.stringify(relative_path)
	return str(JavaScriptBridge.eval(expression))

func _prefetch_initial_pack() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var packs: Dictionary = parsed.get("packs", {}) if parsed is Dictionary else {}
	var data_registry := get_node_or_null("/root/DataRegistry")
	if not data_registry:
		return
	for map_path in data_registry.map_files:
		var context := TiledMapLoader.new()
		if not context.load_file(map_path) or context.spawn_point().is_empty():
			continue
		if not await ensure_map_pack(context.map_id):
			return
		var region_id := str(context.properties.get("parentMap", context.map_id)).to_lower()
		for pack_id_value in packs:
			var definition: Dictionary = packs[pack_id_value]
			if region_id in definition.get("regionIds", []):
				await ensure_pack(str(pack_id_value))
				return

func _load_map_catalogs() -> void:
	var pack_catalog = JSON.parse_string(FileAccess.get_file_as_string(MAP_PACK_CATALOG_PATH))
	var packs: Dictionary = pack_catalog.get("packs", {}) if pack_catalog is Dictionary else {}
	for pack_id_value in packs:
		for region_id_value in packs[pack_id_value].get("regionIds", []):
			map_pack_by_region[str(region_id_value).to_lower()] = str(pack_id_value)
	var map_catalog = JSON.parse_string(FileAccess.get_file_as_string(MAP_CATALOG_PATH))
	var maps: Dictionary = map_catalog.get("maps", {}) if map_catalog is Dictionary else {}
	for map_id_value in maps:
		var definition: Dictionary = maps[map_id_value]
		map_region_by_id[str(map_id_value).to_lower()] = str(definition.get("parentMapId", map_id_value)).to_lower()
