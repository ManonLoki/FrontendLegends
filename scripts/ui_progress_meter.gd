class_name UiProgressMeter
extends Control

var current := 0
var total := 1
var meter_font: Font = preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")
var meter_font_size := 12
var fill_color := Color("343434")
var track_color := Color("faf9f5")
var border_color := Color("55524c")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func set_progress(value: int, maximum: int) -> void:
	current = maxi(0, value)
	# Keep the true maximum (including 0) for display; _draw() clamps separately
	# for the fill-ratio math so a genuine 0 max still reads "0/0" in the label
	# instead of being silently rewritten to "0/1".
	total = maxi(0, maximum)
	queue_redraw()

func set_font_size(value: int) -> void:
	meter_font_size = maxi(10, value)
	queue_redraw()

func set_colors(fill: Color, track: Color = Color("faf9f5"), border: Color = Color("55524c")) -> void:
	fill_color = fill
	track_color = track
	border_color = border
	queue_redraw()

func _draw() -> void:
	var text_width := 82.0 * size.y / 28.0
	var bar_rect := Rect2(Vector2.ZERO, Vector2(maxf(1.0, size.x - text_width), size.y))
	draw_rect(bar_rect, track_color, true)
	draw_rect(bar_rect, border_color, false, 2.0)
	var ratio := clampf(float(current) / float(maxi(1, total)), 0.0, 1.0)
	if ratio > 0.0:
		draw_rect(Rect2(bar_rect.position + Vector2(3.0, 3.0), Vector2(maxf(0.0, (bar_rect.size.x - 6.0) * ratio), maxf(0.0, bar_rect.size.y - 6.0))), fill_color, true)
	var text := "%d/%d" % [current, total]
	draw_string(meter_font, Vector2(bar_rect.end.x + 10.0, size.y * 0.72), text, HORIZONTAL_ALIGNMENT_LEFT, text_width - 10.0, meter_font_size, Color("343434"))
