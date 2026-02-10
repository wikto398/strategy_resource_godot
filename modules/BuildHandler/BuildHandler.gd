class_name BuildHandler extends Node

@export var field_grid: FieldGrid
@export var production_handler: ProductionHandler

func _ready() -> void:
	if not field_grid:
		push_error("BuildHandler requires a reference to FieldGrid.")
	if not production_handler:
		push_error("BuildHandler requires a reference to ProductionHandler.")

func highlight_buildable_fields(building: Building) -> void:
	if not field_grid or not building:
		return
	print("Highlighting buildable fields for building: ", building.name)
	for field in field_grid.fields.values():
		if _can_build_on_field(field, building):
			field.set_buildable(true)
		else:
			field.set_buildable(false)

func clear_highlights() -> void:
	if field_grid:
		field_grid.unhighlight_all_fields.emit()

func _can_build_on_field(field: Field, building: Building) -> bool:
	if not field.walkable:
		return false
	if field.building:
		return false
	if building.required_terrain != Terrain.TerrainType.ALL and field.terrain_type != building.required_terrain:
		return false
	var neighbors = field_grid.get_neighbors(field.grid_position)
	var required_terrain = building.required_nearby_terrain.duplicate(true)
	for neighbor in neighbors:
		if neighbor.terrain_type in required_terrain:
			required_terrain.erase(neighbor.terrain_type)
	return required_terrain.size() == 0

func build_on_field(field: Field, building: Building) -> void:
	if _can_build_on_field(field, building):
		if not production_handler.can_afford(building.build_cost):
			print("Cannot afford to build ", building.name)
			return
		clear_highlights()
		production_handler.start_production(building, field)
	else:
		print("Cannot build ", building.name, " on field at ", field.grid_position)
