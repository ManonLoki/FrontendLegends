extends Node2D

class_name TiledMapRenderer

const MAP_TEXT_FONT := preload("res://assets/Font/fusion-pixel-12px-proportional-zh_hans.ttf")

var context: TiledMapLoader
var map_origin := Vector2.ZERO
var camera_rect := Rect2()
var zoom := 1.0

# 设置context相关逻辑，并保持调用方状态一致。
func set_context(value: TiledMapLoader) -> void:
	context = value
	queue_redraw()

# 设置camera相关逻辑，并保持调用方状态一致。
func set_camera(world_top_left: Vector2, draw_origin: Vector2, world_view_size: Vector2, scale: float) -> void:
	camera_rect = Rect2(world_top_left, world_view_size)
	map_origin = draw_origin
	zoom = scale
	queue_redraw()

# 绘制draw相关逻辑，并保持调用方状态一致。
func _draw() -> void:
	if not context:
		return
	var draw_order := ["Background", "Road", "Prop"]
	for layer_name in draw_order:
		var gids: PackedInt32Array = context.layers.get(layer_name, PackedInt32Array())
		for row in context.height:
			for col in context.width:
				var index := row * context.width + col
				if index >= gids.size() or gids[index] == 0:
					continue
				var world_position := Vector2(col * context.tile_width, row * context.tile_height)
				var world_rect := Rect2(world_position, Vector2(context.tile_width, context.tile_height))
				if camera_rect.size.x > 0.0 and camera_rect.size.y > 0.0 and not world_rect.intersects(camera_rect):
					continue
				var tile := context.tile_region(gids[index] & 0x1fffffff)
				if tile.is_empty():
					continue
				# 图块层采用图块集原始尺寸；正交地图中的超大图块以单元格左下角为锚点。
				var draw_size: Vector2 = tile.source.size
				var draw_position := world_position + Vector2(0.0, context.tile_height - draw_size.y)
				draw_texture_rect_region(tile.texture, Rect2(map_origin + draw_position * zoom, draw_size * zoom), tile.source)
	_draw_tile_objects()
	_draw_text_objects()

# 绘制tile、objects相关逻辑，并保持调用方状态一致。
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

# 绘制text、objects相关逻辑，并保持调用方状态一致。
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
