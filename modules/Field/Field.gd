class_name Field extends Node2D

const UNWALKABLE_TERRAIN_TYPES = [Terrain.TerrainType.WATER, Terrain.TerrainType.MOUNTAIN]

const UNALLOWED_MODULATION = Color(0.5, 0.5, 0.5, 0.5)
const UNAVAIABLE_MODULATION = Color(1, 0, 0, 0.5)
const AVAILABLE_MODULATION = Color(0, 1, 0, 0.5)
const DEFAULT_MODULATION = Color(1, 1, 1, 1)

signal field_clicked(field: Field)
signal building_finished(field: Field)
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
@export var grid_position: Vector2i = Vector2i.ZERO

var movement_cost: int = 1
var build_bonus: Dictionary[Enums.TownResource, Array] = {}
var current_bonus: Dictionary[Enums.TownResource, int] = {}
var in_progress_building: Building = null:
	set(value):
		in_progress_building = value
		if in_progress_building:
			building_texture.texture = in_progress_building.wip_icon

func _ready():
	_set_texture()
	Turn.next_turn.connect(_on_next_turn)

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

func add_bonus(bonus: BuildBonus) -> void:
	if bonus.bonus_type == BuildBonus.BonusType.MULTIPLIER:
		build_bonus[bonus.produced_resource].append(bonus)
	else:
		build_bonus[bonus.produced_resource].insert(0, bonus)

	_calculate_current_bonus(bonus.produced_resource)

func remove_bonus(bonus: BuildBonus) -> void:
	if build_bonus.has(bonus.produced_resource):
		build_bonus[bonus.produced_resource].erase(bonus)

	_calculate_current_bonus(bonus.produced_resource)

func _calculate_current_bonus(town_resource: Enums.TownResource) -> void:
	var total_bonus = 0
	for bonus in build_bonus[town_resource]:
		total_bonus += bonus.bonus_amount
	current_bonus[town_resource] = total_bonus

func finish_building() -> void:
	if in_progress_building:
		building_finished.emit(self)
	else:
		print("No building in progress to finish at field: ", grid_position)

func _on_next_turn() -> void:
	if building:
		building.produce_resource()
