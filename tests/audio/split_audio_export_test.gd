extends SceneTree
## 在隔离的 Web Split 主 PCK 中验证地区音频缺席，逐个挂载分包后验证可加载。

const TITLE_AUDIO := "res://assets/Audio/前端群侠传.ogg"
const PACK_AUDIO := {
	"ng": "res://assets/Audio/NG神教.ogg",
	"kaiyuan": "res://assets/Audio/开源镇.ogg",
	"sky": "res://assets/Audio/空の国.ogg",
	"quantum": "res://assets/Audio/量子仙宗.ogg",
	"mist": "res://assets/Audio/迷雾森林.ogg",
	"shenghuo": "res://assets/Audio/笙火喵喵教.ogg",
	"vanilla": "res://assets/Audio/香草派.ogg",
	"squid": "res://assets/Audio/鱿鱼山庄.ogg",
	"suburbs": "res://assets/Audio/郊区.ogg",
}

var failures: Array[String] = []

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("缺少 Web packs 目录参数")
		quit(2)
		return
	var packs_directory := arguments[0]
	_assert(ResourceLoader.exists(TITLE_AUDIO) and load(TITLE_AUDIO) is AudioStream, "标题音乐必须保留在 Web 主包")
	for audio_path in PACK_AUDIO.values():
		_assert(not ResourceLoader.exists(audio_path), "地区音乐不得留在 Web 主包：%s" % audio_path)
	var manifest_value = JSON.parse_string(FileAccess.get_file_as_string(packs_directory.path_join("manifest.json")))
	var manifest: Dictionary = manifest_value if manifest_value is Dictionary else {}
	var entries: Dictionary = manifest.get("packs", {})
	for pack_id in PACK_AUDIO:
		var relative_path := str(entries.get(pack_id, {}).get("file", ""))
		var pack_path := packs_directory.get_base_dir().path_join(relative_path)
		_assert(not relative_path.is_empty() and ProjectSettings.load_resource_pack(pack_path, false), "分包应能挂载：%s" % pack_id)
		_assert(ResourceLoader.exists(PACK_AUDIO[pack_id]) and load(PACK_AUDIO[pack_id]) is AudioStream, "挂载后应能加载：%s" % PACK_AUDIO[pack_id])
	if failures.is_empty():
		print("split_audio_export_test: PASS (%d packs)" % PACK_AUDIO.size())
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("split_audio_export_test: FAIL (%d)" % failures.size())
	quit(1)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
