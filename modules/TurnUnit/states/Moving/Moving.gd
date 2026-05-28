class_name Moving extends State

var current_path: Array[Field] = []
@export var condition: Condition

func enter(_user: Node) -> void:
	current_path = Pathing.a_star(_user.field, _user.target_position, TerrainFieldGrid.instance, self.heuristic, self.condition, _user)

func exit(_user: Node) -> void:
	_user.target_position = null

func update(_delta: float, _user: Node) -> void:
	if not current_path:
		current_path = Pathing.a_star(_user.field, _user.target_position, TerrainFieldGrid.instance, self.heuristic, self.condition, _user)

	for dummy in range(1 + GameData.builder_speed_multiplier):
		if current_path.size() <= 1:
			return

		var next_field: Field = current_path[1]

		if next_field.unit:
			DebugLogger.debug("{builder}: Path blocked at {position} by {blocker}, checking for new path."
				.format({
					builder = _user.name,
					position = next_field.grid_position,
					blocker = next_field.unit.name
				}))

			var previous_path = current_path.duplicate()
			current_path = Pathing.a_star(_user.field, _user.target_position, TerrainFieldGrid.instance, self.heuristic, self.condition, _user)
			if not current_path:
				DebugLogger.debug("{builder}: No alternative path found, waiting for field to become available."
					.format({builder = _user.name}))
				current_path = previous_path
				next_field = current_path[1]

				DebugLogger.debug("{builder}: Waiting for field to become available.".format({builder = _user.name}))
				await next_field.unit_moved_out

		_move_to(_user, next_field)

func heuristic(a: Field, b: Field) -> int:
	return abs(a.grid_position.x - b.grid_position.x) + abs(a.grid_position.y - b.grid_position.y)

func reconstruct_path(came_from: Dictionary[Field, Field], current: Field) -> Array[Field]:
	var total_path: Array[Field] = [current]
	while came_from.has(current):
		current = came_from[current]
		total_path.insert(0, current)
	return total_path

func _move_to(_user: Node, next_field: Field) -> void:
	_user.field = next_field
	current_path.pop_front()
	if _user.target_position == _user.field:
		_user.target_position = null
		DebugLogger.debug("Unit has reached target position at {position}".format({position = _user.field.grid_position}))
		if _user.field.in_progress_building:
			DebugLogger.debug("{unit} stopped moving and is now working on building at {field}.".format({unit = _user.name, field = _user.field.grid_position}))
			change_state.emit("building")
		else:
			DebugLogger.debug("{unit} stopped moving and is now idle.".format({unit = _user.name}))
			change_state.emit("idle")
