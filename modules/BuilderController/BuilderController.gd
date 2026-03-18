class_name BuilderController extends Node

signal builder_selected(builder: Builder)

var field_grid: FieldGrid = null

var builders: Array[Builder] = []
var nearest_distances: Dictionary[Vector2i, int] = {}
var nearest_builders: Dictionary[Vector2i, int] = {}

func add_builder(builder: Builder) -> void:
	builders.append(builder)
	builder.unit_clicked.connect(_on_builder_clicked)

func print_nearest_builders() -> void:
	for pos in nearest_builders.keys():
		DebugLogger.trace("Position: " + str(pos) + " - Nearest Builder Index: " + str(nearest_builders[pos]) + " - Distance: " + str(nearest_distances[pos]))

func multisource_dijkstra() -> void:
	if field_grid == null:
		DebugLogger.error("Field grid is not assigned in BuilderController.")
		return

	nearest_distances.clear()
	nearest_builders.clear()

	var queue: PriorityQueue = PriorityQueue.new()

	for index in range(len(builders)):
		var pos = builders[index].field.grid_position
		queue.push({"position": pos, "distance": 0, "builder": index}, 0)

	while not queue.is_empty():
		var current = queue.pop()
		var current_pos: Vector2i = current["position"]
		var current_distance: int = current["distance"]
		var current_builder_index: int = current["builder"]

		if not nearest_distances.has(current_pos) or current_distance < nearest_distances[current_pos]:
			nearest_distances[current_pos] = current_distance
			nearest_builders[current_pos] = current_builder_index

		for neighbor in field_grid.get_neighbors(current_pos):
			if not neighbor.walkable:
				continue
			var neighbor_pos = neighbor.grid_position
			var new_distance = current_distance + neighbor.movement_cost

			if not nearest_distances.has(neighbor_pos) or new_distance < nearest_distances[neighbor_pos]:
				queue.push({"position": neighbor_pos, "distance": new_distance, "builder": current_builder_index}, new_distance)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_B:
				DebugLogger.trace("Calculating nearest builders...")
				multisource_dijkstra()
				print_nearest_builders()

func move_builder_towards(builder: Builder, target_pos: Vector2i) -> void:
	if builder == null:
		DebugLogger.error("Builder is null in move_builder_towards.")
		return
	if target_pos == null:
		DebugLogger.error("Target position is null in move_builder_towards.")
		return
	if field_grid == null:
		DebugLogger.error("Field grid is not assigned in BuilderController.")
		return

	var target_field = field_grid.get_field_at(target_pos)
	if target_field == null:
		DebugLogger.error("Target field is null for position: " + str(target_pos))
		return
	builder.target_position = target_field
	if builder.state_machine.current_state_name != "moving":
		builder.state_machine.change_state("moving")
	else:
		builder.state_machine.current_state.a_star(builder.field, target_field)

func _on_builder_clicked(builder: Builder) -> void:
	builder_selected.emit(builder)

func disable_input_on_builders() -> void:
	DebugLogger.trace("Disabling input on builders...")
	for builder in builders:
		builder.process_mode = Node.PROCESS_MODE_DISABLED

func enable_input_on_builders() -> void:
	DebugLogger.trace("Enabling input on builders...")
	for builder in builders:
		builder.process_mode = Node.PROCESS_MODE_INHERIT
