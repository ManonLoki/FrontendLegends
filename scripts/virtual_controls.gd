extends CanvasLayer

signal key_down(keycode: int)
signal key_up(keycode: int)

const FONT := preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")
const DIRECTION_SIZE := Vector2(48, 48)
const ACTION_SIZE := Vector2(52, 52)
const DIRECTION_RADIUS := 54.0
const ACTION_GAP := 10.0
const EDGE_MARGIN := 24.0

var controls_root: Control

## 同时检查显示服务的触摸能力，使触屏电脑即使没有移动平台标签也能显示虚拟方向键。
static func is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") \
		or OS.has_feature("web_android") \
		or OS.has_feature("web_ios") \
		or DisplayServer.is_touchscreen_available()

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

func _build_buttons() -> void:
	_add_button("↑", KEY_UP, "up")
	_add_button("←", KEY_LEFT, "left")
	_add_button("↓", KEY_DOWN, "down")
	_add_button("→", KEY_RIGHT, "right")
	_add_button("A", KEY_SPACE, "confirm", ACTION_SIZE)
	_add_button("B", KEY_ESCAPE, "cancel", ACTION_SIZE)

## 按钮发送 key_down 与 key_up 信号，不伪造真实键盘事件；方向键直接驱动虚拟方向，
## 确认与取消键转入统一分发入口，从而复用实体键盘的处理路径。
func _add_button(
	text: String,
	keycode: int,
	action_name: String,
	button_size: Vector2 = DIRECTION_SIZE,
) -> void:
	var button := Button.new()
	button.name = "Virtual_" + action_name
	button.text = text
	button.custom_minimum_size = button_size
	button.size = button_size
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color("#e6e6e6dd"))
	button.add_theme_color_override("font_hover_color", Color("#ffe678"))
	button.add_theme_stylebox_override("normal", _style(Color("#10121642"), Color("#d8d8d866")))
	button.add_theme_stylebox_override("pressed", _style(Color("#806b32b8"), Color("#ffe678dd")))
	button.add_theme_stylebox_override("hover", _style(Color("#26282d80"), Color("#ffe678aa")))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.button_down.connect(func() -> void: key_down.emit(keycode))
	button.button_up.connect(func() -> void: key_up.emit(keycode))
	controls_root.add_child(button)

func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
	style.anti_aliasing = true
	return style

func _layout_buttons() -> void:
	if not is_instance_valid(controls_root):
		return
	var size := get_viewport().get_visible_rect().size
	var buttons := controls_root.get_children()
	# 防止六个按钮尚未全部创建时收到窗口尺寸变化信号。
	if buttons.size() < 6:
		return
	var dpad_center := Vector2(
		EDGE_MARGIN + DIRECTION_RADIUS + DIRECTION_SIZE.x * 0.5,
		size.y - EDGE_MARGIN - DIRECTION_RADIUS - DIRECTION_SIZE.y * 0.5,
	)
	# 四向键使用图 2 的菱形布局；A/B 分离为右下斜向排列，减少误触。
	buttons[0].position = dpad_center + Vector2(0.0, -DIRECTION_RADIUS) - DIRECTION_SIZE * 0.5
	buttons[1].position = dpad_center + Vector2(-DIRECTION_RADIUS, 0.0) - DIRECTION_SIZE * 0.5
	buttons[2].position = dpad_center + Vector2(0.0, DIRECTION_RADIUS) - DIRECTION_SIZE * 0.5
	buttons[3].position = dpad_center + Vector2(DIRECTION_RADIUS, 0.0) - DIRECTION_SIZE * 0.5
	var action_origin := Vector2(size.x - EDGE_MARGIN - ACTION_SIZE.x, size.y - EDGE_MARGIN - ACTION_SIZE.y)
	buttons[4].position = action_origin + Vector2(0.0, -ACTION_SIZE.y - ACTION_GAP)
	buttons[5].position = action_origin + Vector2(-ACTION_SIZE.x - ACTION_GAP, 0.0)
