class_name UiProgressMeter
extends Control

## 当前已完成的进度值。
var current := 0
## 当前进度目标；允许为零，以便界面如实显示“0/0”。
var total := 1
## 进度文字使用项目统一中文像素字体。
var meter_font: Font = preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")
## 进度文字字号，最小不得低于 10。
var meter_font_size := 12
## 已完成区域、未完成轨道和边框的绘制颜色。
var fill_color := Color("343434")
var track_color := Color("faf9f5")
var border_color := Color("55524c")

## 控件不拦截鼠标事件，并在进入场景树时申请首次绘制。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

## 写入真实进度；目标为零时仍保留零，只在比例计算阶段临时防止除零。
func set_progress(value: int, maximum: int) -> void:
	current = maxi(0, value)
	total = maxi(0, maximum)
	queue_redraw()

## 更新文字字号并重绘。
func set_font_size(value: int) -> void:
	meter_font_size = maxi(10, value)
	queue_redraw()

## 一次设置完整配色，避免调用方分别改写绘制状态。
func set_colors(fill: Color, track: Color = Color("faf9f5"), border: Color = Color("55524c")) -> void:
	fill_color = fill
	track_color = track
	border_color = border
	queue_redraw()

## 按控件当前尺寸依次绘制轨道、边框、填充区域和数值文字。
func _draw() -> void:
	## 右侧预留随高度缩放的文字区域。
	var text_width := 82.0 * size.y / 28.0
	## 左侧剩余空间作为进度条主体，宽度至少为一个像素。
	var bar_rect := Rect2(Vector2.ZERO, Vector2(maxf(1.0, size.x - text_width), size.y))
	draw_rect(bar_rect, track_color, true)
	draw_rect(bar_rect, border_color, false, 2.0)
	## 分母只在计算比例时钳为 1，显示文本仍使用真实目标值。
	var ratio := clampf(float(current) / float(maxi(1, total)), 0.0, 1.0)
	if ratio > 0.0:
		draw_rect(Rect2(bar_rect.position + Vector2(3.0, 3.0), Vector2(maxf(0.0, (bar_rect.size.x - 6.0) * ratio), maxf(0.0, bar_rect.size.y - 6.0))), fill_color, true)
	## 数值文本使用“当前/目标”格式并绘制在进度条右侧。
	var text := "%d/%d" % [current, total]
	draw_string(meter_font, Vector2(bar_rect.end.x + 10.0, size.y * 0.72), text, HORIZONTAL_ALIGNMENT_LEFT, text_width - 10.0, meter_font_size, Color("343434"))
