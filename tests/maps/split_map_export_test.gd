extends SceneTree
## 在隔离的 Web Split 主 PCK 中验证地图图块缺席，挂载分包后逐图加载。

const MAP_CATALOG_PATH := "res://assets/Data/maps.json"
const PACK_CATALOG_PATH := "res://assets/Data/map_packs.json"
const SAMPLE_TMX := "res://assets/Map/maps/LoreWorld/KaiyuanTown/KaiyuanTown.tmx"
const SAMPLE_TSX := "res://assets/Map/tilesets/1_Terrains_16x16.tsx"
const SAMPLE_IMAGE := "res://assets/Map/assets/ModernFarm/1_Terrains_16x16.png"

var failures: Array[String] = []

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("缺少 Web packs 目录参数")
		quit(2)
		return
	var packs_directory := arguments[0]
	_assert(FileAccess.file_exists(SAMPLE_TMX), "TMX 索引数据必须保留在 Web 主包")
	_assert(not FileAccess.file_exists(SAMPLE_TSX), "地图 TSX 不得留在 Web 主包")
	_assert(not ResourceLoader.exists(SAMPLE_IMAGE), "地图图片不得留在 Web 主包")
	var manifest := _read_json(packs_directory.path_join("manifest.json"))
	var entries: Dictionary = manifest.get("packs", {})
	var pack_catalog := _read_json(PACK_CATALOG_PATH)
	_assert(entries.has("map_shared"), "清单必须包含共享地图包")
	_assert(pack_catalog.get("packs", {}).size() == 12, "地图分包清单必须覆盖 12 个地区")
	for pack_id_value in pack_catalog.get("packs", {}):
		_mount_pack(entries, str(pack_id_value), packs_directory)
	_mount_pack(entries, "map_shared", packs_directory)
	_assert(FileAccess.file_exists(SAMPLE_TSX), "挂载地图包后应恢复 TSX")
	_assert(ResourceLoader.exists(SAMPLE_IMAGE) and load(SAMPLE_IMAGE) is Texture2D, "挂载地图包后应恢复图片")
	var maps: Dictionary = _read_json(MAP_CATALOG_PATH).get("maps", {})
	for map_id_value in maps:
		var path := str(maps[map_id_value].get("path", ""))
		var context := TiledMapLoader.new()
		_assert(context.load_file(path) and not context.tilesets.is_empty(), "挂载后地图应完整加载：%s" % path)
	if failures.is_empty():
		print("split_map_export_test: PASS (%d maps)" % maps.size())
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("split_map_export_test: FAIL (%d)" % failures.size())
	quit(1)

func _mount_pack(entries: Dictionary, pack_id: String, packs_directory: String) -> void:
	var relative_path := str(entries.get(pack_id, {}).get("file", ""))
	var pack_path := packs_directory.get_base_dir().path_join(relative_path)
	_assert(not relative_path.is_empty() and ProjectSettings.load_resource_pack(pack_path, false), "地图分包应能挂载：%s" % pack_id)

func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
