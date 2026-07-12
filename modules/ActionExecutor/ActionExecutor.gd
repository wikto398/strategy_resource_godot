class_name ActionExecutor extends ActionExecutorInterface

@export var build_handler: BuildHandler
@export var field_grid: TerrainFieldGrid
@export var builder_controller: BuilderController

func execute_action(action: Array) -> void:
    _parse_action(action)

func _parse_action(action: Array):
    DebugLogger.debug("Received action: " + str(action))
    if action.size() == 0:
        DebugLogger.error("Empty action array.")
        return
    var action_type: int = action.get(0)
    match action_type:
        0:
            _next_turn()
        1:
            _move_builder(action)
        2:
            _build_structure(action)
        _:
            DebugLogger.error("Unknown action type: %d" % action_type)

func _build_structure(action: Array):
    var building_type: int = action.get(2)
    var position_flat: int = action.get(3)
    if building_type == null or position_flat == null:
        DebugLogger.error("Invalid build action: missing building_type or position.")
        return
    var position: Vector2i = _flat_to_2d_index(position_flat, field_grid.columns)
    building_type = building_type
    DebugLogger.debug("Executing build action: building_type=%d, position=%s" % [building_type, position])
    DebugLogger.debug("Buildings dictionary: " + str(ResourceDatabase.int_to_building))
    var building: Building = ResourceDatabase.int_to_building.get(building_type)
    if building == null:
        DebugLogger.error("Invalid build action: unknown structure_type %d." % building_type)
        return
    var field = field_grid.get_field_at(position)
    if field == null:
        DebugLogger.error("Invalid build action: unknown position %s." % position)
        return
    build_handler.build_on_field(field, building)

func _move_builder(action: Array):
    var builder_id: int = action.get(1)
    var position_flat: int = action.get(3)
    if builder_id == null or position_flat == null:
        DebugLogger.error("Invalid move action: missing builder_id or position.")
        return
    var position: Vector2i = _flat_to_2d_index(position_flat, field_grid.columns)
    var builder = builder_controller.get_builder_by_id(builder_id)
    if builder == null:
        DebugLogger.error("Invalid move action: unknown builder_id %d." % builder_id)
        return
    var field = field_grid.get_field_at(position)
    if field == null:
        DebugLogger.error("Invalid move action: unknown position %s." % position)
        return
    builder_controller.move_builder_towards(builder, position)

func _next_turn():
    DebugLogger.debug("Executing next turn action.")
    Turn.go_to_next_turn()

func _flat_to_2d_index(flat_index: int, width: int) -> Vector2i:
    var x = flat_index % width
    var y = flat_index / width
    DebugLogger.info(
        "flat=%d -> coord=%s actual=%s"
        % [
            flat_index,
            Vector2i(x,y),
            field_grid.get_field_at(Vector2i(x, y)).grid_position if field_grid.get_field_at(Vector2i(x, y)) != null else "null",
        ]
    )
    return Vector2i(x, y)
