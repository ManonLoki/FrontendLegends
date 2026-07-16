extends RefCounted
## 玩家图集帧、世界/屏幕坐标换算与相机渲染。

var game: Node2D

func _init(owner: Node2D) -> void:
	game = owner

func draw() -> void:
	var grid_origin := map_draw_origin()
	var cell := float(TiledMapLoader.DEFAULT_TILE_SIZE) * render_scale()
	if not game.map_context:
		for y in range(10):
			for x in range(TiledMapLoader.DEFAULT_TILE_SIZE):
				game.draw_rect(Rect2(grid_origin + Vector2(x, y) * cell, Vector2(cell - 1, cell - 1)), Color("#274f45"))
	var player_pos := world_to_screen(Vector2(game.player_tile) * Vector2(TiledMapLoader.DEFAULT_TILE_SIZE, TiledMapLoader.DEFAULT_TILE_SIZE)) + Vector2(1, 1) * render_scale()
	game._draw_npcs()
	var frame_key := player_frame_key()
	var source := player_frame_region(frame_key)
	var draw_rect := player_frame_draw_rect(player_pos, source, frame_key)
	var horizontal_shear := player_frame_horizontal_shear()
	if is_zero_approx(horizontal_shear):
		game.draw_texture_rect_region(game.player_texture, draw_rect, source)
	else:
		# 以脚底中心为固定轴剪切侧身帧，只扶正上半身，不移动角色所处逻辑格。
		var foot_pivot := Vector2(draw_rect.get_center().x, draw_rect.end.y)
		var shear_transform := Transform2D(Vector2(1.0, 0.0), Vector2(horizontal_shear, 1.0), foot_pivot)
		game.draw_set_transform_matrix(shear_transform)
		game.draw_texture_rect_region(game.player_texture, Rect2(draw_rect.position - foot_pivot, draw_rect.size), source)
		game.draw_set_transform_matrix(Transform2D.IDENTITY)

func load_player_sprite_regions() -> void:
	game.player_sprite_regions.clear()
	game.player_sprite_layouts.clear()
	var player_image: Image = game.player_texture.get_image()
	var file := FileAccess.open("res://assets/Texture/player.tpsheet", FileAccess.READ)
	if not file:
		return
	var sheet = JSON.parse_string(file.get_as_text())
	if not sheet is Dictionary:
		return
	var textures: Array = sheet.get("textures", [])
	if textures.is_empty():
		return
	var maximum_canvas_size := Vector2.ZERO
	for sprite_value in textures[0].get("sprites", []):
		var sprite: Dictionary = sprite_value
		var key := str(sprite.get("filename", "")).get_file().get_basename()
		var region: Dictionary = sprite.get("region", {})
		var margin: Dictionary = sprite.get("margin", {})
		var packed_size := Vector2(float(region.get("w", 0)), float(region.get("h", 0)))
		if key.is_empty() or packed_size.x <= 0.0 or packed_size.y <= 0.0:
			continue
		game.player_sprite_regions[key] = Rect2(float(region.get("x", 0)), float(region.get("y", 0)), packed_size.x, packed_size.y)
		var trim_offset := Vector2(float(margin.get("x", 0)), float(margin.get("y", 0)))
		var source_canvas_size := trim_offset + packed_size + Vector2(float(margin.get("w", 0)), float(margin.get("h", 0)))
		maximum_canvas_size = maximum_canvas_size.max(source_canvas_size)
		var foot_center_x := _opaque_foot_center_x(player_image, Rect2i(int(region.get("x", 0)), int(region.get("y", 0)), int(packed_size.x), int(packed_size.y)))
		game.player_sprite_layouts[key] = {"offset": trim_offset, "source_canvas_size": source_canvas_size, "foot_center_x": trim_offset.x + foot_center_x}
	for key in game.player_sprite_layouts:
		var layout: Dictionary = game.player_sprite_layouts[key]
		var source_canvas_size: Vector2 = layout.source_canvas_size
		var canvas_padding := (maximum_canvas_size - source_canvas_size) * 0.5
		layout.offset = canvas_padding + Vector2(layout.offset)
		# 贴图内部的脚部支点不一定位于透明画布中心；只修正绘制位置，不影响逻辑格与碰撞。
		var normalized_foot_x := canvas_padding.x + float(layout.foot_center_x)
		layout.visual_offset = Vector2(round(maximum_canvas_size.x * 0.5 - normalized_foot_x), 0.0)
		layout.canvas_size = maximum_canvas_size
		game.player_sprite_layouts[key] = layout

# 以帧底部三行不透明像素的平均横坐标估算角色双脚支点。
func _opaque_foot_center_x(image: Image, region: Rect2i) -> float:
	if image == null or image.is_empty() or region.size.x <= 0 or region.size.y <= 0:
		return float(region.size.x) * 0.5
	var bottom_y := -1
	for local_y in range(region.size.y - 1, -1, -1):
		for local_x in region.size.x:
			if image.get_pixel(region.position.x + local_x, region.position.y + local_y).a > 0.05:
				bottom_y = local_y
				break
		if bottom_y >= 0:
			break
	if bottom_y < 0:
		return float(region.size.x) * 0.5
	var x_total := 0.0
	var pixel_count := 0
	for local_y in range(maxi(0, bottom_y - 2), bottom_y + 1):
		for local_x in region.size.x:
			if image.get_pixel(region.position.x + local_x, region.position.y + local_y).a > 0.05:
				x_total += local_x
				pixel_count += 1
	return x_total / float(pixel_count) if pixel_count > 0 else float(region.size.x) * 0.5

func player_frame_key() -> String:
	var gender := "female" if str(GameState.profile.get("gender", "male")).to_lower() == "female" else "male"
	var direction := "down"
	if game.facing == Vector2i.UP:
		direction = "up"
	elif game.facing == Vector2i.LEFT:
		direction = "left"
	elif game.facing == Vector2i.RIGHT:
		direction = "right"
	var frame := posmod(game.animation_frame, 4)
	if not game.player_moving or frame == 0 or frame == 2:
		return "player_%s_%s_idle_0" % [gender, direction]
	return "player_%s_%s_run_%d" % [gender, direction, 1 if frame == 1 else 3]

# 左右侧身帧的头脚轴线方向相反，以轻微剪切抵消贴图本身的倾斜。
func player_frame_horizontal_shear() -> float:
	if game.facing == Vector2i.LEFT:
		return -0.08
	if game.facing == Vector2i.RIGHT:
		return 0.08
	return 0.0

func player_frame_region(frame_key := "") -> Rect2:
	var key := frame_key if not frame_key.is_empty() else player_frame_key()
	return game.player_sprite_regions.get(key, game.player_sprite_regions.get("player_male_down_idle_0", Rect2(0, 0, 1, 1)))

func player_battle_portrait_region() -> Rect2:
	var gender := "female" if str(GameState.profile.get("gender", "male")).to_lower() == "female" else "male"
	var key := "player_%s_down_idle_0" % gender
	return game.player_sprite_regions.get(key, game.player_sprite_regions.get("player_male_down_idle_0", Rect2(0, 0, 1, 1)))

func player_frame_draw_rect(player_pos: Vector2, source: Rect2, frame_key := "") -> Rect2:
	var layout: Dictionary = game.player_sprite_layouts.get(frame_key if not frame_key.is_empty() else player_frame_key(), {})
	var canvas_size: Vector2 = layout.get("canvas_size", source.size)
	var trim_offset: Vector2 = layout.get("offset", Vector2.ZERO)
	var visual_offset: Vector2 = layout.get("visual_offset", Vector2.ZERO)
	var canvas_origin := player_pos + Vector2((TiledMapLoader.DEFAULT_TILE_SIZE - canvas_size.x) * 0.5, TiledMapLoader.DEFAULT_TILE_SIZE - canvas_size.y) * render_scale()
	return Rect2(canvas_origin + (trim_offset + visual_offset) * render_scale(), source.size * render_scale())

func game_view_rect() -> Rect2:
	var viewport_size: Vector2 = game.get_viewport_rect().size
	var view_size: Vector2 = game.CAMERA_SIZE * view_scale()
	return Rect2((viewport_size - view_size) * 0.5, view_size)

func display_scale() -> float:
	return 1.0

# 地图相机与 480×320 逻辑视口一致；窗口缩放只由 Godot stretch 负责。
func view_scale() -> float:
	return game.get_viewport_rect().size.y / game.CAMERA_SIZE.y

func map_zoom() -> float:
	if not game.map_context:
		return 1.0
	# 室内地图保持 Tiled 的原始像素尺寸，避免小房间被自动拉伸。
	if game.map_context.properties.has("parentMap"):
		return 1.0
	var map_size := Vector2(game.map_context.width * game.map_context.tile_width, game.map_context.height * game.map_context.tile_height)
	return maxf(1.0, maxf(game.CAMERA_SIZE.x / map_size.x, game.CAMERA_SIZE.y / map_size.y))

func camera_world_size() -> Vector2:
	return game.CAMERA_SIZE / map_zoom()

func render_scale() -> float:
	return map_zoom() * view_scale()

func camera_world_top_left() -> Vector2:
	if not game.map_context:
		return Vector2.ZERO
	var map_size := Vector2(game.map_context.width * game.map_context.tile_width, game.map_context.height * game.map_context.tile_height)
	var world_size := camera_world_size()
	var player_center := (Vector2(game.player_tile) + Vector2(0.5, 0.5)) * Vector2(game.map_context.tile_width, game.map_context.tile_height)
	return Vector2(
		0.0 if map_size.x <= world_size.x else clampf(player_center.x - world_size.x * 0.5, 0.0, map_size.x - world_size.x),
		0.0 if map_size.y <= world_size.y else clampf(player_center.y - world_size.y * 0.5, 0.0, map_size.y - world_size.y),
	)

func is_world_tile_visible(tile: Vector2) -> bool:
	if not game.map_context:
		return false
	var tile_size := Vector2(game.map_context.tile_width, game.map_context.tile_height)
	return Rect2(tile * tile_size, tile_size).intersects(Rect2(camera_world_top_left(), camera_world_size()))

func map_draw_origin() -> Vector2:
	var view_rect := game_view_rect()
	if not game.map_context:
		return view_rect.position
	var map_size := Vector2(game.map_context.width * game.map_context.tile_width, game.map_context.height * game.map_context.tile_height)
	var scale := render_scale()
	var origin := view_rect.position - camera_world_top_left() * scale
	var scaled_map_size := map_size * scale
	if scaled_map_size.x < view_rect.size.x:
		origin.x += (view_rect.size.x - scaled_map_size.x) * 0.5
	if scaled_map_size.y < view_rect.size.y:
		origin.y += (view_rect.size.y - scaled_map_size.y) * 0.5
	return origin

func world_to_screen(world_position: Vector2) -> Vector2:
	return map_draw_origin() + world_position * render_scale()

func update_camera() -> void:
	if not game.map_context:
		return
	game.map_renderer.set_camera(camera_world_top_left(), map_draw_origin(), camera_world_size(), render_scale())
	game.queue_redraw()
