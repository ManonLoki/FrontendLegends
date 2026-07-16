extends Control

## 启动画面使用的固定设计尺寸、字体和跨平台输入组件。
const FONT := preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")
const DESIGN_SIZE := Vector2(480.0, 320.0)
const BLINK_TIME := 0.5
const VIRTUAL_CONTROLS := preload("res://scripts/virtual_controls.gd")
const MOBILE_ORIENTATION := preload("res://scripts/mobile_orientation.gd")

var stage: Control
var prompt: Label
var blink_elapsed := 0.0
var mobile_runtime := false
var transitioning := false

## 创建启动画面并连接窗口尺寸变化；移动端同时安装虚拟控制器。
func _ready() -> void:
	mobile_runtime = VIRTUAL_CONTROLS.is_mobile_runtime()
	MOBILE_ORIENTATION.apply()
	_build_stage()
	_install_virtual_controls()
	get_viewport().size_changed.connect(_layout_stage)
	_layout_stage()

## 按固定周期切换提示文字可见性，形成闪烁效果。
func _process(delta: float) -> void:
	if not is_instance_valid(prompt):
		return
	blink_elapsed += delta
	if blink_elapsed >= BLINK_TIME:
		blink_elapsed -= BLINK_TIME
		prompt.visible = not prompt.visible

## 桌面端仅响应按下空格，避免按键释放事件重复切换场景。
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if event.is_pressed() and event.keycode == KEY_SPACE:
		MOBILE_ORIENTATION.request_from_user_gesture()
		get_viewport().set_input_as_handled()
		_continue_from_splash()

## 移动端和桌面端共用同一套虚拟按键信号接口。
func _install_virtual_controls() -> void:
	var controls = VIRTUAL_CONTROLS.new()
	add_child(controls)
	controls.key_down.connect(_on_virtual_key_down)

## 虚拟确认键请求横屏权限并继续游戏。
func _on_virtual_key_down(keycode: int) -> void:
	if keycode == KEY_SPACE:
		MOBILE_ORIENTATION.request_from_user_gesture()
		_continue_from_splash()

## 根据是否已有角色资料选择进入主游戏或角色创建场景。
func _continue_from_splash() -> void:
	if transitioning:
		return
	transitioning = true
	var next_scene := "res://scenes/game.tscn" if GameState.has_profile() else "res://scenes/character_creation.tscn"
	get_tree().change_scene_to_file(next_scene)

## 在 480×320 设计舞台中动态构建纯黑启动画面。
func _build_stage() -> void:
	stage = Control.new()
	stage.name = "DesignStage"
	stage.size = DESIGN_SIZE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

	var background := ColorRect.new()
	background.color = Color.BLACK
	background.size = DESIGN_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)

	_add_label("前端群侠传", Rect2(0, 54, DESIGN_SIZE.x, 54), 36, Color.WHITE)
	var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_add_label("v%s" % version, Rect2(0, 112, DESIGN_SIZE.x, 26), 15, Color.WHITE)
	var continue_text := "按确认键继续" if mobile_runtime else "按空格继续"
	prompt = _add_label(continue_text, Rect2(0, 232, DESIGN_SIZE.x, 34), 17, Color.WHITE)

## 创建并挂载一个采用统一字体、居中显示且不拦截输入的标签。
func _add_label(text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(label)
	return label

## 舞台保持设计尺寸，并在 expand 模式扩展出的逻辑视口中居中。
func _layout_stage() -> void:
	if not is_instance_valid(stage):
		return
	stage.scale = Vector2.ONE
	stage.position = ((get_viewport_rect().size - DESIGN_SIZE) * 0.5).round()
