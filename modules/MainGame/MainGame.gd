class_name MainGame extends Node2D

var BUILDER_SCENE = preload("uid://vgsn6mcridso")

@export var city_center: CityCenter

@onready var field_grid: FieldGrid = $FieldGrid
@onready var build_handler: BuildHandler = $BuildHandler
@onready var builder_controller: BuilderController = $BuilderController
@onready var production_handler: ProductionHandler = $ProductionHandler
@onready var action_handler: ActionHandler = $ActionHandler
@onready var production_ui: ProductionUI = $UI/ProductionUI
@onready var building_selector: BuildingSelector = $UI/BuildingSelector
@onready var camera: Camera2D = $Camera2D
@onready var units_node: Node2D = $Units
@onready var ui: CanvasLayer = $UI

func _ready() -> void:
	camera.global_position = get_viewport().size * 0.5
	_connect_ui_signals()
	_setup_action_handler()
	_setup_production_handler()
	_connect_game_result_signals()
	_select_city_center_location()
	_disable_ui_if_headless()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				DebugLogger.info("Reloading scene...")
				_reload()
			KEY_F5:
				DebugLogger.info("Saving game...")
			KEY_F9:
				DebugLogger.info("Loading game...")

func _reload():
	get_tree().reload_current_scene()

func _connect_ui_signals() -> void:
	production_handler.resources_updated.connect(production_ui._on_update_resources)
	production_handler.production_updated.connect(production_ui._on_update_production)

func _setup_builder_controller(field: Field) -> void:
	builder_controller.field_grid = field_grid
	var neareast_walkable_fields = field_grid.get_nearest_walkable_fields(field.grid_position, 3)
	for i in range(3):
		var builder = BUILDER_SCENE.instantiate() as Builder
		builder.field = neareast_walkable_fields[i]
		units_node.add_child(builder)
		DebugLogger.trace("Added builder at position: " + str(builder.field.grid_position) + " with global position: " + str(builder.global_position))
		builder_controller.add_builder(builder)

func _setup_action_handler() -> void:
	action_handler.setup(build_handler, production_handler, field_grid, building_selector, builder_controller)

func _setup_production_handler() -> void:
	production_handler.setup()

func _connect_game_result_signals() -> void:
	Global.game_won.connect(_on_game_won)
	Global.game_lost.connect(_on_game_lost)

func _on_game_won() -> void:
	DebugLogger.info("Congratulations! You've won the game!")

func _on_game_lost() -> void:
	DebugLogger.info("Game Over! You've lost the game.")

func _select_city_center_location() -> void:
	action_handler._building_selected(city_center)
	var field = await city_center.city_center_built
	DebugLogger.info("City Center has been built! You can now build additional structures and expand your town.")
	_setup_builder_controller(field)

func _disable_ui_if_headless() -> void:
	if DisplayServer.get_name() == "headless":
		DebugLogger.info("Running in headless mode, disabling UI.")
		ui.visible = false
		ui.process_mode = Node.PROCESS_MODE_DISABLED
