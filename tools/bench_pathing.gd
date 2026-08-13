extends Node

var _main: Node
var _frames := 0

func _ready() -> void:
	Global.map_seed = 42
	Global.map_seed_valid = true
	_main = load("res://modules/MainGame/MainGame.tscn").instantiate()
	add_child(_main)
	var main_game := _main as MainGame
	var grid := _main.get_node("TerrainFieldGrid") as TerrainFieldGrid
	var build_handler := _main.get_node("BuildHandler") as BuildHandler
	for field in grid.ordered_fields:
		if build_handler.can_build_on_field(field, main_game.city_center):
			build_handler.build_on_field(field, main_game.city_center)
			break

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 15:
		_run_bench()
		get_tree().quit(0)

func _legacy_movable(builder_controller: BuilderController, grid: TerrainFieldGrid) -> Array:
	var movable_cells = []
	for builder in builder_controller.builders:
		var builder_cells = []
		var reachable_fields = builder.reachable_fields()
		for field in grid.ordered_fields:
			builder_cells.append(1 if reachable_fields.has(field) else 0)
		movable_cells.append(builder_cells)
	while movable_cells.size() < GameData.MAX_BUILDERS:
		var empty_cells = []
		for field in grid.ordered_fields:
			empty_cells.append(0)
		movable_cells.append(empty_cells)
	return movable_cells

func _run_bench() -> void:
	var collector = _main.get_node("EnvironmentConnector/ObservationCollector")
	var grid = _main.get_node("TerrainFieldGrid") as TerrainFieldGrid
	var builder_controller = _main.get_node("BuilderController") as BuilderController
	var build_handler = _main.get_node("BuildHandler") as BuildHandler
	var n_builders: int = builder_controller.builders.size()
	print("bench: builders=%d" % n_builders)

	var N := 300

	for i in 20:
		collector._movable_cells()
	var t0 := Time.get_ticks_usec()
	for i in N:
		collector._movable_cells()
	print("new movable (cached) avg: %.3f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / N))

	for i in 20:
		collector._start_cache.clear()
		collector._movable_cells()
	t0 = Time.get_ticks_usec()
	for i in N:
		collector._start_cache.clear()
		collector._movable_cells()
	print("new movable (cold) avg: %.3f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / N))

	for i in 20:
		_legacy_movable(builder_controller, grid)
	t0 = Time.get_ticks_usec()
	for i in N:
		_legacy_movable(builder_controller, grid)
	print("legacy movable avg: %.3f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / N))

	for i in 20:
		collector._action_mask()
	t0 = Time.get_ticks_usec()
	for i in N:
		collector._action_mask()
	print("action_mask avg: %.3f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / N))

	for i in 20:
		collector._field_masks()
	t0 = Time.get_ticks_usec()
	for i in N:
		collector._field_masks()
	print("field_masks avg: %.3f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / N))

	var walk: bool = GameData.builders_walk_on_water
	var table: Array[PackedInt32Array] = FlatPathing.build_neighbor_table(grid, walk)
	_equivalence(builder_controller, grid, table, walk)

	GameData.builders_walk_on_water = true
	var table_water: Array[PackedInt32Array] = FlatPathing.build_neighbor_table(grid, true)
	_equivalence(builder_controller, grid, table_water, true)
	GameData.builders_walk_on_water = walk

	_run_field_masks_checks(collector, grid, build_handler)

	_dump_packets(collector)

func _dump_packets(collector) -> void:
	var flat: PackedByteArray = collector.get_observation_bytes()
	var msgpack_bytes: PackedByteArray = Messagepack.encode(collector.get_observation())["value"]
	var flat_file := FileAccess.open("/tmp/opencode/flat.bin", FileAccess.WRITE)
	flat_file.store_buffer(flat)
	flat_file.close()
	var msg_file := FileAccess.open("/tmp/opencode/msgpack.bin", FileAccess.WRITE)
	msg_file.store_buffer(msgpack_bytes)
	msg_file.close()
	print("flat bytes=%d msgpack bytes=%d" % [flat.size(), msgpack_bytes.size()])

func _reference_field_masks(collector, grid: TerrainFieldGrid, build_handler: BuildHandler) -> Array:
	var result = []
	for building in ResourceDatabase.buildings:
		var row = []
		if not collector.can_build(building):
			for f in grid.ordered_fields:
				row.append(0)
		else:
			for f in grid.ordered_fields:
				row.append(1 if build_handler.can_build_on_field(f, building) else 0)
		result.append(row)
	return result

func _compare_field_masks(label: String, collector, grid: TerrainFieldGrid, build_handler: BuildHandler) -> void:
	var cached: Array = collector._field_masks()
	var reference: Array = _reference_field_masks(collector, grid, build_handler)
	var mismatches := 0
	var checked := 0
	for i in ResourceDatabase.buildings.size():
		for j in grid.ordered_fields.size():
			checked += 1
			if cached[i][j] != reference[i][j]:
				mismatches += 1
	print("field_masks eq[%s]: cells=%d mismatches=%d" % [label, checked, mismatches])

func _run_field_masks_checks(collector, grid: TerrainFieldGrid, build_handler: BuildHandler) -> void:
	var N := 300

	for i in 20:
		collector._field_masks()
	var t0 := Time.get_ticks_usec()
	for i in N:
		collector._field_masks()
	print("field_masks (cached) avg: %.3f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / N))

	_compare_field_masks("init", collector, grid, build_handler)

	var housing: Building = ResourceDatabase.buildings[1]
	var build_field: TerrainField = null
	for f in grid.ordered_fields:
		if build_handler.can_build_on_field(f, housing):
			build_field = f
			break
	if build_field != null:
		build_handler.build_on_field(build_field, housing)
	_compare_field_masks("build_start", collector, grid, build_handler)

	var prod_handler = collector.production_handler
	var saved_resources: Dictionary = prod_handler.town_resources.duplicate()
	for key in prod_handler.town_resources.keys():
		prod_handler.town_resources[key] = 0
	_compare_field_masks("gates_off", collector, grid, build_handler)
	for key in prod_handler.town_resources.keys():
		prod_handler.town_resources[key] = saved_resources[key]
	_compare_field_masks("gates_on", collector, grid, build_handler)

	var complete_field: TerrainField = null
	for f in grid.ordered_fields:
		if f != build_field and not f.building and not f.in_progress_building:
			complete_field = f
			break
	if complete_field != null:
		var b: Building = housing.duplicate()
		complete_field.building = b
		collector._on_building_completed(b, complete_field)
	_compare_field_masks("build_complete", collector, grid, build_handler)

	for i in 20:
		collector._field_masks_cache = []
		collector._buildable_cache = []
		collector._gate_cache = []
		collector._field_masks_initialized = false
		collector._pending_patches.clear()
		collector._field_masks()
	t0 = Time.get_ticks_usec()
	for i in N:
		collector._field_masks_cache = []
		collector._buildable_cache = []
		collector._gate_cache = []
		collector._field_masks_initialized = false
		collector._pending_patches.clear()
		collector._field_masks()
	print("field_masks (cold) avg: %.3f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / N))

func _equivalence(builder_controller: BuilderController, grid: TerrainFieldGrid, table: Array[PackedInt32Array], walk: bool) -> void:
	var mismatches := 0
	var checked := 0
	var total_old := 0
	var total_new := 0
	var n_cells: int = grid.ordered_fields.size()
	for builder in builder_controller.builders:
		if builder.field == null:
			continue
		var old_reach: Array = builder.reachable_fields()
		var old_mask := PackedByteArray()
		old_mask.resize(n_cells)
		for f in old_reach:
			old_mask[int(f.grid_position.x + grid.columns * f.grid_position.y)] = 1
		var flat: int = int(builder.field.grid_position.x + grid.columns * builder.field.grid_position.y)
		var new_mask: PackedByteArray = FlatPathing.bfs_mask(flat, table)
		checked += 1
		for i in range(n_cells):
			total_old += int(old_mask[i])
			total_new += int(new_mask[i])
			if old_mask[i] != new_mask[i]:
				mismatches += 1
	print("equivalence(walk=%s): builders=%d old_cells=%d new_cells=%d mismatches=%d" % [walk, checked, total_old, total_new, mismatches])
