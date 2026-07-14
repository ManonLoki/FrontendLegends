extends Node2D

class_name TiledMapRenderer

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
				draw_texture_rect_region(tile.texture, Rect2(map_origin + world_position * zoom, Vector2(context.tile_width, context.tile_height) * zoom), tile.source)
