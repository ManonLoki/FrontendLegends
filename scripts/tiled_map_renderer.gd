extends Node2D

class_name TiledMapRenderer

const MAP_TEXT_FONT := preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")

var context: TiledMapLoader
var map_origin := Vector2.ZERO
var camera_rect := Rect2()
var zoom := 1.0

func set_context(value: TiledMapLoader) -> void:
	context = value
	queue_redraw()

func set_camera(world_top_left: Vector2, draw_origin: Vector2, world_view_size: Vector2, scale: float) -> void:
	camera_rect = Rect2(world_top_left, world_view_size)
	map_origin = draw_origin
	zoom = scale
	queue_redraw()

func _draw() -> void:
	if not context:
		return
	var col_range := _visible_axis_range(camera_rect.position.x, camera_rect.size.x, context.tile_width, context.width)
	var row_range := _visible_axis_range(camera_rect.position.y, camera_rect.size.y, context.tile_height, context.height)
	var draw_order := ["Background", "Road", "Prop"]
	for layer_name in draw_order:
		var gids: PackedInt32Array = context.layers.get(layer_name, PackedInt32Array())
		for row in range(row_range.x, row_range.y):
			for col in range(col_range.x, col_range.y):
				var index := row * context.width + col
				if index >= gids.size() or gids[index] == 0:
					continue
				var tile := context.tile_region(gids[index] & 0x1fffffff)
				if tile.is_empty():
					continue
				# 图块层采用图块集原始尺寸；正交地图中的超大图块以单元格左下角为锚点。
				var world_position := Vector2(col * context.tile_width, row * context.tile_height)
				var draw_size: Vector2 = tile.source.size
				var draw_position := world_position + Vector2(0.0, context.tile_height - draw_size.y)
				draw_texture_rect_region(tile.texture, Rect2(map_origin + draw_position * zoom, draw_size * zoom), tile.source)
	_draw_tile_objects()
	_draw_text_objects()

## 由相机矩形推导可见的行/列半开区间，避免每次重绘全图扫描；相机未设置时覆盖整图。
func _visible_axis_range(start: float, size: float, tile_size: int, cell_count: int) -> Vector2i:
	if size <= 0.0:
		return Vector2i(0, cell_count)
	var from := clampi(floori(start / float(tile_size)), 0, cell_count)
	var to := clampi(ceili((start + size) / float(tile_size)), 0, cell_count)
	return Vector2i(from, to)

func _draw_tile_objects() -> void:
	for object in context.objects:
		var gid := int(object.get("gid", 0))
		if gid == 0:
			continue
		var object_size := Vector2(float(object.get("width", context.tile_width)), float(object.get("height", context.tile_height)))
		# Tiled 的图块对象坐标以左下角为基准。
		var world_position := Vector2(float(object.get("x", 0.0)), float(object.get("y", 0.0)) - object_size.y)
		var world_rect := Rect2(world_position, object_size)
		if camera_rect.size.x > 0.0 and camera_rect.size.y > 0.0 and not world_rect.intersects(camera_rect):
			continue
		var tile := context.tile_region(gid & 0x1fffffff)
		if tile.is_empty():
			continue
		# 图块对象使用 TMX 明确记录的宽高，不受源图片原始尺寸限制。
		draw_texture_rect_region(tile.texture, Rect2(map_origin + world_position * zoom, object_size * zoom), tile.source)

func _draw_text_objects() -> void:
	for object in context.objects:
		var text := str(object.get("text", ""))
		if text.is_empty():
			continue
		var world_position := Vector2(float(object.get("x", 0.0)), float(object.get("y", 0.0)))
		var world_size := Vector2(float(object.get("width", 0.0)), float(object.get("height", 0.0)))
		var world_rect := Rect2(world_position, world_size)
		if camera_rect.size.x > 0.0 and camera_rect.size.y > 0.0 and not world_rect.intersects(camera_rect):
			continue
		var options: Dictionary = object.get("text_options", {})
		var pixel_size := maxi(1, int(options.get("pixelsize", 16)))
		var draw_position := map_origin + world_position * zoom
		# 画布文字以首行基线定位，而 Tiled 对象记录的是左上角坐标。
		draw_position.y += float(pixel_size) * zoom
		var wrap_width := world_size.x * zoom if int(options.get("wrap", 0)) != 0 and world_size.x > 0.0 else -1.0
		draw_multiline_string(MAP_TEXT_FONT, draw_position, text, HORIZONTAL_ALIGNMENT_LEFT, wrap_width, int(round(float(pixel_size) * zoom)), -1, Color.BLACK)
