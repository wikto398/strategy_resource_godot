class_name FieldGrid
extends Node2D

const PROBABILITY_WATER_TO_GRASS = [1, 3]
const PROBABILITY_BORDER_GRASS = [1, 4, 2]
const PROBABILITY_INNER_GRASS = [1, 6, 3]

signal unhighlight_all_fields
signal update_visuals()
signal field_clicked(field: Field)

@export var columns: int
@export var rows: int
@export var hex_size: float = 16.0

var fields: Dictionary = {}

static var instance: FieldGrid = null

func _ready():
	if instance:
		push_error("Multiple instances of FieldGrid detected. This is not supported.")
	else:
		instance = self
	_add_empty_fields()
	generate_ca_map(3)
	_set_boundary_fields()
	_fill_island_with_terrain()
	update_visuals.emit()
	_center()

func _add_empty_fields():
	var field_scene = load("uid://bfrqdhxq3pe6x")
	var base_terrains = [Terrain.TerrainType.WATER, Terrain.TerrainType.GRASS]
	var random = RandomNumberGenerator.new()
	for q in range(columns):
		for r in range(rows):
			var field := field_scene.instantiate() as Field
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

func get_field_at(v: Vector2i) -> Field:
	return fields.get(v, null)

const EVEN_R_DIRECTIONS := [
	Vector2i(-1, -1), Vector2i(0, -1),
	Vector2i(-1, 0),  Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),
]

const ODD_R_DIRECTIONS := [
	Vector2i(0, -1),  Vector2i(1, -1),
	Vector2i(-1, 0),  Vector2i(1, 0),
	Vector2i(0, 1),   Vector2i(1, 1),
]

func get_neighbors(v: Vector2i) -> Array[Field]:
	var result: Array[Field] = []
	var directions = EVEN_R_DIRECTIONS if (v.y & 1) == 0 else ODD_R_DIRECTIONS
	for d in directions:
		var f := get_field_at(v + d)
		if f:
			result.append(f)
	return result

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

func _on_field_clicked(field: Field) -> void:
	print("Field clicked at position: ", field.grid_position, " with global position: ", field.global_position)
	field_clicked.emit(field)

func generate_ca_map(iterations: int = 3):
	for i in range(iterations):
		_run_ca_step()

func _run_ca_step():
	var new_types = {}

	for coords in fields:
		var grass_neighbors = 0
		var neighbors = get_neighbors(coords)

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
			var neighbors = get_neighbors(coords)
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

func _calculate_field_bonuses():
	pass
