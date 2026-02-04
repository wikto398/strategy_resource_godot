class_name Field extends Node2D

signal field_clicked(field: Field)

@onready var elements: Node2D = $Elements
@onready var terrain: Sprite2D = $Elements/Terrain
@onready var building_texture: Sprite2D = $Elements/Building

@export var terrain_type: Terrain.TerrainType = Terrain.TerrainType.GRASS
@export var walkable: bool = true:
	set(value):
		walkable = value
		set_unwalkable()
@export var building: Building:
	set(value):
		building = value
		if building:
			building_texture.texture = building.icon
		else:
			building_texture.texture = null
@export var grid_position: Vector2i = Vector2i.ZERO

func _ready():
	_set_texture()

func set_unwalkable():
	if walkable:
		terrain.modulate = Color(1, 1, 1, 1)
	else:
		terrain.modulate = Color(1, 0, 0, 0.5)

func set_buildable(buildable: bool):
	if buildable:
		terrain.modulate = Color(0, 1, 0, 0.5)
	else:
		set_unwalkable()

func _set_texture():
	terrain.texture = Terrain.get_texture_for_type(terrain_type)

func _on_area_2d_mouse_entered() -> void:
	material = Shaders.load_shader("hovered")

func _on_area_2d_mouse_exited() -> void:
	material = null

func _on_unhighlight() -> void:
	terrain.modulate = Color(1, 1, 1, 1)

func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			field_clicked.emit(self)
