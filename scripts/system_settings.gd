extends Node
## 与角色存档完全分离的本机系统设置；当前只管理 BGM 开关。

const PRODUCTION_SETTINGS_PATH := "user://frontend_legends_settings.json"
const BGM_BUS_NAME := &"BGM"

var active_settings_path := PRODUCTION_SETTINGS_PATH
var _bgm_enabled := true

func _ready() -> void:
	_ensure_bgm_bus()
	get_tree().node_added.connect(_on_node_added)
	load_settings()
	_assign_existing_title_players()

func bgm_enabled() -> bool:
	return _bgm_enabled

func set_bgm_enabled(enabled: bool) -> void:
	_bgm_enabled = enabled
	_apply_audio_state()
	save_settings()

func toggle_bgm() -> bool:
	set_bgm_enabled(not _bgm_enabled)
	return _bgm_enabled

func current_settings_path() -> String:
	return active_settings_path

func use_test_settings_path(suite_name: String) -> void:
	var safe_name := suite_name.validate_filename()
	active_settings_path = OS.get_temp_dir().path_join(
		"frontend_legends_test_settings/%s.json" % (safe_name if not safe_name.is_empty() else "unnamed")
	)
	load_settings()

func delete_settings() -> void:
	var target := ProjectSettings.globalize_path(active_settings_path)
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	_bgm_enabled = true
	_apply_audio_state()

func load_settings() -> void:
	_bgm_enabled = true
	if FileAccess.file_exists(active_settings_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(active_settings_path))
		if parsed is Dictionary:
			_bgm_enabled = bool(parsed.get("bgm_enabled", true))
	_apply_audio_state()

func save_settings() -> bool:
	var target := ProjectSettings.globalize_path(active_settings_path)
	var directory := target.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(target, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify({"version": 1, "bgm_enabled": _bgm_enabled}, "\t") + "\n")
	return true

func _ensure_bgm_bus() -> void:
	if AudioServer.get_bus_index(BGM_BUS_NAME) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, BGM_BUS_NAME)

func _apply_audio_state() -> void:
	_ensure_bgm_bus()
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BGM_BUS_NAME), not _bgm_enabled)

func _on_node_added(node: Node) -> void:
	if node is AudioStreamPlayer and node.name == &"TitleBgm":
		(node as AudioStreamPlayer).bus = BGM_BUS_NAME

func _assign_existing_title_players() -> void:
	var current_scene := get_tree().current_scene
	if current_scene:
		_assign_title_players_below(current_scene)

func _assign_title_players_below(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_assign_title_players_below(child)
