class_name Field extends Node2D

const UNWALKABLE_TERRAIN_TYPES = [Terrain.TerrainType.WATER, Terrain.TerrainType.MOUNTAIN]

const UNALLOWED_MODULATION = Color(0.5, 0.5, 0.5, 0.5)
const UNAVAIABLE_MODULATION = Color(1, 0, 0, 0.5)
const AVAILABLE_MODULATION = Color(0, 1, 0, 0.5)
const DEFAULT_MODULATION = Color(1, 1, 1, 1)

signal field_clicked(field: Field)
signal unit_moved_out()

var unit: Unit = null:
	set(value):
		unit = value
		if not unit:
			unit_moved_out.emit()

@onready var elements: Node2D = $Elements
@onready var terrain: Sprite2D = $Elements/Terrain
@onready var building_texture: Sprite2D = $Elements/Building

@export var terrain_type: Terrain.TerrainType = Terrain.TerrainType.GRASS:
	set(value):
		terrain_type = value
		walkable = false if terrain_type in UNWALKABLE_TERRAIN_TYPES else true
@export var walkable: bool = true:
	set(value):
		walkable = value
@export var building: Building:
	set(value):
		building = value
		if building:
			building_texture.texture = building.icon
		else:
			building_texture.texture = null
@export var grid_position: Vector2i = Vector2i.ZERO

var movement_cost: int = 1

func _ready():
	_set_texture()

func set_unwalkable():
	terrain.modulate = DEFAULT_MODULATION if walkable else UNAVAIABLE_MODULATION

func set_buildable(buildable: bool):
	terrain.modulate = AVAILABLE_MODULATION if buildable else UNALLOWED_MODULATION

func _set_texture():
	terrain.texture = Terrain.get_texture_for_type(terrain_type)

func _on_area_2d_mouse_entered() -> void:
	material = Shaders.load_shader("hovered")

func _on_area_2d_mouse_exited() -> void:
	material = null

func _on_unhighlight() -> void:
	terrain.modulate = DEFAULT_MODULATION

func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			field_clicked.emit(self)
