class_name ActionHandler extends Node

@export var build_handler: BuildHandler
@export var production_handler: ProductionHandler
@export var field_grid: FieldGrid
@export var building_selector: BuildingSelector
@export var builder_controller: BuilderController

var selected

func setup(_build_handler: BuildHandler, _production_handler: ProductionHandler, _field_grid: FieldGrid, _building_selector: BuildingSelector, _builder_controller: BuilderController) -> void:
	build_handler = _build_handler
	production_handler = _production_handler
	field_grid = _field_grid
	building_selector = _building_selector
	builder_controller = _builder_controller

	field_grid.field_clicked.connect(_field_selected)
	building_selector.building_selected.connect(_building_selected)
	builder_controller.builder_selected.connect(_builder_selected)

func _field_selected(field: Field) -> void:
	if selected is Building:
		build_handler.build_on_field(field, selected)
	elif selected is Builder:
		builder_controller.move_builder_towards(selected, field.grid_position)
	else:
		DebugLogger.trace("Showing field info for field at " + str(field.grid_position))
		return

	selected = null
	builder_controller.enable_input_on_builders()

func _building_selected(building: Building) -> void:
	DebugLogger.debug("ActionHandler: Building selected: " + building.name)
	if not production_handler.can_afford(building.build_cost):
		DebugLogger.warning("Cannot afford to build " + building.name)
		return
	selected = building
	build_handler.highlight_buildable_fields(selected)
	builder_controller.disable_input_on_builders()

func _builder_selected(builder: Builder) -> void:
	DebugLogger.debug("ActionHandler: Builder selected: " + builder.name)
	selected = builder
	build_handler.clear_highlights()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			DebugLogger.trace("Right click detected, clearing highlights and selection.")
			build_handler.clear_highlights()
			selected = null
