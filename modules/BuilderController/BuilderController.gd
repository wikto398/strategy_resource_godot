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
		print("Position: ", pos, " - Nearest Builder Index: ", nearest_builders[pos], " - Distance: ", nearest_distances[pos])

func multisource_dijkstra() -> void:
	if field_grid == null:
		push_error("Field grid is not assigned in BuilderController.")
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
				print("Calculating nearest builders...")
				multisource_dijkstra()
				print_nearest_builders()

func move_builder_towards(builder: Builder, target_pos: Vector2i) -> void:
	if builder == null:
		push_error("Builder is null in move_builder_towards.")
		return
	if target_pos == null:
		push_error("Target position is null in move_builder_towards.")
		return
	if field_grid == null:
		push_error("Field grid is not assigned in BuilderController.")
		return
	var shortest_path = a_star(builder.field.grid_position, target_pos)
	if shortest_path.size() == 0:
		print("No path found from ", builder.field.grid_position, " to ", target_pos)
		return
	var index = 1
	var next_field: Field = null
	while builder.field.grid_position != target_pos:
		next_field = field_grid.get_field_at(shortest_path[index])
		if next_field.unit:
			print("Path blocked at ", next_field.grid_position, ", recalculating path.")
			shortest_path = a_star(builder.field.grid_position, target_pos)
			index = 1
			next_field = field_grid.get_field_at(shortest_path[index])
			if next_field.unit:
				print("No other path found from ", builder.field.grid_position, " to ", target_pos, " after recalculation. Waiting for field to become available.")
				await next_field.unit_moved_out
				continue

		builder.field = next_field
		index += 1
		await Turn.next_turn

func _on_builder_clicked(builder: Builder) -> void:
	builder_selected.emit(builder)

func a_star(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var open_set: PriorityQueue = PriorityQueue.new()
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var g_score: Dictionary[Vector2i, int] = {}
	var f_score: Dictionary[Vector2i, int] = {}

	g_score[start] = 0
	f_score[start] = heuristic(start, goal)
	open_set.push(start, f_score[start])

	while not open_set.is_empty():
		var current: Vector2i = open_set.pop()
		if current == goal:
			return reconstruct_path(came_from, current)

		for neighbor in field_grid.get_neighbors(current):
			if not neighbor.walkable:
				continue
			var tentative_g_score = g_score[current] + neighbor.movement_cost
			if not g_score.has(neighbor.grid_position) or tentative_g_score < g_score[neighbor.grid_position]:
				came_from[neighbor.grid_position] = current
				g_score[neighbor.grid_position] = tentative_g_score
				f_score[neighbor.grid_position] = tentative_g_score + heuristic(neighbor.grid_position, goal)
				open_set.push(neighbor.grid_position, f_score[neighbor.grid_position])

	return []

func heuristic(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func reconstruct_path(came_from: Dictionary[Vector2i, Vector2i], current: Vector2i) -> Array[Vector2i]:
	var total_path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		total_path.insert(0, current)
	return total_path
