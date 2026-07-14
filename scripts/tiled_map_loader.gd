class_name TiledMapLoader
extends RefCounted

var map_id := ""
var width := 0
var height := 0
var tile_width := 16
var tile_height := 16
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
	tile_width = int(map_attrs.get("tilewidth", 16))
	tile_height = int(map_attrs.get("tileheight", 16))
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
		var object_rect := Rect2(float(object.get("x", 0.0)), float(object.get("y", 0.0)), float(object.get("width", tile_width)), float(object.get("height", tile_height)))
		if object_rect.size.x <= 0.0:
			object_rect.size.x = float(tile_width)
		if object_rect.size.y <= 0.0:
			object_rect.size.y = float(tile_height)
		if object_rect.intersects(tile_rect) or tile_rect.encloses(object_rect):
			return object
	return {}

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
	if selected.is_empty() or not selected.has("texture"):
		return {}
	var local_id := gid - int(selected.first_gid)
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
	if image_source.is_empty():
		return
	var image_path := tsx_path.get_base_dir().path_join(image_source).simplify_path()
	var texture := load(image_path) as Texture2D
	if not texture:
		return
	tilesets.append({
		"first_gid": first_gid,
		"tile_width": int(tsx_attrs.get("tilewidth", 16)),
		"tile_height": int(tsx_attrs.get("tileheight", 16)),
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

func _first_match(text: String, pattern: String, dotall := false) -> String:
	var regex := RegEx.new()
	regex.compile(("(?s)" if dotall else "") + pattern)
	var match := regex.search(text)
	return match.get_string(1) if match else ""

func _all_matches(text: String, pattern: String, dotall := false) -> Array[RegExMatch]:
	var regex := RegEx.new()
	regex.compile(("(?s)" if dotall else "") + pattern)
	return regex.search_all(text)
