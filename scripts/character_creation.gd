extends Control

const FONT := preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")
const DESIGN_SIZE := Vector2(640.0, 480.0)
const CONTENT_SIZE := Vector2(640.0, 400.0)
const INTRO_SPEED := 58.0
const ROW_H := 35.0
const ROWS := ["name", "gender", "strength", "agility", "constitution", "wisdom", "confirm"]
const ATTR_KEYS := ["strength", "agility", "constitution", "wisdom"]
const ATTR_LABELS := {"strength": "编码", "agility": "思维", "constitution": "架构", "wisdom": "灵感"}
const COLOR_YELLOW := Color("#ffe678")
const COLOR_GRAY := Color("#b8b8b8")
const COLOR_WHITE := Color("#ffffff")
const COLOR_FIELD := Color("#f5f5f5")
const VIRTUAL_CONTROLS := preload("res://scripts/virtual_controls.gd")
const MOBILE_ORIENTATION := preload("res://scripts/mobile_orientation.gd")

var stage: Control
var form: Control
var intro_root: Control
var intro_content: Control
var intro_total_height := 0.0
var intro_playing := true
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

func _ready() -> void:
	mobile_runtime = VIRTUAL_CONTROLS.is_mobile_runtime()
	MOBILE_ORIENTATION.apply()
	_build_stage()
	_install_virtual_controls()
	get_viewport().size_changed.connect(_layout_stage)
	_layout_stage()
	_build_intro()

func _process(delta: float) -> void:
	if not intro_playing:
		return
	intro_content.position.y -= INTRO_SPEED * delta
	if intro_content.position.y + intro_total_height < -28.0:
		_finish_intro()

func _input(event: InputEvent) -> void:
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

func _install_virtual_controls() -> void:
	var controls = VIRTUAL_CONTROLS.new()
	add_child(controls)
	controls.key_down.connect(_on_virtual_key_down)

func _on_virtual_key_down(keycode: int) -> void:
	MOBILE_ORIENTATION.request_from_user_gesture()
	if intro_playing:
		return
	_handle_key(keycode)

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

func _build_stage() -> void:
	stage = Control.new()
	stage.name = "DesignStage"
	stage.size = DESIGN_SIZE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)

func _build_intro() -> void:
	intro_root = Control.new()
	intro_root.name = "OpeningText"
	intro_root.size = CONTENT_SIZE
	intro_root.position = Vector2(0.0, (DESIGN_SIZE.y - CONTENT_SIZE.y) * 0.5)
	intro_root.clip_contents = true
	intro_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(intro_root)
	var background := ColorRect.new()
	background.color = Color("#080a0e")
	background.size = CONTENT_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_root.add_child(background)

	intro_content = Control.new()
	intro_content.name = "ScrollingContent"
	intro_content.size = CONTENT_SIZE
	intro_root.add_child(intro_content)

	var lines := [
		["18岁那年，高考结束", 17, COLOR_WHITE, 6],
		["你没有收到任何一所大学的录取通知书", 17, COLOR_WHITE, 18],
		["你试过外出打工，想靠双手把日子撑起来", 17, COLOR_WHITE, 6],
		["可简历石沉大海，面试屡屡碰壁，", 17, COLOR_WHITE, 6],
		["连最普通的岗位都像隔着一扇看不见的门", 17, COLOR_WHITE, 18],
		["后来，你不再投简历，也很少和家里说话", 17, COLOR_WHITE, 6],
		["白天昏睡，夜里醒来，", 17, COLOR_WHITE, 6],
		["把时间耗在网吧的泡面、游戏和通宵里", 17, COLOR_WHITE, 18],
		["直到今天清晨", 17, COLOR_GRAY, 18],
		["你刚从网吧出来，阳光刺得眼睛发疼", 17, COLOR_WHITE, 6],
		["一张皱巴巴的传单被风卷着，啪地拍在了你的脸上", 17, COLOR_WHITE, 18],
		["传单正中写着四个醒目的大字：", 17, COLOR_GRAY, 12],
		["码界招工", 24, COLOR_YELLOW, 18],
		["下方还有一行小字：", 17, COLOR_GRAY, 6],
		["诚招异界开发者，包吃包住，前途未知，风险自负", 17, COLOR_WHITE, 18],
		["也许是通宵后的脑子还不清醒，", 17, COLOR_WHITE, 6],
		["也许是你对原来的生活已经没什么留恋", 17, COLOR_WHITE, 6],
		["你拿起笔，在“乙方”那一栏填下了自己的名字", 17, COLOR_WHITE, 18],
		["下一秒，白光骤然亮起", 17, COLOR_YELLOW, 18],
		["等你再次睁开眼时，", 17, COLOR_WHITE, 6],
		["破旧的网吧、灰白的街道、催促你长大的世界，", 17, COLOR_WHITE, 6],
		["全都消失不见", 17, COLOR_WHITE, 18],
		["取而代之的，是一座陌生的小镇", 17, COLOR_WHITE, 6],
		["镇口的木牌上写着三个字：", 17, COLOR_GRAY, 12],
		["开源镇", 24, COLOR_YELLOW, 18],
		["而你的异界生活，也从这里正式开始", 17, COLOR_WHITE, 18],
		["若干年后", 17, COLOR_GRAY, 18],
		["也许你会站在顶峰，大喊我命由我不由天", 17, COLOR_WHITE, 18],
		["也许沉沦谷底，万般皆是命，半点不由人", 17, COLOR_WHITE, 18],
		["是非善恶，全凭一心", 17, COLOR_WHITE, 6],
	]
	for line in lines:
		var label := _label(str(line[0]), int(line[1]), line[2])
		var height := float(line[1]) + 8.0
		label.position = Vector2(40, intro_total_height)
		label.size = Vector2(560, height)
		intro_content.add_child(label)
		intro_total_height += height + float(line[3])

	intro_content.position = Vector2(0, CONTENT_SIZE.y + 34.0)
	form = Control.new()
	form.name = "CreationForm"
	form.size = CONTENT_SIZE
	form.position = Vector2(0.0, (DESIGN_SIZE.y - CONTENT_SIZE.y) * 0.5)
	form.visible = false
	stage.add_child(form)
	_build_form()

func _finish_intro() -> void:
	if not intro_playing:
		return
	intro_playing = false
	intro_root.queue_free()
	form.visible = true
	_refresh_focus()

func _build_form() -> void:
	for index in ROWS.size():
		var row: String = ROWS[index]
		var y := 25.0 + index * ROW_H
		cursor_labels[row] = _label("", 16, COLOR_YELLOW)
		cursor_labels[row].position = Vector2(72, y)
		cursor_labels[row].size = Vector2(24, 30)
		form.add_child(cursor_labels[row])
		var caption: String = "姓名" if row == "name" else "性别" if row == "gender" else "确认" if row == "confirm" else String(ATTR_LABELS[row])
		var caption_label := _label(caption, 16, COLOR_GRAY)
		caption_label.position = Vector2(100, y)
		caption_label.size = Vector2(60, 30)
		form.add_child(caption_label)
		if row == "name":
			name_edit = LineEdit.new()
			name_edit.position = Vector2(169, y)
			name_edit.size = Vector2(285, 30)
			name_edit.placeholder_text = "（按确认键输入）" if mobile_runtime else "（按空格输入）"
			name_edit.add_theme_font_override("font", FONT)
			name_edit.add_theme_font_size_override("font_size", 16)
			name_edit.add_theme_color_override("font_color", Color("#222222"))
			name_edit.add_theme_color_override("font_placeholder_color", COLOR_YELLOW)
			name_edit.add_theme_stylebox_override("normal", _field_style(COLOR_FIELD, COLOR_YELLOW, 2))
			name_edit.add_theme_stylebox_override("focus", _field_style(COLOR_FIELD, COLOR_YELLOW, 2))
			name_edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
			form.add_child(name_edit)
		else:
			value_labels[row] = _label("", 16, COLOR_WHITE)
			value_labels[row].position = Vector2(174, y)
			value_labels[row].size = Vector2(300, 30)
			form.add_child(value_labels[row])

	message = _label("可分配点数：0", 16, COLOR_WHITE)
	message.position = Vector2(330, 290)
	message.size = Vector2(260, 30)
	form.add_child(message)
	_refresh_values()

func _activate() -> void:
	var row: String = ROWS[focus_index]
	if row == "name":
		name_editing = true
		name_edit.text = saved_name
		name_edit.edit()
		name_edit.grab_focus()
		_refresh_focus()
	elif row == "confirm":
		_start_game()

func _move_focus(delta: int) -> void:
	focus_index = posmod(focus_index + delta, ROWS.size())
	_refresh_focus()

func _adjust(delta: int) -> void:
	var row: String = ROWS[focus_index]
	if row == "gender":
		gender = "female" if delta > 0 else "male"
		_refresh_values()
	elif row in ATTR_KEYS:
		attributes[row] = clampi(int(attributes[row]) + delta, 5, 50)
		_refresh_values()

func _refresh_focus() -> void:
	if not is_instance_valid(form):
		return
	for row in ROWS:
		var selected: bool = ROWS[focus_index] == row
		cursor_labels[row].text = "▶" if selected else ""
		if value_labels.has(row):
			value_labels[row].modulate = COLOR_YELLOW if selected else COLOR_WHITE
		if row == "name":
			name_edit.modulate = COLOR_YELLOW if selected else COLOR_WHITE
	if name_editing:
		name_edit.grab_focus()
	else:
		name_edit.release_focus()

func _refresh_values() -> void:
	value_labels["gender"].text = "【男】    女" if gender == "male" else "男    【女】"
	for key in ATTR_KEYS:
		value_labels[key].text = "－  %d  ＋" % int(attributes[key])
	value_labels["confirm"].text = "开始游戏"
	message.text = "可分配点数：%d" % _unallocated_points()

func _unallocated_points() -> int:
	var total := 0
	for key in ATTR_KEYS:
		total += int(attributes[key])
	return 100 - total

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

func _save_name_edit() -> void:
	if not name_editing:
		return
	saved_name = name_edit.text.strip_edges()
	name_editing = false
	name_edit.text = saved_name
	name_edit.release_focus()
	_refresh_focus()

func _cancel_name_edit() -> void:
	if not name_editing:
		return
	name_editing = false
	name_edit.text = saved_name
	name_edit.release_focus()
	_refresh_focus()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _field_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	return style

func _layout_stage() -> void:
	if not is_instance_valid(stage):
		return
	stage.scale = Vector2.ONE
	stage.position = Vector2.ZERO
