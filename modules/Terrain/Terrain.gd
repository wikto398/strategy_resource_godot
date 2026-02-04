class_name Terrain

enum TerrainType {
	GRASS,
	WATER,
	MOUNTAIN,
	SAND
}

static var textures: Dictionary = {
	TerrainType.GRASS: _load_textures_from_path("res://assets/terrain/grass"),
	TerrainType.WATER: _load_textures_from_path("res://assets/terrain/water"),
	TerrainType.MOUNTAIN: _load_textures_from_path("res://assets/terrain/mountain"),
	TerrainType.SAND: _load_textures_from_path("res://assets/terrain/sand")
}

static func _load_textures_from_path(path: String) -> PackedStringArray:
	var texture_file_names := ResourceLoader.list_directory(path)
	var texture_paths := PackedStringArray()
	for texture in texture_file_names:
		if texture.ends_with(".png") or texture.ends_with(".jpg"):
			texture_paths.append(path + "/" + texture)
	return texture_paths

static func get_texture_for_type(terrain_type: TerrainType) -> Texture2D:
	return load(textures[terrain_type][randi() % textures[terrain_type].size()]) as Texture2D
