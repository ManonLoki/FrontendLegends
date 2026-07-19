extends SceneTree
## 按地区分析 TMX→TSX→PNG 依赖，并生成共享图块包与地区地图包。

const MAP_CATALOG_PATH := "res://assets/Data/maps.json"
const PACK_CATALOG_PATH := "res://assets/Data/map_packs.json"

var source_pattern := RegEx.new()

func _initialize() -> void:
	source_pattern.compile("<image\\b[^>]*source=\\\"([^\\\"]+\\.png)\\\"|<tileset\\b[^>]*source=\\\"([^\\\"]+\\.tsx)\\\"")
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("用法：--script res://tools/build_map_packs.gd -- <输出目录>")
		quit(2)
		return
	var output_directory := ProjectSettings.globalize_path(arguments[0])
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		push_error("无法创建地图分包目录：%s" % output_directory)
		quit(2)
		return
	var catalog := _read_json(PACK_CATALOG_PATH)
	var pack_maps := _group_maps(catalog.get("packs", {}))
	var dependencies := _collect_dependencies(pack_maps)
	var shared_threshold := int(catalog.get("sharedUseThreshold", 5))
	var shared_files := _shared_files(dependencies, shared_threshold)
	var failures: Array[String] = []
	var shared_error := _write_pack(output_directory.path_join("map_shared.pck"), shared_files)
	if not shared_error.is_empty():
		failures.append(shared_error)
	for pack_id_value in pack_maps:
		var pack_id := str(pack_id_value)
		var files: Dictionary = {}
		for map_path in pack_maps[pack_id_value]:
			files[map_path] = true
		for path_value in dependencies:
			var path := str(path_value)
			if dependencies[path_value].has(pack_id) and not shared_files.has(path):
				files[path] = true
		var error := _write_pack(output_directory.path_join(pack_id + ".pck"), files)
		if not error.is_empty():
			failures.append(error)
	if failures.is_empty():
		print("Map packs: PASS (%d region packs + shared)" % pack_maps.size())
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _group_maps(definitions: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var region_to_pack: Dictionary = {}
	for pack_id_value in definitions:
		result[pack_id_value] = []
		for region_id_value in definitions[pack_id_value].get("regionIds", []):
			region_to_pack[str(region_id_value).to_lower()] = pack_id_value
	var maps: Dictionary = _read_json(MAP_CATALOG_PATH).get("maps", {})
	for map_id_value in maps:
		var definition: Dictionary = maps[map_id_value]
		var region_id := str(definition.get("parentMapId", map_id_value)).to_lower()
		if region_to_pack.has(region_id):
			result[region_to_pack[region_id]].append(str(definition.get("path", "")))
	return result

func _collect_dependencies(pack_maps: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for pack_id_value in pack_maps:
		var pack_id := str(pack_id_value)
		for map_path_value in pack_maps[pack_id_value]:
			var map_path := str(map_path_value)
			for tsx_path in _referenced_paths(map_path, ".tsx"):
				_add_usage(result, tsx_path, pack_id)
				for image_path in _referenced_paths(tsx_path, ".png"):
					_add_usage(result, image_path, pack_id)
	return result

func _referenced_paths(xml_path: String, extension: String) -> Array[String]:
	var result: Array[String] = []
	var xml := FileAccess.get_file_as_string(xml_path)
	for match_value in source_pattern.search_all(xml):
		var source := match_value.get_string(1) if extension == ".png" else match_value.get_string(2)
		if source.is_empty() or not source.ends_with(extension):
			continue
		var path := xml_path.get_base_dir().path_join(source).simplify_path()
		if path not in result:
			result.append(path)
	return result

func _add_usage(dependencies: Dictionary, path: String, pack_id: String) -> void:
	if not dependencies.has(path):
		dependencies[path] = {}
	dependencies[path][pack_id] = true

func _shared_files(dependencies: Dictionary, threshold: int) -> Dictionary:
	var result: Dictionary = {}
	for path_value in dependencies:
		if dependencies[path_value].size() >= threshold:
			result[str(path_value)] = true
	return result

func _write_pack(output_path: String, files: Dictionary) -> String:
	var packer := PCKPacker.new()
	if packer.pck_start(output_path) != OK:
		return "无法创建地图 PCK：%s" % output_path
	for path_value in files:
		var path := str(path_value)
		var error := _add_imported_file(packer, path) if path.ends_with(".png") else _add_raw_file(packer, path)
		if not error.is_empty():
			return error
	if packer.flush() != OK:
		return "无法写入地图 PCK：%s" % output_path
	return ""

func _add_raw_file(packer: PCKPacker, path: String) -> String:
	if not FileAccess.file_exists(path) or packer.add_file(path, ProjectSettings.globalize_path(path)) != OK:
		return "无法加入地图文件：%s" % path
	return ""

func _add_imported_file(packer: PCKPacker, path: String) -> String:
	var import_path := path + ".import"
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		return "找不到地图图片导入元数据：%s" % import_path
	if packer.add_file(import_path, ProjectSettings.globalize_path(import_path)) != OK:
		return "无法加入地图图片元数据：%s" % import_path
	var destinations: PackedStringArray = config.get_value("deps", "dest_files", PackedStringArray())
	for destination in destinations:
		if packer.add_file(destination, ProjectSettings.globalize_path(destination)) != OK:
			return "无法加入地图图片导入产物：%s" % destination
	return ""

func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
