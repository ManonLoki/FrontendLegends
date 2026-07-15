extends CanvasLayer

signal key_down(keycode: int)
signal key_up(keycode: int)

const FONT := preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")
const BUTTON_SIZE := Vector2(58, 58)
const GAP := 6.0

var controls_root: Control

## 同时检查显示服务的触摸能力，使触屏电脑即使没有移动平台标签也能显示虚拟方向键。
static func is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") \
		or OS.has_feature("web_android") \
		or OS.has_feature("web_ios") \
		or DisplayServer.is_touchscreen_available()

# 初始化ready相关逻辑，并保持调用方状态一致。
func _ready() -> void:
	# 非移动运行环境直接释放覆盖层，避免桌面端保留无用按钮节点。
	if not is_mobile_runtime():
		queue_free()
		return
	controls_root = Control.new()
	controls_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 使用 PASS 让空白区域触摸继续传给游戏视图，同时保留按钮自身的输入捕获。
	controls_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(controls_root)
	_build_buttons()
	get_viewport().size_changed.connect(_layout_buttons)
	_layout_buttons()

# 构建buttons相关逻辑，并保持调用方状态一致。
func _build_buttons() -> void:
	_add_button("↑", KEY_UP, "up")
	_add_button("←", KEY_LEFT, "left")
	_add_button("↓", KEY_DOWN, "down")
	_add_button("→", KEY_RIGHT, "right")
	_add_button("确认键", KEY_SPACE, "confirm")
	_add_button("取消键", KEY_ESCAPE, "cancel")

## 按钮发送 key_down 与 key_up 信号，不伪造真实键盘事件；方向键直接驱动虚拟方向，
## 确认与取消键转入统一分发入口，从而复用实体键盘的处理路径。
func _add_button(text: String, keycode: int, action_name: String) -> void:
	var button := Button.new()
	button.name = "Virtual_" + action_name
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 16 if text.length() > 1 else 24)
	button.add_theme_color_override("font_color", Color("#ffffffcc"))
	button.add_theme_color_override("font_hover_color", Color("#ffe678"))
	button.add_theme_stylebox_override("normal", _style(Color("#17191dcc"), Color("#ffffff66")))
	button.add_theme_stylebox_override("pressed", _style(Color("#6f6228ee"), Color("#ffe678")))
	button.add_theme_stylebox_override("hover", _style(Color("#25251fee"), Color("#ffe678")))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.button_down.connect(func() -> void: key_down.emit(keycode))
	button.button_up.connect(func() -> void: key_up.emit(keycode))
	controls_root.add_child(button)

# 处理style相关逻辑，并保持调用方状态一致。
func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style

# 处理buttons相关逻辑，并保持调用方状态一致。
func _layout_buttons() -> void:
	if not is_instance_valid(controls_root):
		return
	var size := get_viewport().get_visible_rect().size
	var buttons := controls_root.get_children()
	# 防止六个按钮尚未全部创建时收到窗口尺寸变化信号。
	if buttons.size() < 6:
		return
	var left := 24.0
	var bottom := size.y - 24.0 - BUTTON_SIZE.y
	# 方向键位于左下，确认与取消位于右下，让双手拇指都能自然触及各自按钮组。
	buttons[0].position = Vector2(left + BUTTON_SIZE.x + GAP, bottom - BUTTON_SIZE.y - GAP)
	buttons[1].position = Vector2(left, bottom)
	buttons[2].position = Vector2(left + BUTTON_SIZE.x + GAP, bottom)
	buttons[3].position = Vector2(left + (BUTTON_SIZE.x + GAP) * 2.0, bottom)
	buttons[4].position = Vector2(size.x - 24.0 - BUTTON_SIZE.x * 2.0 - GAP, bottom)
	buttons[5].position = Vector2(size.x - 24.0 - BUTTON_SIZE.x, bottom)
