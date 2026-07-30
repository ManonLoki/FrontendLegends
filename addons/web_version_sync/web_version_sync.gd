@tool
extends EditorPlugin
## Web 加载页版本同步插件：project.godot 是唯一版本来源，模板不再保存手写版本号。

const VERSION_TOKEN := "__FRONTEND_LEGENDS_VERSION__"
var export_plugin: WebVersionExportPlugin

func _enter_tree() -> void:
	export_plugin = WebVersionExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null

class WebVersionExportPlugin extends EditorExportPlugin:
	var output_path := ""

	func _get_name() -> String:
		return "FrontendLegendsWebVersionSync"

	func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
		output_path = path if features.has("web") and path.get_extension().to_lower() == "html" else ""

	func _export_end() -> void:
		if output_path.is_empty():
			return
		var html := FileAccess.get_file_as_string(output_path)
		if html.is_empty() or not html.contains(VERSION_TOKEN):
			push_error("Web 导出版本同步失败：输出 HTML 缺少版本令牌。")
			return
		var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
		var output := FileAccess.open(output_path, FileAccess.WRITE)
		if not output:
			push_error("Web 导出版本同步失败：无法写入 %s。" % output_path)
			return
		output.store_string(html.replace(VERSION_TOKEN, version))
