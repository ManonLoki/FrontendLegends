extends Control

## 角色创建界面的设计尺寸、排版常量、字段定义和跨平台组件。
const FONT := preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")
const DESIGN_SIZE := Vector2(640.0, 480.0)
const CONTENT_SIZE := Vector2(640.0, 400.0)
const INTRO_SPEED := 58.0
const ROW_H := 35.0
const NAME_MAX_LENGTH := 10
const ROWS := ["name", "gender", "strength", "agility", "constitution", "wisdom", "confirm"]
const ATTR_KEYS := ["strength", "agility", "constitution", "wisdom"]
const ATTR_LABELS := {"strength": "编码", "agility": "思维", "constitution": "架构", "wisdom": "灵感"}
const COLOR_YELLOW := Color("#ffe678")
const COLOR_GRAY := Color("#b8b8b8")
const COLOR_WHITE := Color("#ffffff")
const COLOR_FIELD := Color("#00000000")
const VIRTUAL_CONTROLS := preload("res://scripts/virtual_controls.gd")
const MOBILE_ORIENTATION := preload("res://scripts/mobile_orientation.gd")
const CREATION_INTRO := preload("res://scripts/character_creation/creation_intro.gd")
const CREATION_WIDGETS := preload("res://scripts/character_creation/creation_widgets.gd")
const WEB_NAME_INPUT := preload("res://scripts/character_creation/web_name_input.gd")

## 设计舞台、开场字幕与角色表单的节点引用。
var stage: Control
var form: Control
var intro_root: Control
var intro_content: Control
var intro_total_height := 0.0
var intro_playing := true
## 表单光标、数值标签和姓名输入框的运行状态。
var cursor_labels: Dictionary = {}
var value_labels: Dictionary = {}
var name_edit: LineEdit
var message: Label
var focus_index := 0
var gender := "male"
var attributes := {"strength": 25, "agility": 25, "constitution": 25, "wisdom": 25}
var mobile_runtime := false
var name_editing := false
var saved_name := ""
var web_name_submission := -1
## 初始化平台能力、设计舞台、虚拟控制器和开场字幕。
func _ready() -> void:
	mobile_runtime = VIRTUAL_CONTROLS.is_mobile_runtime()
	MOBILE_ORIENTATION.apply()
	_build_stage()
	_install_virtual_controls()
	get_viewport().size_changed.connect(_layout_stage)
	_layout_stage()
	_build_intro()
## 按固定速度向上滚动开场字幕，完全离场后切换到角色表单。
func _process(delta: float) -> void:
	if not intro_playing:
		_sync_web_name_input()
		return
	intro_content.position.y -= INTRO_SPEED * delta
	if intro_content.position.y + intro_total_height < -28.0:
		_finish_intro()
## 处理桌面键盘输入；姓名编辑状态优先于表单导航。
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_name_touch(event)
		return
	if not event is InputEventKey:
		return
	if not event.is_pressed():
		return
	if intro_playing:
		return
	if name_editing:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_cancel_name_edit()
		elif event.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			_save_name_edit()
		elif event.keycode == KEY_UP or event.keycode == KEY_DOWN:
			get_viewport().set_input_as_handled()
			_save_name_edit()
			_move_focus(-1 if event.keycode == KEY_UP else 1)
		return
	get_viewport().set_input_as_handled()
	_handle_key(event.keycode)

## 微信触摸必须在原始 touch 事件栈中直接激活 DOM 输入框，不能等待延迟焦点信号。
func _handle_name_touch(event: InputEventScreenTouch) -> void:
	if not event.pressed or intro_playing or not is_instance_valid(name_edit):
		return
	if not name_edit.get_global_rect().has_point(event.position):
		return
	get_viewport().set_input_as_handled()
	focus_index = 0
	if not name_editing:
		_activate()

## 安装移动端虚拟方向键和确认、取消按钮。
func _install_virtual_controls() -> void:
	var controls = VIRTUAL_CONTROLS.new()
	add_child(controls)
	controls.key_down.connect(_on_virtual_key_down)

## 将虚拟按键转入与实体键盘相同的处理入口。
func _on_virtual_key_down(keycode: int) -> void:
	MOBILE_ORIENTATION.request_from_user_gesture()
	if intro_playing:
		return
	_handle_key(keycode)

## 根据当前编辑状态和表单焦点分发导航、调整或确认操作。
func _handle_key(keycode: int) -> void:
	if name_editing:
		if keycode == KEY_ESCAPE:
			_cancel_name_edit()
		elif keycode == KEY_SPACE:
			_save_name_edit()
		elif keycode == KEY_UP or keycode == KEY_DOWN:
			_save_name_edit()
			_move_focus(-1 if keycode == KEY_UP else 1)
		return
	if focus_index == 0 and keycode == KEY_ESCAPE:
		return
	if keycode == KEY_UP:
		_move_focus(-1)
	elif keycode == KEY_DOWN:
		_move_focus(1)
	elif keycode == KEY_LEFT:
		_adjust(-1)
	elif keycode == KEY_RIGHT:
		_adjust(1)
	elif keycode == KEY_SPACE:
		_activate()

## 创建固定 640×480 的角色创建设计舞台。
func _build_stage() -> void:
	stage = Control.new()
	stage.name = "DesignStage"
	stage.size = DESIGN_SIZE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

## 通过独立构建器创建开场字幕，并预先创建隐藏的角色表单。
func _build_intro() -> void:
	var intro: Dictionary = CREATION_INTRO.build(stage, FONT)
	intro_root = intro.root
	intro_content = intro.content
	intro_total_height = float(intro.total_height)
	form = Control.new()
	form.name = "CreationForm"
	form.size = CONTENT_SIZE
	form.position = Vector2(0.0, (DESIGN_SIZE.y - CONTENT_SIZE.y) * 0.5)
	form.visible = false
	stage.add_child(form)
	_build_form()

## 结束开场字幕并激活角色表单的首个字段。
func _finish_intro() -> void:
	if not intro_playing:
		return
	intro_playing = false
	intro_root.queue_free()
	form.visible = true
	if mobile_runtime:
		_refresh_focus()
	else:
		_activate()

## 按字段定义构建姓名、性别、四维属性和确认行。
func _build_form() -> void:
	for index in ROWS.size():
		var row: String = ROWS[index]
		var y := 25.0 + index * ROW_H
		cursor_labels[row] = CREATION_WIDGETS.label("", 16, COLOR_YELLOW, FONT)
		cursor_labels[row].position = Vector2(72, y)
		cursor_labels[row].size = Vector2(24, 30)
		form.add_child(cursor_labels[row])
		var caption: String = "姓名" if row == "name" else "性别" if row == "gender" else "确认" if row == "confirm" else String(ATTR_LABELS[row])
		var caption_label := CREATION_WIDGETS.label(caption, 16, COLOR_GRAY, FONT)
		caption_label.position = Vector2(100, y)
		caption_label.size = Vector2(60, 30)
		form.add_child(caption_label)
		if row == "name":
			name_edit = LineEdit.new()
			name_edit.max_length = NAME_MAX_LENGTH
			name_edit.position = Vector2(169, y)
			name_edit.size = Vector2(285, 30)
			name_edit.placeholder_text = "（直接输入姓名）"
			name_edit.add_theme_font_override("font", FONT)
			name_edit.add_theme_font_size_override("font_size", 16)
			name_edit.add_theme_color_override("font_color", COLOR_WHITE)
			name_edit.add_theme_color_override("font_placeholder_color", COLOR_GRAY)
			name_edit.add_theme_stylebox_override("normal", CREATION_WIDGETS.field_style(COLOR_FIELD, COLOR_GRAY, 1))
			name_edit.add_theme_stylebox_override("focus", CREATION_WIDGETS.field_style(COLOR_FIELD, COLOR_YELLOW, 2))
			name_edit.mouse_filter = Control.MOUSE_FILTER_STOP
			name_edit.focus_entered.connect(_on_name_focus_entered)
			name_edit.text_submitted.connect(func(_text: String) -> void: _save_name_edit())
			form.add_child(name_edit)
		else:
			value_labels[row] = CREATION_WIDGETS.label("", 16, COLOR_WHITE, FONT)
			value_labels[row].position = Vector2(174, y)
			value_labels[row].size = Vector2(300, 30)
			form.add_child(value_labels[row])

	message = CREATION_WIDGETS.label("可分配点数：0", 16, COLOR_WHITE, FONT)
	message.position = Vector2(330, 290)
	message.size = Vector2(260, 30)
	form.add_child(message)
	_refresh_values()

## 触摸姓名框时同步表单编辑状态；Web 导出器随后负责连接浏览器软键盘。
func _on_name_focus_entered() -> void:
	if intro_playing or name_editing:
		return
	focus_index = 0
	saved_name = name_edit.text
	name_editing = true
	name_edit.edit()
	web_name_submission = WEB_NAME_INPUT.open(name_edit.text)
	_refresh_focus()

## 从真实 DOM 输入框同步微信输入法文本，并在键盘确认时保存。
func _sync_web_name_input() -> void:
	if not name_editing or not WEB_NAME_INPUT.available():
		return
	name_edit.text = WEB_NAME_INPUT.value().left(NAME_MAX_LENGTH)
	if WEB_NAME_INPUT.submission() != web_name_submission:
		_save_name_edit()

## 激活当前字段：姓名进入编辑状态，确认行尝试创建角色。
func _activate() -> void:
	var row: String = ROWS[focus_index]
	if row == "name":
		name_editing = true
		name_edit.text = saved_name
		name_edit.edit()
		name_edit.grab_focus()
		if mobile_runtime:
			DisplayServer.virtual_keyboard_show(name_edit.text, name_edit.get_global_rect())
		web_name_submission = WEB_NAME_INPUT.open(name_edit.text)
		_refresh_focus()
	elif row == "confirm":
		_start_game()

## 循环移动表单焦点并刷新高亮。
func _move_focus(delta: int) -> void:
	focus_index = posmod(focus_index + delta, ROWS.size())
	_refresh_focus()

## 调整性别或当前属性；单项属性限制在 5～50。
func _adjust(delta: int) -> void:
	var row: String = ROWS[focus_index]
	if row == "gender":
		gender = "female" if delta > 0 else "male"
		_refresh_values()
	elif row in ATTR_KEYS:
		if delta > 0 and _unallocated_points() <= 0:
			return
		attributes[row] = clampi(int(attributes[row]) + delta, 5, 50)
		_refresh_values()

## 同步光标、标签颜色和姓名输入框焦点。
func _refresh_focus() -> void:
	if not is_instance_valid(form):
		return
	for row in ROWS:
		var selected: bool = ROWS[focus_index] == row
		cursor_labels[row].text = "▶" if selected else ""
		if value_labels.has(row):
			value_labels[row].modulate = COLOR_YELLOW if selected else COLOR_WHITE
	if name_editing:
		name_edit.grab_focus()
	else:
		name_edit.release_focus()

## 把角色状态格式化到表单标签，并显示剩余可分配点数。
func _refresh_values() -> void:
	value_labels["gender"].text = "【男】    女" if gender == "male" else "男    【女】"
	for key in ATTR_KEYS:
		value_labels[key].text = "－  %d  ＋" % int(attributes[key])
	value_labels["confirm"].text = "开始游戏"
	message.text = "可分配点数：%d" % _unallocated_points()

## 四项属性总额固定为 100，返回尚未分配的差值。
func _unallocated_points() -> int:
	var total := 0
	for key in ATTR_KEYS:
		total += int(attributes[key])
	return 100 - total

## 验证姓名和属性总额，通过后创建角色并进入主游戏。
func _start_game() -> void:
	if name_editing:
		_save_name_edit()
	var player_name: String = name_edit.text.strip_edges()
	if player_name.is_empty():
		message.text = "请输入姓名"
		focus_index = 0
		_refresh_focus()
		return
	if _unallocated_points() != 0:
		message.text = "还有 %d 点属性未分配" % _unallocated_points()
		return
	GameState.create_profile(player_name, attributes, gender)
	get_tree().change_scene_to_file("res://scenes/game.tscn")

## 确认姓名输入，保存裁剪空白后的文本并退出编辑状态。
func _save_name_edit() -> void:
	if not name_editing:
		return
	saved_name = name_edit.text.strip_edges()
	name_editing = false
	name_edit.text = saved_name
	DisplayServer.virtual_keyboard_hide()
	WEB_NAME_INPUT.close()
	name_edit.release_focus()
	_refresh_focus()

## 放弃本次姓名编辑，恢复进入编辑前保存的文本。
func _cancel_name_edit() -> void:
	if not name_editing:
		return
	name_editing = false
	name_edit.text = saved_name
	DisplayServer.virtual_keyboard_hide()
	WEB_NAME_INPUT.close()
	name_edit.release_focus()
	_refresh_focus()

## 设计舞台保持原始尺寸和原点，窗口缩放交由项目拉伸设置。
func _layout_stage() -> void:
	if not is_instance_valid(stage):
		return
	stage.scale = Vector2.ONE
	stage.position = Vector2.ZERO
