extends SceneTree
## 从导出 PCK 启动时确认全部发布音频均存在且可以加载。

const AUDIO_PATHS := [
	"res://assets/Audio/NG神教.ogg",
	"res://assets/Audio/前端群侠传.ogg",
	"res://assets/Audio/开源镇.ogg",
	"res://assets/Audio/空の国.ogg",
	"res://assets/Audio/笙火喵喵教.ogg",
	"res://assets/Audio/迷雾森林.ogg",
	"res://assets/Audio/郊区.ogg",
	"res://assets/Audio/量子仙宗.ogg",
	"res://assets/Audio/香草派.ogg",
	"res://assets/Audio/鱿鱼山庄.ogg",
]

func _initialize() -> void:
	var failures: Array[String] = []
	for path in AUDIO_PATHS:
		if not ResourceLoader.exists(path):
			failures.append("导出资源不存在：%s" % path)
			continue
		var stream := load(path) as AudioStream
		if not stream:
			failures.append("导出音频无法加载：%s" % path)
	if failures.is_empty():
		print("exported_audio_test: PASS (%d files)" % AUDIO_PATHS.size())
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("exported_audio_test: FAIL (%d)" % failures.size())
	quit(1)
