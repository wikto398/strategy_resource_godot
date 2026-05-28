class_name TerrainFieldGrid extends PointyHexGrid

const PROBABILITY_WATER_TO_GRASS = [1, 3]
const PROBABILITY_BORDER_GRASS = [1, 4, 2]
const PROBABILITY_INNER_GRASS = [1, 6, 3]
const STRUCTURE_PLACEMENT_PROBABILITY = 0.4

signal unhighlight_all_fields
signal update_visuals()
signal field_clicked(field: TerrainField)

func _ready():
	super._ready()
	_add_empty_fields()
	generate_ca_map(3)
	_set_boundary_fields()
	_fill_island_with_terrain()
	_add_structures()
	update_visuals.emit()
	_center()

func _add_empty_fields():
	var field_scene = load("uid://bfrqdhxq3pe6x")
	var base_terrains = [Terrain.TerrainType.WATER, Terrain.TerrainType.GRASS]
	var random = RandomNumberGenerator.new()
	for q in range(columns):
		for r in range(rows):
			var field := field_scene.instantiate() as TerrainField
			field.terrain_type = base_terrains[random.rand_weighted(PROBABILITY_WATER_TO_GRASS)]
			add_child(field)
			unhighlight_all_fields.connect(field._on_unhighlight)
			field.field_clicked.connect(_on_field_clicked)
			update_visuals.connect(field._set_texture)

			# field.z_index = q + r * columns

			var pos := _hex_to_pixel(q, r)
			field.position = pos

			var tex_size := field.terrain.texture.get_size()
			var hex_scale := (2.0 * hex_size) / tex_size.y
			field.scale = Vector2.ONE * hex_scale

			fields[Vector2i(q, r)] = field
			field.grid_position = Vector2i(q, r)

func _set_boundary_fields():
	for coords in fields:
		if _is_boundary(coords):
			fields[coords].terrain_type = Terrain.TerrainType.WATER

func _hex_to_pixel(q: int, r: int) -> Vector2:
	var x := hex_size * sqrt(3) * (q + 0.5 * (r & 1))
	var y := hex_size * 1.5 * r
	return Vector2(x, y)

func _is_boundary(v: Vector2i) -> bool:
	return v.x == 0 or v.y == 0 or v.x == columns - 1 or v.y == rows - 1

func get_field_at(v: Vector2i) -> TerrainField:
	return fields.get(v, null)

func _center():
	var viewport_center := get_viewport_rect().size * 0.5

	var children = get_children()
	if children.size() == 0: return

	var rect = Rect2(children[0].position, Vector2.ZERO)

	for i in range(1, children.size()):
		var field = children[i]
		if field is Node2D:
			rect = rect.expand(field.position)

	var grid_center = rect.position + (rect.size * 0.5)

	position = viewport_center - grid_center

func _on_field_clicked(field: TerrainField) -> void:
	DebugLogger.trace("TerrainField clicked at position: " + str(field.grid_position) + " with global position: " + str(field.global_position))
	field_clicked.emit(field)

func generate_ca_map(iterations: int = 3):
	for i in range(iterations):
		_run_ca_step()

func _run_ca_step():
	var new_types = {}

	for coords in fields:
		var grass_neighbors = 0
		var neighbors = get_neighbours(coords)

		for n in neighbors:
			if n.terrain_type == Terrain.TerrainType.GRASS:
				grass_neighbors += 1

		var current_type = fields[coords].terrain_type
		if current_type == Terrain.TerrainType.GRASS:
			new_types[coords] = Terrain.TerrainType.GRASS if grass_neighbors >= 4 else Terrain.TerrainType.WATER
		else:
			new_types[coords] = Terrain.TerrainType.GRASS if grass_neighbors >= 5 else Terrain.TerrainType.WATER

	for coords in new_types:
		fields[coords].terrain_type = new_types[coords]

func _fill_island_with_terrain():
	var borders = []
	var non_borders = []
	var is_border = false
	for coords in fields:
		var field = fields[coords]
		is_border = false
		if field.terrain_type == Terrain.TerrainType.GRASS:
			var neighbors = get_neighbours(coords)
			for n in neighbors:
				if n.terrain_type == Terrain.TerrainType.WATER:
					is_border = true
					break
			if is_border:
				borders.append(field)
			else:
				non_borders.append(field)

	var random = RandomNumberGenerator.new()
	var terrain_types = [Terrain.TerrainType.SAND, Terrain.TerrainType.GRASS, Terrain.TerrainType.MOUNTAIN]
	for border_field in borders:
		border_field.terrain_type = terrain_types[random.rand_weighted(PROBABILITY_BORDER_GRASS)]

	for non_border_field in non_borders:
		non_border_field.terrain_type = terrain_types[random.rand_weighted(PROBABILITY_INNER_GRASS)]

func _add_structures():
	var grouped_structures = _group_structures_by_terrain(ResourceDatabase.load_structures())
	DebugLogger.trace("Grouped structures by terrain: " + str(grouped_structures))
	for coords in fields:
		var field = fields[coords]
		if field.terrain_type in grouped_structures and randf() < STRUCTURE_PLACEMENT_PROBABILITY:
			var possible_structures = grouped_structures[field.terrain_type]
			field.structure = possible_structures[randi() % possible_structures.size()]

func _group_structures_by_terrain(structures: Array[Structure]) -> Dictionary[Terrain.TerrainType, Array]:
	var grouped: Dictionary[Terrain.TerrainType, Array] = {}
	for structure in structures:
		for terrain_type in structure.field_types:
			if not grouped.has(terrain_type):
				grouped[terrain_type] = []
			grouped[terrain_type].append(structure)
	return grouped

func get_nearest_walkable_fields(start: Vector2i, amount: int) -> Array[TerrainField]:
	var result: Array[TerrainField] = []
	var visited: Dictionary[Vector2i, bool] = {}
	var queue: Array[Vector2i] = [start]
	var distance: Dictionary[Vector2i, int] = {start: 0}
	var max_distance: int = 10

	while queue.size() > 0 and result.size() < amount:
		var current = queue.pop_front()
		if distance[current] > max_distance:
			continue

		if fields[current].walkable:
			result.append(fields[current])

		for neighbor in get_neighbours(current):
			if not visited.has(neighbor.grid_position):
				visited[neighbor.grid_position] = true
				queue.append(neighbor.grid_position)
				distance[neighbor.grid_position] = distance[current] + 1

	return result

func observation() -> Array:
	var obs: Array = []
	for coords in fields:
		obs.append(fields[coords].observation())
	return obs
