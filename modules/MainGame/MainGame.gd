class_name MainGame extends Node2D

var BUILDER_SCENE = preload("uid://vgsn6mcridso")

@onready var field_grid: FieldGrid = $FieldGrid
@onready var build_handler: BuildHandler = $BuildHandler
@onready var builder_controller: BuilderController = $BuilderController
@onready var production_handler: ProductionHandler = $ProductionHandler
@onready var action_handler: ActionHandler = $ActionHandler
@onready var production_ui: ProductionUI = $UI/ProductionUI
@onready var building_selector: BuildingSelector = $UI/BuildingSelector
@onready var camera: Camera2D = $Camera2D
@onready var units_node: Node2D = $Units

func _ready() -> void:
	camera.global_position = get_viewport().size * 0.5
	_connect_ui_signals()
	_setup_builder_controller()
	_setup_action_handler()
	_setup_production_handler()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed: 
		match event.keycode:
			KEY_F1:
				print("Reloading scene...")
				_reload()
			KEY_F5:
				print("Saving game...")
			KEY_F9:
				print("Loading game...")

func _reload():
	get_tree().reload_current_scene()

func _connect_ui_signals() -> void:
	production_handler.resources_updated.connect(production_ui._on_update_resources)
	production_handler.production_updated.connect(production_ui._on_update_production)

func _setup_builder_controller() -> void:
	builder_controller.field_grid = field_grid
	for i in range(3):
		var builder = BUILDER_SCENE.instantiate() as Builder
		builder.field = field_grid.get_field_at(Vector2i(i * 2, i))
		units_node.add_child(builder)
		print("Added builder at position: ", builder.field.grid_position, " with global position: ", builder.global_position)
		builder_controller.add_builder(builder)

func _setup_action_handler() -> void:
	action_handler.setup(build_handler, production_handler, field_grid, building_selector, builder_controller)

func _setup_production_handler() -> void:
	production_handler.setup()
