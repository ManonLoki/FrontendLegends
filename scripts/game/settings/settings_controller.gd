extends RefCounted
## 系统设置独立 HUD；当前提供与角色存档分离的 BGM 开关。

var game: Node
var title_label: Label
var bgm_label: Label
var footer_label: Label
var selection_panel: Panel

func _init(owner: Node) -> void:
	game = owner

func open() -> void:
	game._close_menu()
	game.settings_open = true
	game.map_badge_panel.visible = false
	game._use_detail_hud("settings")
	_build_hud()
	_refresh()

func handle_key(key: Key) -> void:
	if key == KEY_ESCAPE:
		close()
	elif key in [KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		SystemSettings.toggle_bgm()
		_refresh()

func close() -> void:
	game.settings_open = false
	game.details_panel.visible = false
	game.menu_controller.return_to_main_menu(3)
	game.system_open = true
	game.system_index = game.SYSTEM_ITEMS.size() - 1
	game._refresh_menu()

func _build_hud() -> void:
	game.details_content.visible = true
	game.details_content.text = ""
	game._clear_details_widgets()
	title_label = game._detail_label("设置", Rect2(), 20)
	bgm_label = game._detail_label("", Rect2(), 16)
	footer_label = game._detail_label("← → / 空格切换　ESC 返回", Rect2(), 12, HORIZONTAL_ALIGNMENT_CENTER, Color(0.42, 0.42, 0.42, 1))
	selection_panel = Panel.new()
	selection_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_panel.add_theme_stylebox_override("panel", game._ui_box(Color(1, 1, 1, 0), Color(0.78, 0.12, 0.06, 1), 2))
	game.details_content.add_child(selection_panel)
	game.details_widgets.append(selection_panel)
	layout()

func _refresh() -> void:
	if not is_instance_valid(bgm_label):
		return
	bgm_label.text = "BGM　　　　　　　　　%s" % ("【开】　关" if SystemSettings.bgm_enabled() else "开　【关】")

func layout() -> void:
	if not is_instance_valid(title_label):
		return
	var scale: float = game._display_scale()
	title_label.position = Vector2(24, 20) * scale
	title_label.size = Vector2(416, 42) * scale
	title_label.add_theme_font_size_override("font_size", maxi(12, int(round(20.0 * scale))))
	bgm_label.position = Vector2(56, 92) * scale
	bgm_label.size = Vector2(368, 44) * scale
	bgm_label.add_theme_font_size_override("font_size", maxi(12, int(round(16.0 * scale))))
	footer_label.position = Vector2(24, 244) * scale
	footer_label.size = Vector2(416, 32) * scale
	footer_label.add_theme_font_size_override("font_size", maxi(12, int(round(12.0 * scale))))
	selection_panel.position = Vector2(38, 92) * scale
	selection_panel.size = Vector2(404, 44) * scale
