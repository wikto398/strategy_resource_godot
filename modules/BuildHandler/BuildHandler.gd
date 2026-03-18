class_name BuildHandler extends Node

@export var field_grid: FieldGrid
@export var production_handler: ProductionHandler

func _ready() -> void:
	if not field_grid:
		DebugLogger.error("BuildHandler requires a reference to FieldGrid.")
	if not production_handler:
		DebugLogger.error("BuildHandler requires a reference to ProductionHandler.")

func highlight_buildable_fields(building: Building) -> void:
	if not field_grid or not building:
		return
	DebugLogger.trace("Highlighting buildable fields for building: " + building.name)
	for field in field_grid.fields.values():
		if can_build_on_field(field, building):
			field.set_buildable(true)
		else:
			field.set_buildable(false)

func clear_highlights() -> void:
	if field_grid:
		field_grid.unhighlight_all_fields.emit()

func can_build_on_field(field: Field, building: Building) -> bool:
	if field.building or field.in_progress_building:
		return false
	var data = {"field": field}
	return building.validate_conditions(data)

func build_on_field(field: Field, building: Building) -> void:
	if can_build_on_field(field, building):
		clear_highlights()
		if not building.unique:
			building = building.duplicate() as Building
		else:
			building.remove_unique_building_from_selector()
		production_handler.start_production(building, field)
	else:
		DebugLogger.info("Cannot build " + building.name + " on field at " + str(field.grid_position))
