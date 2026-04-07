class_name ActionExecutor extends ActionExecutorInterface

@export var build_handler: BuildHandler
@export var field_grid: FieldGrid

func execute_action(action: Array) -> void:
    _parse_action(action)

func _parse_action(action: Array):
    DebugLogger.debug("Received action: " + str(action))
    if action.size() == 0:
        DebugLogger.error("Empty action array.")
        return
    var action_type: int = action.get(0)
    if action_type == 0:
        _next_turn()
    else:
        _build_structure(action)

func _build_structure(action: Array):
    var building_type: int = action.get(0)
    var position_flat: int = action.get(1)
    if building_type == null or position_flat == null:
        DebugLogger.error("Invalid build action: missing building_type or position.")
        return
    var position: Vector2i = _flat_to_2d_index(position_flat, field_grid.columns)
    building_type = building_type
    var building: Building = ResourceDatabase.int_to_building.get(building_type)
    if building == null:
        DebugLogger.error("Invalid build action: unknown structure_type %d." % building_type)
        return
    var field = field_grid.get_field_at(position)
    if field == null:
        DebugLogger.error("Invalid build action: unknown position %s." % position)
        return
    build_handler.build_on_field(field, building)

func _next_turn():
    DebugLogger.debug("Executing next turn action.")
    Turn.next_turn.emit()

func _flat_to_2d_index(flat_index: int, width: int) -> Vector2i:
    var x = flat_index % width
    var y = flat_index / width
    return Vector2i(x, y)
