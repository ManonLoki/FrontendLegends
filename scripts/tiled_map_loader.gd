class_name TiledMapLoader
extends RefCounted

## Tiled 地图/图块集未显式声明 tilewidth/tileheight 时使用的默认边长。
const DEFAULT_TILE_SIZE := 16

var map_id := ""
var width := 0
var height := 0
var tile_width := DEFAULT_TILE_SIZE
var tile_height := DEFAULT_TILE_SIZE
var properties: Dictionary = {}
var layers: Dictionary = {}
var objects: Array[Dictionary] = []
var tilesets: Array[Dictionary] = []

func load_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var xml := file.get_as_text()
	map_id = path.get_file().get_basename()
	var map_attrs := _attrs(_first_match(xml, "<map\\b([^>]*)>"))
	width = int(map_attrs.get("width", 0))
	height = int(map_attrs.get("height", 0))
	tile_width = int(map_attrs.get("tilewidth", DEFAULT_TILE_SIZE))
	tile_height = int(map_attrs.get("tileheight", DEFAULT_TILE_SIZE))
	properties = _properties(_first_match(xml, "<map\\b[^>]*>(.*?)<tileset", true))
	for match in _all_matches(xml, "<tileset\\b([^>]*?)(?:/>|>(.*?)</tileset>)", true):
		_load_tileset(path, _attrs(match.get_string(1)), match.get_string(2))
	for match in _all_matches(xml, "<layer\\b([^>]*)>(.*?)</layer>", true):
		var attrs: Dictionary = _attrs(match.get_string(1))
		var data_match := _first_match(match.get_string(2), "<data\\b[^>]*>(.*?)</data>", true)
		layers[attrs.get("name", "layer")] = _decode_layer(data_match)
	for match in _all_matches(xml, "<object\\b([^>]*?)(?:/>|>(.*?)</object>)", true):
		var object_attrs: Dictionary = _attrs(match.get_string(1))
		var body := match.get_string(2)
		var object: Dictionary = object_attrs.duplicate()
		object["x"] = float(object.get("x", 0))
		object["y"] = float(object.get("y", 0))
		object["properties"] = _properties(body)
		var text_match := _match(body, "<text\\b([^>]*)>(.*?)</text>", true)
		if text_match:
			object["text"] = _decode_xml_text(text_match.get_string(2))
			object["text_options"] = _attrs(text_match.get_string(1))
		objects.append(object)
	return width > 0 and height > 0

func is_walkable(col: int, row: int) -> bool:
	if col < 0 or row < 0 or col >= width or row >= height:
		return false
	var road: PackedInt32Array = layers.get("Road", PackedInt32Array())
	return road.size() > row * width + col and road[row * width + col] != 0

func npc_objects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for object in objects:
		if object.get("type", "") == "NPC" or object.get("properties", {}).has("npcId"):
			result.append(object)
	return result

func transaction_objects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for object in objects:
		var properties: Dictionary = object.get("properties", {})
		if object.get("type", "") == "Transaction" or (properties.has("from") and properties.has("to")):
			result.append(object)
	return result

func spawn_point() -> Dictionary:
	for object in objects:
		var object_name := str(object.get("name", ""))
		var object_type := str(object.get("type", "")).to_lower()
		var properties: Dictionary = object.get("properties", {})
		var property_type := str(properties.get("type", "")).to_lower()
		if object_name == "SpawnPoint" or object_type == "spawnpoint" or property_type == "spawnpoint":
			return object
	return {}

func object_at_tile(col: int, row: int) -> Dictionary:
	var tile_rect := Rect2(float(col * tile_width), float(row * tile_height), float(tile_width), float(tile_height))
	for object in objects:
		if _object_occupies_tile(object, tile_rect):
			return object
	return {}

func interactable_object_at_tile(col: int, row: int) -> Dictionary:
	var tile_rect := Rect2(float(col * tile_width), float(row * tile_height), float(tile_width), float(tile_height))
	for object in objects:
		var object_properties: Dictionary = object.get("properties", {})
		if str(object_properties.get("event", "")).is_empty() and str(object_properties.get("text", "")).is_empty() and str(object_properties.get("questGiver", "")).is_empty():
			continue
		if _object_occupies_tile(object, tile_rect):
			return object
	return {}

func npc_object_at_tile(col: int, row: int) -> Dictionary:
	var tile_rect := Rect2(float(col * tile_width), float(row * tile_height), float(tile_width), float(tile_height))
	for object in objects:
		if str(object.get("properties", {}).get("npcId", "")).is_empty():
			continue
		if _object_occupies_tile(object, tile_rect):
			return object
	return {}

func pick_dynamic_npc_tile() -> Vector2i:
	var indoor := str(properties.get("cameraAutoFit", "false")).to_lower() == "true" or properties.has("parentMap")
	var candidates: Array[Vector2i] = []
	for row in height:
		for col in width:
			if not is_walkable(col, row) or _transaction_at_tile(col, row):
				continue
			if indoor:
				if is_walkable(col, row - 1) and _valid_dynamic_npc_tile(col, row):
					candidates.append(Vector2i(col, row))
				continue
			var horizontal := is_walkable(col - 1, row) or is_walkable(col + 1, row)
			var vertical := is_walkable(col, row - 1) or is_walkable(col, row + 1)
			if horizontal and not vertical:
				if row > 0 and not is_walkable(col, row - 1) and _valid_dynamic_npc_tile(col, row - 1):
					candidates.append(Vector2i(col, row - 1))
			elif vertical and not horizontal:
				for side_col in [col - 1, col + 1]:
					if side_col >= 0 and side_col < width and not is_walkable(side_col, row) and _valid_dynamic_npc_tile(side_col, row):
						candidates.append(Vector2i(side_col, row))
						break
	if not candidates.is_empty():
		return candidates[randi() % candidates.size()]
	var fallback: Array[Vector2i] = []
	for row in height:
		for col in width:
			if is_walkable(col, row) and _valid_dynamic_npc_tile(col, row):
				fallback.append(Vector2i(col, row))
	return fallback[randi() % fallback.size()] if not fallback.is_empty() else Vector2i(-1, -1)

func _valid_dynamic_npc_tile(col: int, row: int) -> bool:
	if col < 0 or row < 0 or col >= width or row >= height or _transaction_at_tile(col, row):
		return false
	var tile_rect := Rect2(float(col * tile_width), float(row * tile_height), float(tile_width), float(tile_height))
	for object in objects:
		var object_properties: Dictionary = object.get("properties", {})
		var is_npc := str(object.get("type", "")) == "NPC" or object_properties.has("npcId")
		var is_prop := str(object.get("type", "")) == "Props" or object_properties.has("event") or object_properties.has("questGiver") or object_properties.has("text")
		if (is_npc or is_prop) and _object_occupies_tile(object, tile_rect):
			return false
	return true

func _transaction_at_tile(col: int, row: int) -> bool:
	var tile_rect := Rect2(float(col * tile_width), float(row * tile_height), float(tile_width), float(tile_height))
	for object in transaction_objects():
		if _object_occupies_tile(object, tile_rect):
			return true
	return false

func _object_occupies_tile(object: Dictionary, tile_rect: Rect2) -> bool:
	var raw_width := float(object.get("width", 0.0))
	var raw_height := float(object.get("height", 0.0))
	# 与原项目 TileGeometry.tileOverlapsObject 一致：无 gid 的零尺寸 point
	# 对象（地图 NPC 的常见格式）只占 floor(x/tileW), floor(y/tileH) 单格。
	if int(object.get("gid", 0)) == 0 and raw_width <= 0.0 and raw_height <= 0.0:
		return Vector2i(
			floori(float(object.get("x", 0.0)) / tile_width),
			floori(float(object.get("y", 0.0)) / tile_height),
		) == Vector2i(floori(tile_rect.position.x / tile_width), floori(tile_rect.position.y / tile_height))
	var object_size := Vector2(raw_width if raw_width > 0.0 else tile_width, raw_height if raw_height > 0.0 else tile_height)
	if object_size.x <= 0.0:
		object_size.x = float(tile_width)
	if object_size.y <= 0.0:
		object_size.y = float(tile_height)
	var object_position := Vector2(float(object.get("x", 0.0)), float(object.get("y", 0.0)))
	if int(object.get("gid", 0)) != 0:
		object_position.y -= object_size.y
	var object_rect := Rect2(object_position, object_size)
	return object_rect.intersects(tile_rect)

func transaction_for_arrival(from_map: String, to_map: String, cyber := false) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for object in transaction_objects():
		var properties: Dictionary = object.get("properties", {})
		if str(properties.get("to", "")) != to_map:
			continue
		if cyber or str(properties.get("from", "")) == from_map:
			if is_walkable(int(floor(float(object.get("x", 0)) / tile_width)), int(floor(float(object.get("y", 0)) / tile_height))):
				candidates.append(object)
	if candidates.is_empty():
		return {}
	return candidates[randi() % candidates.size()] if cyber else candidates[0]

func tile_region(gid: int) -> Dictionary:
	var selected: Dictionary = {}
	for tileset in tilesets:
		if gid >= int(tileset.first_gid):
			selected = tileset
	if selected.is_empty():
		return {}
	var local_id := gid - int(selected.first_gid)
	var individual_tiles: Dictionary = selected.get("individual_tiles", {})
	if individual_tiles.has(local_id):
		var texture: Texture2D = individual_tiles[local_id]
		return {"texture": texture, "source": Rect2(Vector2.ZERO, texture.get_size())}
	if not selected.has("texture"):
		return {}
	var columns := maxi(1, int(selected.columns))
	var tile_w := int(selected.tile_width)
	var tile_h := int(selected.tile_height)
	var spacing := int(selected.spacing)
	var margin := int(selected.margin)
	var source := Rect2(margin + (local_id % columns) * (tile_w + spacing), margin + (local_id / columns) * (tile_h + spacing), tile_w, tile_h)
	return {"texture": selected.texture, "source": source}

func _load_tileset(map_path: String, attrs: Dictionary, body: String) -> void:
	var first_gid := int(attrs.get("firstgid", 1))
	var source_path := str(attrs.get("source", ""))
	var tsx_path := map_path.get_base_dir().path_join(source_path).simplify_path() if not source_path.is_empty() else map_path
	var tsx_xml := body
	if not source_path.is_empty():
		var tsx_file := FileAccess.open(tsx_path, FileAccess.READ)
		if not tsx_file:
			return
		tsx_xml = tsx_file.get_as_text()
	var tsx_attrs := _attrs(_first_match(tsx_xml, "<tileset\\b([^>]*)>"))
	var image_source := _first_match(tsx_xml, "<image\\b[^>]*source=\\\"([^\\\"]+)\\\"")
	# Image-collection tilesets have columns=0 and one <image> per <tile>.
	# A broad image search finds their first child image, so distinguish them
	# using the tileset metadata before taking the atlas path.
	if image_source.is_empty() or int(tsx_attrs.get("columns", 0)) == 0:
		var individual_tiles: Dictionary = {}
		for tile_match in _all_matches(tsx_xml, "<tile\\b([^>]*)>(.*?)</tile>", true):
			var tile_attrs := _attrs(tile_match.get_string(1))
			var tile_image := _first_match(tile_match.get_string(2), "<image\\b[^>]*source=\\\"([^\\\"]+)\\\"")
			if tile_image.is_empty():
				continue
			var tile_path := tsx_path.get_base_dir().path_join(tile_image).simplify_path()
			var tile_texture := load(tile_path) as Texture2D
			if tile_texture:
				individual_tiles[int(tile_attrs.get("id", 0))] = tile_texture
		if not individual_tiles.is_empty():
			tilesets.append({"first_gid": first_gid, "individual_tiles": individual_tiles})
		return
	var image_path := tsx_path.get_base_dir().path_join(image_source).simplify_path()
	var texture := load(image_path) as Texture2D
	if not texture:
		return
	tilesets.append({
		"first_gid": first_gid,
		"tile_width": int(tsx_attrs.get("tilewidth", DEFAULT_TILE_SIZE)),
		"tile_height": int(tsx_attrs.get("tileheight", DEFAULT_TILE_SIZE)),
		"columns": int(tsx_attrs.get("columns", 1)),
		"spacing": int(tsx_attrs.get("spacing", 0)),
		"margin": int(tsx_attrs.get("margin", 0)),
		"texture": texture,
	})

func _decode_layer(encoded: String) -> PackedInt32Array:
	var result := PackedInt32Array()
	if encoded.is_empty():
		return result
	var compressed := Marshalls.base64_to_raw(encoded.strip_edges())
	# Godot's DEFLATE mode is the zlib stream used by Tiled's base64 data.
	var raw: PackedByteArray = compressed.decompress_dynamic(maxi(4, width * height * 4), 1)
	for offset in range(0, raw.size() - 3, 4):
		result.append(raw[offset] | (raw[offset + 1] << 8) | (raw[offset + 2] << 16) | (raw[offset + 3] << 24))
	return result

func _properties(xml: String) -> Dictionary:
	var result: Dictionary = {}
	for match in _all_matches(xml, "<property\\b([^>]*)/>"):
		var attrs: Dictionary = _attrs(match.get_string(1))
		result[attrs.get("name", "")] = attrs.get("value", "")
	return result

func _attrs(text: String) -> Dictionary:
	var result: Dictionary = {}
	for match in _all_matches(text, "([A-Za-z_][A-Za-z0-9_]*)=\\\"([^\\\"]*)\\\""):
		result[match.get_string(1)] = match.get_string(2)
	return result

func _decode_xml_text(text: String) -> String:
	return text.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")

func _match(text: String, pattern: String, dotall := false) -> RegExMatch:
	var regex := RegEx.new()
	regex.compile(("(?s)" if dotall else "") + pattern)
	return regex.search(text)

func _first_match(text: String, pattern: String, dotall := false) -> String:
	var match := _match(text, pattern, dotall)
	return match.get_string(1) if match else ""

func _all_matches(text: String, pattern: String, dotall := false) -> Array[RegExMatch]:
	var regex := RegEx.new()
	regex.compile(("(?s)" if dotall else "") + pattern)
	return regex.search_all(text)
