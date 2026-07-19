extends SceneTree
## 将已导入的地区 BGM 分别封装为可在运行时挂载的 PCK。

const CATALOG_PATH := "res://assets/Data/bgm_packs.json"

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("用法：--script res://tools/build_audio_packs.gd -- <输出目录>")
		quit(2)
		return
	var output_directory := ProjectSettings.globalize_path(arguments[0])
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		push_error("无法创建音频分包目录：%s" % output_directory)
		quit(2)
		return
	var catalog := _load_catalog()
	var failures: Array[String] = []
	for pack_id_value in catalog:
		var pack_id := str(pack_id_value)
		var definition: Dictionary = catalog[pack_id_value]
		var audio_path := str(definition.get("audio", ""))
		var error := _write_pack(output_directory.path_join(pack_id + ".pck"), audio_path)
		if not error.is_empty():
			failures.append(error)
	if failures.is_empty():
		print("Audio packs: PASS (%d packs)" % catalog.size())
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)

func _load_catalog() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return parsed.get("packs", {}) if parsed is Dictionary else {}

func _write_pack(output_path: String, audio_path: String) -> String:
	var import_path := audio_path + ".import"
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		return "找不到音频导入元数据：%s" % import_path
	var destinations: PackedStringArray = config.get_value("deps", "dest_files", PackedStringArray())
	if destinations.is_empty():
		return "音频没有导入产物：%s" % audio_path
	var packer := PCKPacker.new()
	if packer.pck_start(output_path) != OK:
		return "无法创建 PCK：%s" % output_path
	if packer.add_file(import_path, ProjectSettings.globalize_path(import_path)) != OK:
		return "无法加入导入元数据：%s" % import_path
	for destination in destinations:
		if packer.add_file(destination, ProjectSettings.globalize_path(destination)) != OK:
			return "无法加入音频导入产物：%s" % destination
	if packer.flush() != OK:
		return "无法写入 PCK：%s" % output_path
	return ""
