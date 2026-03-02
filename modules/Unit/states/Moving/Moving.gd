class_name Moving extends State

var current_path: Array[Field] = []

func enter(_user: Node) -> void:
	a_star(_user.field, _user.target_position)

func exit(_user: Node) -> void:
	_user.target_position = null

func update(_delta: float, _user: Node) -> void:
	if not current_path:
		a_star(_user.field, _user.target_position)

	for dummy in range(1 + GameData.builder_speed_multiplier):
		if current_path.size() <= 1:
			return

		var next_field: Field = current_path[1]

		if next_field.unit:
			print("{builder}: Path blocked at {position} by {blocker}, checking for new path."
				.format({
					builder = _user.name,
					position = next_field.grid_position,
					blocker = next_field.unit.name
				}))

			var previous_path = current_path.duplicate()
			a_star(_user.field, _user.target_position, true)
			if not current_path:
				print("{builder}: No alternative path found, waiting for field to become available."
					.format({builder = _user.name}))
				current_path = previous_path
				next_field = current_path[1]

				print(_user.name, ": Waiting for field to become available.")
				await next_field.unit_moved_out

		_move_to(_user, next_field)

func a_star(start: Field, goal: Field, skip_blocked_by_unit: bool = false) -> void:
	var open_set: PriorityQueue = PriorityQueue.new()
	var came_from: Dictionary[Field, Field] = {}
	var g_score: Dictionary[Field, int] = {}
	var f_score: Dictionary[Field, int] = {}

	g_score[start] = 0
	f_score[start] = heuristic(start, goal)
	open_set.push(start, f_score[start])

	var field_grid: FieldGrid = FieldGrid.instance

	while not open_set.is_empty():
		var current: Field = open_set.pop()
		if current == goal:
			current_path = reconstruct_path(came_from, current)
			return

		for neighbor in field_grid.get_neighbours(current.grid_position):
			if not neighbor.walkable or (neighbor.unit and (not skip_blocked_by_unit or neighbor.unit != self)):
				continue
			var tentative_g_score = g_score[current] + neighbor.movement_cost
			if not g_score.has(neighbor) or tentative_g_score < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g_score
				f_score[neighbor] = tentative_g_score + heuristic(neighbor, goal)
				open_set.push(neighbor, f_score[neighbor])

	print("No path found from ", start.grid_position, " to ", goal.grid_position)
	current_path = []

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
		print("Unit has reached target position at ", _user.field.grid_position)
		if _user.field.in_progress_building:
			print("{unit} stopped moving and is now working on building at {field}.".format({unit = _user.name, field = _user.field.grid_position}))
			change_state.emit("building")
		else:
			print("{unit} stopped moving and is now idle.".format({unit = _user.name}))
			change_state.emit("idle")
