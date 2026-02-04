class_name FieldGrid
extends Node2D

signal unhighlight_all_fields
signal field_clicked(field: Field)

@export var columns: int
@export var rows: int
@export var hex_size: float = 16.0

var fields: Dictionary = {}

func _ready():
	_add_empty_fields()
	_center()

func _add_empty_fields():
	var field_scene = load("uid://bfrqdhxq3pe6x")

	for q in range(columns):
		for r in range(rows):
			var field := field_scene.instantiate() as Field
			field.terrain_type = Terrain.TerrainType.values().pick_random()
			add_child(field)
			unhighlight_all_fields.connect(field._on_unhighlight)
			field.field_clicked.connect(_on_field_clicked)

			field.z_index = q + r * columns

			var pos := _hex_to_pixel(q, r)
			field.position = pos

			var tex_size := field.terrain.texture.get_size()
			var hex_scale := (2.0 * hex_size) / tex_size.y
			field.elements.scale = Vector2.ONE * hex_scale

			fields[Vector2i(q, r)] = field
			field.grid_position = Vector2i(q, r)

func _hex_to_pixel(q: int, r: int) -> Vector2:
	var x := hex_size * sqrt(3) * (q + 0.5 * (r & 1))
	var y := hex_size * 1.5 * r
	return Vector2(x, y)

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
	print("Field clicked at position: ", field.grid_position)
	field_clicked.emit(field)