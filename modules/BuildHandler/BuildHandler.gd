class_name BuildHandler extends Node

@export var field_grid: FieldGrid
@export var production_handler: ProductionHandler
@export var current_building: Building:
	set(value):
		current_building = value
		clear_highlights()
		if current_building:
			highlight_buildable_fields()

func _ready() -> void:
	if not field_grid:
		push_error("BuildHandler requires a reference to FieldGrid.")
	if not production_handler:
		push_error("BuildHandler requires a reference to ProductionHandler.")
	
	field_grid.field_clicked.connect(build_on_field)

func highlight_buildable_fields() -> void:
	if not field_grid or not current_building:
		return
	print("Highlighting buildable fields for building: ", current_building.name)
	for field in field_grid.fields.values():
		if _can_build_on_field(field):
			field.set_buildable(true)
		else:
			field.set_buildable(false)

func clear_highlights() -> void:
	if field_grid:
		field_grid.unhighlight_all_fields.emit()

func _can_build_on_field(field: Field) -> bool:
	if not field.walkable:
		return false
	if field.building:
		return false
	if field.terrain_type != current_building.required_terrain:
		return false
	var neighbors = field_grid.get_neighbors(field.grid_position)
	var required_terrain = current_building.required_nearby_terrain.duplicate()
	for neighbor in neighbors:
		if neighbor.terrain_type in required_terrain:
			required_terrain.erase(neighbor.terrain_type)
	return required_terrain.size() == 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			highlight_buildable_fields()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			clear_highlights()

func build_on_field(field: Field) -> void:
	if _can_build_on_field(field):
		if not production_handler.can_afford(current_building.build_cost):
			print("Cannot afford to build ", current_building.name)
			return
		field.building = current_building
		current_building = null
		clear_highlights()
		production_handler.start_production(field.building)
	else:
		print("Cannot build ", current_building.name, " on field at ", field.grid_position)
