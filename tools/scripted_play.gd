extends Node

const MAX_STEPS: int = 20000

var _main: Node
var _frames := 0
var _started := false

func _ready() -> void:
	Global.map_seed = int(ArgsParser.kwargs.get("script_seed", "42"))
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
	if not _started and _frames >= 2:
		_started = true
		_run()

func _run() -> void:
	var action_executor := _main.get_node("EnvironmentConnector/ActionExecutor")
	var collector := _main.get_node("EnvironmentConnector/ObservationCollector")
	var grid := _main.get_node("TerrainFieldGrid") as TerrainFieldGrid
	var build_handler := _main.get_node("BuildHandler") as BuildHandler
	var prod := _main.get_node("ProductionHandler") as ProductionHandler
	var bctrl := _main.get_node("BuilderController") as BuilderController

	var policy: String = ArgsParser.kwargs.get("script_policy", "balanced").to_lower()
	var step := 0
	var done := false
	while not done and step < MAX_STEPS:
		step += 1
		var action: Array = _decide_action(policy, grid, build_handler, prod, bctrl, collector)
		action_executor.execute_action(action)
		collector._reward()
		done = collector._done()
		await get_tree().process_frame
	_report(policy, prod, bctrl, collector)
	get_tree().quit(0)

func _decide_action(policy: String, grid: TerrainFieldGrid, build_handler: BuildHandler, prod: ProductionHandler, bctrl: BuilderController, collector) -> Array:
	var building: Building = _choose_building(policy, prod, collector, grid)
	if building == null:
		return [0]
	var cell: TerrainField = _find_cell_for(building, grid, build_handler, collector, bctrl)
	if cell == null:
		DebugLogger.info("SCRIPTED: no buildable cell for %s" % building.name)
		return [0]
	# A builder is already en route to this cell (for a not-yet-started build) —
	# wait for it to arrive rather than assigning a second builder.
	if _has_mover_to(cell, bctrl):
		return [0]
	var builder = _nearest_idle_builder(cell, bctrl)
	if builder == null:
		return [0]
	var builder_id: int = bctrl.builders.find(builder)
	var building_type: int = ResourceDatabase.building_to_int.get(building, 0)
	var flat: int = int(cell.grid_position.x + grid.columns * cell.grid_position.y)
	if builder.field == cell:
		return [2, 0, building_type, flat]
	return [1, builder_id, 0, flat]

func _choose_building(policy: String, prod: ProductionHandler, collector, grid: TerrainFieldGrid) -> Building:
	match policy:
		"spam":
			return _choose_building_spam(prod, collector, grid)
		_:
			return _choose_building_balanced(prod, collector, grid)

func _choose_building_balanced(prod: ProductionHandler, collector, grid: TerrainFieldGrid) -> Building:
	var workshop := _building_by_name("Workshop")
	if _can_start(workshop, collector, grid, true) and prod.can_afford(workshop.build_cost):
		return workshop
	# Population buffer: construction requires population > working_population,
	# and a producer completing mid-build can push working to population and stall
	# the build. Keep at least two free workers while producers are still missing,
	# but cap population (incl. Housing already in progress) so upkeep doesn't
	# cancel production — one producer per resource only needs pop ~= working + 2.
	if GameData.population + _count_in_progress(grid, "Housing") < 6 and GameData.working_population >= GameData.population - 2:
		var housing := _building_by_name("Housing")
		if housing != null and _can_start(housing, collector, grid, true) and prod.can_afford(housing.build_cost):
			return housing
	var producers: Dictionary = {
		Enums.TownResource.WOOD: "Sawmill",
		Enums.TownResource.STONE: "Mine",
		Enums.TownResource.FOOD: "Farm",
		Enums.TownResource.GOLD: "Stone Works",
	}
	var counts: Dictionary = _building_counts(collector, grid)
	# One producer per resource; Farm (food) first, then lowest-stock resource.
	for res in _producer_order(prod, producers, counts):
		var b: Building = _producer_for(res, producers, collector, grid)
		if _can_start(b, collector, grid) and prod.can_afford(b.build_cost):
			return b
	return null

func _choose_building_spam(prod: ProductionHandler, collector, grid: TerrainFieldGrid) -> Building:
	var mine := _building_by_name("Mine")
	if mine != null and prod.can_afford(mine.build_cost) and not mine.already_built:
		return mine
	return null

func _can_start(building: Building, collector, grid: TerrainFieldGrid, allow_full: bool = false) -> bool:
	if building == null:
		return false
	if not collector.can_build(building):
		return false
	var used: int = GameData.working_population + _in_progress_count(grid)
	if allow_full:
		if used > GameData.population:
			return false
	else:
		if used >= GameData.population:
			return false
	if _in_progress_count(grid) >= GameData.current_builders:
		return false
	return true

func _in_progress_count(grid: TerrainFieldGrid) -> int:
	var count := 0
	for field in grid.ordered_fields:
		if field.in_progress_building != null:
			count += 1
	return count

func _count_in_progress(grid: TerrainFieldGrid, name: String) -> int:
	var count := 0
	for field in grid.ordered_fields:
		if field.in_progress_building != null and field.in_progress_building.name == name:
			count += 1
	return count

func _building_counts(collector, grid: TerrainFieldGrid) -> Dictionary:
	var counts: Dictionary = collector._built_completed.duplicate()
	for field in grid.ordered_fields:
		var building: Building = field.in_progress_building
		if building != null:
			counts[building.name] = counts.get(building.name, 0) + 1
	return counts

func _producer_for(res: Enums.TownResource, producers: Dictionary, collector, grid: TerrainFieldGrid) -> Building:
	if res != Enums.TownResource.GOLD:
		return _building_by_name(producers[res])
	for candidate_name in ["Stone Works", "Timber Yard"]:
		var b := _building_by_name(candidate_name)
		if b != null and _has_any_cell(b, collector, grid):
			return b
	return _building_by_name("Stone Works")

func _has_any_cell(building: Building, collector, grid: TerrainFieldGrid) -> bool:
	if building == null:
		return false
	for field in grid.ordered_fields:
		if collector.build_handler.can_build_on_field(field, building):
			return true
	return false

func _has_producer(res: Enums.TownResource, producers: Dictionary, counts: Dictionary) -> bool:
	if res == Enums.TownResource.GOLD:
		if counts.get("Mine", 0) == 0:
			return false
		return counts.get("Stone Works", 0) > 0 or counts.get("Timber Yard", 0) > 0
	return counts.get(producers[res], 0) > 0

func _needs_population(prod: ProductionHandler, collector, grid: TerrainFieldGrid) -> bool:
	if GameData.population > GameData.working_population + _in_progress_count(grid):
		return false
	var producers: Dictionary = {
		Enums.TownResource.WOOD: "Sawmill",
		Enums.TownResource.STONE: "Mine",
		Enums.TownResource.FOOD: "Farm",
		Enums.TownResource.GOLD: "Stone Works",
	}
	var counts: Dictionary = _building_counts(collector, grid)
	for res in producers.keys():
		if not _has_producer(res, producers, counts):
			return true
	# Endgame: the Workshop needs a free worker (Building.build() requires
	# population > working_population), so keep one spare population slot.
	if GameData.working_population >= GameData.population and GameData.population < 6:
		return true
	return false

func _resources_by_lowest_stock(prod: ProductionHandler) -> Array:
	var sorted: Array = prod.town_resources.keys()
	sorted.sort_custom(func(a, b): return prod.town_resources[a] < prod.town_resources[b])
	return sorted

func _producer_order(prod: ProductionHandler, producers: Dictionary, counts: Dictionary) -> Array:
	var missing: Array = []
	for res in producers.keys():
		if not _has_producer(res, producers, counts):
			missing.append(res)
	missing.sort_custom(func(a, b):
		if a == Enums.TownResource.FOOD:
			return true
		if b == Enums.TownResource.FOOD:
			return false
		return prod.town_resources[a] < prod.town_resources[b])
	return missing

func _find_cell_for(building: Building, grid: TerrainFieldGrid, build_handler: BuildHandler, collector, bctrl: BuilderController) -> TerrainField:
	var best: TerrainField = null
	var best_dist := INF
	for field in grid.ordered_fields:
		if not build_handler.can_build_on_field(field, building):
			continue
		if not collector.can_build(building):
			continue
		var d: float = _nearest_builder_distance(field, bctrl)
		if d < best_dist:
			best_dist = d
			best = field
	return best

func _has_mover_to(cell: TerrainField, bctrl: BuilderController) -> bool:
	for builder in bctrl.builders:
		if builder.target_position == cell:
			return true
	return false

func _nearest_builder_distance(field: TerrainField, bctrl: BuilderController) -> float:
	var best := INF
	for builder in bctrl.builders:
		if builder.field == null:
			continue
		var d: float = absf(builder.field.grid_position.x - field.grid_position.x) + absf(builder.field.grid_position.y - field.grid_position.y)
		if d < best:
			best = d
	return best

func _nearest_idle_builder(cell: TerrainField, bctrl: BuilderController):
	var best = null
	var best_dist := INF
	for builder in bctrl.builders:
		if builder.field == null:
			continue
		if builder.state_machine.current_state_name.to_lower() != "idle":
			continue
		# A builder idle on a field with an in-progress building is committed to
		# it (it auto-enters the building state next turn) — do not reassign.
		if builder.field.in_progress_building != null:
			continue
		var d: float = absf(builder.field.grid_position.x - cell.grid_position.x) + absf(builder.field.grid_position.y - cell.grid_position.y)
		if d < best_dist:
			best_dist = d
			best = builder
	return best

func _building_by_name(name: String) -> Building:
	for building in ResourceDatabase.buildings:
		if building.name == name:
			return building
	return null

func _report(policy: String, prod: ProductionHandler, bctrl: BuilderController, collector) -> void:
	var won: bool = collector.is_game_won
	var breakdown: Dictionary = {}
	for key in collector.COMPONENT_KEYS:
		breakdown[key] = collector.episode_components.get(key, 0.0)
	print(
		"SCRIPTED: policy=%s seed=%d won=%s turns=%d pop=%d/%d builders=%d resources=%s production=%s started=%s completed=%s breakdown=%s"
		% [
			policy,
			Global.map_seed,
			str(won),
			Turn.turn,
			GameData.population,
			GameData.working_population,
			bctrl.builders.size(),
			str(prod.town_resources),
			str(prod.current_production),
			str(collector._built_started),
			str(collector._built_completed),
			str(breakdown),
		]
	)
