class_name ObservationCollector extends ObservationCollectorInterface

const POP_MILESTONES: Array = [4, 5, 6, 8]
const PROD_MILESTONES: Array = [5, 10, 20, 30]
const STOCK_MILESTONES: Array = [800, 1200, 1500]

@export var field_grid: TerrainFieldGrid
@export var build_handler: BuildHandler
@export var production_handler: ProductionHandler
@export var builder_controller: BuilderController
@export var action_executor: ActionExecutor

var is_game_won: bool = false
var done: bool = false
var reward = 0.0
var last_action: Array = []

const COMPONENT_KEYS: Array = ["time", "deficit", "production", "economy", "stock_warning", "milestones", "stockpile", "productive", "construction", "win_progress", "build_start", "build_finish", "first_build", "events", "move", "skip", "build", "over_commit", "over_commit_state", "balance", "housing", "resource_gap", "surplus", "terminal"]

var episode_components: Dictionary = {}
var pending_components: Dictionary = {}
var _peak_min_stock: float = 0.0
var _phi_applied: float = 0.0
var _completed_value: float = 0.0
var _built_types: Dictionary = {}
var _built_started: Dictionary = {}
var _built_completed: Dictionary = {}
var _neighbor_table: Array[PackedInt32Array] = []
var _start_cache: Dictionary[int, PackedByteArray] = {}
var _walk_on_water_snapshot: bool = false
var _buildable_cache: Array = []
var _gate_cache: Array = []
var _field_masks_cache: Array = []
var _pending_patches: Array[int] = []
var _field_masks_initialized: bool = false
var _prev_progress: Dictionary = {}
var _pop_milestones: Dictionary = {}
var _prod_milestones: Dictionary = {}
var _stock_milestones: Dictionary = {}

enum RewardMode {
    AFTER_SKIP,
    AFTER_BUILD,
    AFTER_MOVE,
    FINAL_REWARD
}


func _ready() -> void:
    super._ready()
    Global.game_won.connect(_on_game_won)
    Global.game_lost.connect(_on_game_lost)
    Global.add_to_reward.connect(_on_add_to_reward)
    if action_executor != null:
        action_executor.action_executed.connect(_on_action_executed)
    else:
        DebugLogger.error("ObservationCollector requires an action_executor reference.")
    if production_handler != null:
        production_handler.building_started.connect(_on_building_started)
        production_handler.building_completed.connect(_on_building_completed)
    _peak_min_stock = _min_stock()

func _on_action_executed(action: Array) -> void:
    last_action = action

func _on_building_started(building: Building, field: Field) -> void:
    _built_started[building.name] = _built_started.get(building.name, 0) + 1
    _pending_patches.append(_flat_of(field))

func _on_building_completed(building: Building, field: Field) -> void:
    var count_before = _built_completed.get(building.name, 0)
    _built_completed[building.name] = count_before + 1
    var total_cost = 0
    for resource in building.build_cost.values():
        total_cost += resource
    _completed_value += total_cost
    var first = not _built_types.has(building.name)
    _built_types[building.name] = true
    if first:
        _on_add_to_reward(RewardConfig.first_build_bonus, "first_build")
    if building is ProductionBuilding:
        var reward_value = building.production_rate * RewardConfig.build_finish_coef / (1.0 + count_before)
        _on_add_to_reward(reward_value, "build_finish")
        var net = _projected_production(building.produced_resource)
        var gap = clampf(RewardConfig.gap_target - float(net), 0.0, RewardConfig.gap_cap)
        _on_add_to_reward(RewardConfig.gap_coef * gap, "resource_gap")
    else:
        _on_add_to_reward(RewardConfig.build_finish_flat / (1.0 + count_before), "build_finish")
    _pending_patches.append(_flat_of(field))
    for neighbor in field_grid.get_neighbours(field.grid_position):
        _pending_patches.append(_flat_of(neighbor))

func _projected_production(resource: Enums.TownResource) -> int:
    var total: int = production_handler.current_production.get(resource, 0)
    for field in field_grid.ordered_fields:
        var in_progress: Building = field.in_progress_building
        if in_progress is ProductionBuilding and in_progress.produced_resource == resource:
            total += in_progress.production_rate
    return total

func _reward() -> float:
    var event_total = reward
    reward = 0.0
    var pending = pending_components.duplicate()
    pending_components.clear()
    var total = event_total
    var reward_mode: RewardMode = _set_reward_mode(last_action)
    var components: Dictionary = _empty_components()
    for tag in pending:
        if COMPONENT_KEYS.has(tag):
            components[tag] = components[tag] + pending[tag]

    match reward_mode:
        RewardMode.FINAL_REWARD:
            var terminal = _result_score()
            total += terminal
            components["terminal"] = terminal

        RewardMode.AFTER_SKIP:
            if not last_action.is_empty():
                var skip = _skip_reward()
                var time = _time_penalty()
                var deficit = _deficit_penalty()
                var production = _production_penalty()
                var economy = _economy_reward()
                var balance = _balance_reward()
                var stock_warning = _stock_warning()
                var milestones = _milestones()
                var stockpile = _stockpile_reward()
                var productive = _productive_turn()
                var construction = _construction_reward()
                var surplus = _surplus_penalty()
                var win_progress = _win_progress()
                var over_commit_state = _over_commit_state_penalty()
                total += skip + time + deficit + production + economy + balance + stock_warning + milestones + stockpile + productive + construction + surplus + win_progress + over_commit_state
                components["skip"] = skip
                components["time"] = time
                components["deficit"] = deficit
                components["production"] = production
                components["economy"] = economy
                components["balance"] = balance
                components["stock_warning"] = stock_warning
                components["milestones"] = milestones
                components["stockpile"] = stockpile
                components["productive"] = productive
                components["construction"] = construction
                components["surplus"] = surplus
                components["win_progress"] = win_progress
                components["over_commit_state"] = over_commit_state

        RewardMode.AFTER_MOVE:
            var move = _move_reward()
            total += move
            components["move"] = move

        RewardMode.AFTER_BUILD:
            var build = _build_reward()
            var over_commit = _over_commit_penalty()
            total += build + over_commit
            components["build"] = build
            components["over_commit"] = over_commit

    _accumulate_episode(components)

    DebugLogger.debug("Calculating reward for action: " + str(last_action) + ", reward mode: " + str(reward_mode) + ", reward: " + str(total))
    if done:
        _log_episode_breakdown()

    return total

func _observation() -> Dictionary:
    return {
        "fields": field_grid.observation(),
        "global": _global_features(),
        "builders": builder_controller.observation()
    }

func _action_mask() -> Dictionary:
    var available_buildings = _available_buildings()
    var field_masks = _field_masks()
    var moveable_cells = _movable_cells()
    var available_builders = _available_builders()
    var real_builders = _real_builders()
    return {"buildable_cells": field_masks, "available_buildings": available_buildings, "moveable_cells": moveable_cells, "available_builders": available_builders, "real_builders": real_builders, "available_skip": 1 if ResourceDatabase.buildings[0].already_built else 0}

func get_observation_bytes() -> PackedByteArray:
    # Flat binary protocol. Layout must stay in sync with
    # rl_tools/game_engine/ObservationInterface/UDPObservation/UDPObservation.py
    # and torch_files/Factory/NetworkFactory.py (AGENTS.md). Native little-endian.
    # Call order matches get_observation() so _reward() side-effects are unchanged.
    var observation := _observation()
    var action_mask := _action_mask()
    var reward_val := _reward()
    var done_val := _done()
    var info := _info()

    var bytes := PackedByteArray()
    bytes.append(0x53)  # magic
    bytes.append(0x01)  # version

    var floats := PackedFloat32Array()
    for field_obs in observation["fields"]:
        for v in field_obs:
            floats.append(float(v))
    for v in observation["global"]:
        floats.append(float(v))
    for builder_obs in observation["builders"]:
        for v in builder_obs:
            floats.append(float(v))
    bytes.append_array(floats.to_byte_array())

    bytes.append_array(_mask_u8s(action_mask["buildable_cells"]))
    bytes.append_array(_mask_u8s(action_mask["available_buildings"]))
    bytes.append_array(_mask_u8s(action_mask["moveable_cells"]))
    bytes.append_array(_mask_u8s(action_mask["available_builders"]))
    bytes.append_array(_mask_u8s(action_mask["real_builders"]))
    bytes.append(1 if action_mask["available_skip"] else 0)

    bytes.append_array(PackedFloat32Array([reward_val]).to_byte_array())
    bytes.append(1 if done_val else 0)

    var info_bytes: PackedByteArray = Messagepack.encode(info)["value"]
    bytes.append_array(PackedInt32Array([info_bytes.size()]).to_byte_array())
    bytes.append_array(info_bytes)
    return bytes

func _mask_u8s(mask: Array) -> PackedByteArray:
    var out := PackedByteArray()
    for row in mask:
        if row is Array:
            for v in row:
                out.append(1 if v else 0)
        else:
            out.append(1 if row else 0)
    return out

func _field_masks() -> Array:
    if not _field_masks_initialized:
        _init_field_masks()
    _apply_pending_patches()
    _refresh_gates()
    return _field_masks_cache

func _init_field_masks() -> void:
    var zeros: Array = []
    for j in field_grid.ordered_fields.size():
        zeros.append(0)
    for building in ResourceDatabase.buildings:
        var gate = can_build(building)
        _gate_cache.append(gate)
        var buildable_row = []
        for field in field_grid.ordered_fields:
            buildable_row.append(1 if build_handler.can_build_on_field(field, building) else 0)
        _buildable_cache.append(buildable_row)
        _field_masks_cache.append(buildable_row.duplicate() if gate else zeros.duplicate())
    _field_masks_initialized = true

func _flat_of(field: Field) -> int:
    return int(field.grid_position.x + field_grid.columns * field.grid_position.y)

func _apply_pending_patches() -> void:
    if _pending_patches.is_empty():
        return
    for flat in _pending_patches:
        var field = field_grid.ordered_fields[flat]
        for i in ResourceDatabase.buildings.size():
            var value = 1 if build_handler.can_build_on_field(field, ResourceDatabase.buildings[i]) else 0
            _buildable_cache[i][flat] = value
            if _gate_cache[i]:
                _field_masks_cache[i][flat] = value
    _pending_patches.clear()

func _refresh_gates() -> void:
    for i in ResourceDatabase.buildings.size():
        var gate = can_build(ResourceDatabase.buildings[i])
        if gate != _gate_cache[i]:
            _gate_cache[i] = gate
            if gate:
                _field_masks_cache[i] = _buildable_cache[i].duplicate()
            else:
                for j in _field_masks_cache[i].size():
                    _field_masks_cache[i][j] = 0

func _available_buildings() -> Array:
    var available_buildings = []
    var city_center = ResourceDatabase.buildings[0]
    if not city_center.already_built:
        available_buildings.append(1)
        for i in range(1, ResourceDatabase.buildings.size()):
            available_buildings.append(0)
        return available_buildings
    for building in ResourceDatabase.buildings:
        if can_build(building):
            available_buildings.append(1)
        else:
            available_buildings.append(0)

    return available_buildings

func _global_features() -> Array:
    var obs: Array = []
    obs.append_array(production_handler.current_production.values())
    obs.append_array(production_handler.town_resources.values())
    obs.append_array(GameData.observation())
    return obs

func _movable_cells() -> Array:
    _ensure_pathing_data()
    var movable_cells = []
    var columns: int = field_grid.columns
    for builder in builder_controller.builders:
        var builder_cells = []
        var flat: int = int(builder.field.grid_position.x + columns * builder.field.grid_position.y)
        if not _start_cache.has(flat):
            _start_cache[flat] = FlatPathing.bfs_mask(flat, _neighbor_table)
        for cell in _start_cache[flat]:
            builder_cells.append(cell)
        movable_cells.append(builder_cells)
    while movable_cells.size() < GameData.MAX_BUILDERS:
        var empty_cells = []
        for i in field_grid.ordered_fields.size():
            empty_cells.append(0)
        movable_cells.append(empty_cells)
    return movable_cells

func _ensure_pathing_data() -> void:
    var walk_on_water: bool = GameData.builders_walk_on_water
    if _neighbor_table.is_empty() or _walk_on_water_snapshot != walk_on_water:
        _neighbor_table = FlatPathing.build_neighbor_table(field_grid, walk_on_water)
        _start_cache.clear()
        _walk_on_water_snapshot = walk_on_water

func _on_game_won() -> void:
    is_game_won = true
    done = true

func _on_game_lost() -> void:
    done = true

func _done() -> bool:
    return done

func _info() -> Dictionary:
    var info: Dictionary = {
        "won": is_game_won,
        "lost": done and not is_game_won,
    }
    if done:
        info["turns"] = Turn.turn
        info["population"] = GameData.population
        info["working_population"] = GameData.working_population
        info["total_resources"] = _total_resources()
        info["production"] = production_handler.current_production.values()
        info["buildings_started"] = _built_started.duplicate()
        info["buildings_completed"] = _built_completed.duplicate()
        info["reward_breakdown"] = episode_components.duplicate()
    return info

func can_build(building: Building) -> bool:
    if building.already_built:
        return false
    if building is ProductionBuilding and GameData.population <= GameData.working_population:
        return false
    return production_handler.can_afford(building.build_cost)

func _available_builders() -> Array:
    var available_builders = []
    for builder in builder_controller.builders:
        if builder.state_machine.current_state_name.to_lower() == "idle":
            available_builders.append(1)
        else:
            available_builders.append(0)
    while available_builders.size() < GameData.MAX_BUILDERS:
        available_builders.append(0)
    return available_builders

func _real_builders() -> Array:
    var real_builders = []
    for builder in builder_controller.builders:
        real_builders.append(1)
    while real_builders.size() < GameData.MAX_BUILDERS:
        real_builders.append(0)
    return real_builders

func _move_reward() -> float:
    var additional_reward = 0.0
    var move_target = last_action.get(3)
    if move_target != null:
        var position: Vector2i = field_grid.flat_to_2d_index(move_target)
        var field = field_grid.get_field_at(position)
        if field != null:
            if field.in_progress_building != null:
                DebugLogger.debug("Builder moved to a field with an in-progress building. Rewarding additional points.")
                additional_reward += 0.2
            elif _is_buildable_destination(field):
                DebugLogger.debug("Builder moved to a buildable field. Rewarding additional points.")
                additional_reward += 0.1
    return additional_reward

func _is_buildable_destination(field: Field) -> bool:
    for building in ResourceDatabase.buildings:
        if can_build(building) and build_handler.can_build_on_field(field, building):
            return true
    return false

func _build_reward() -> float:
    var additional_reward = 0.0
    return additional_reward

func _over_commit_overshoot() -> int:
    var in_progress = 0
    for field in field_grid.ordered_fields:
        if field.in_progress_building != null:
            in_progress += 1
    var free_population = GameData.population - GameData.working_population
    return in_progress - free_population

func _over_commit_penalty() -> float:
    var building_type: int = last_action.get(2)
    if building_type == null:
        return 0.0
    var building: Building = ResourceDatabase.int_to_building.get(building_type)
    if building == null:
        return 0.0
    var overshoot = _over_commit_overshoot()
    if overshoot > 0:
        DebugLogger.debug("Starting " + building.name + " with too many buildings in progress. Applying over-commit penalty scaled by overshoot.")
        return -RewardConfig.over_commit_penalty * overshoot
    return 0.0

func _over_commit_state_penalty() -> float:
    var overshoot = _over_commit_overshoot()
    if overshoot > 0:
        DebugLogger.debug("Still overcommitted by " + str(overshoot) + " buildings. Applying per-turn over-commit state penalty.")
        return -RewardConfig.over_commit_state_penalty * overshoot
    return 0.0

func _skip_reward() -> float:
    return RewardConfig.skip_penalty

func _economy_reward() -> float:
    var reward_value = 0.0
    for production in production_handler.current_production.values():
        reward_value += clampf(production, 0.0, RewardConfig.economy_cap) * RewardConfig.economy_coef
    return reward_value

func _balance_reward() -> float:
    var positive_count = 0
    for production in production_handler.current_production.values():
        if production > 0:
            positive_count += 1
    return RewardConfig.balance_coef * positive_count

func _stock_warning() -> float:
    var penalty = 0.0
    for resource in production_handler.town_resources.keys():
        var stock = production_handler.town_resources[resource]
        var shortfall = max(0.0, 1.0 - stock / RewardConfig.stock_warning_threshold)
        penalty -= RewardConfig.stock_warning_coef * min(3.0, shortfall)
    return penalty

func _milestones() -> float:
    var reward_value = 0.0
    var pop = GameData.population
    for level in POP_MILESTONES:
        if pop >= level and not _pop_milestones.has(level):
            _pop_milestones[level] = true
            reward_value += RewardConfig.pop_milestone_bonus
    var net_production = 0
    for production in production_handler.current_production.values():
        net_production += production
    for level in PROD_MILESTONES:
        if net_production >= level and not _prod_milestones.has(level):
            _prod_milestones[level] = true
            reward_value += 1.0
    var min_stock = _min_stock()
    if min_stock > _peak_min_stock:
        reward_value += RewardConfig.peak_coef * (min_stock - _peak_min_stock)
        _peak_min_stock = min_stock
    return reward_value

func _stockpile_reward() -> float:
    var reward_value = 0.0
    var min_stock = _min_stock()
    for level in STOCK_MILESTONES:
        if min_stock >= level and not _stock_milestones.has(level):
            _stock_milestones[level] = true
            reward_value += RewardConfig.stock_milestone_bonus
    return reward_value

func _min_stock() -> float:
    var min_value = INF
    for resource in production_handler.town_resources.values():
        min_value = min(min_value, float(resource))
    return min_value

func _productive_turn() -> float:
    var free_population = GameData.working_population < GameData.population
    var positive_net = false
    for production in production_handler.current_production.values():
        if production > 0:
            positive_net = true
            break
    if not free_population and not positive_net:
        return 0.0
    var productive = false
    for builder in builder_controller.builders:
        if builder.state_machine.current_state_name.to_lower() == "building":
            productive = true
            break
    if not productive:
        for production in production_handler.current_production.values():
            if production > 0:
                productive = true
                break
    return RewardConfig.productive_bonus if productive else 0.0

func _construction_reward() -> float:
    var total_progress = 0
    for field in field_grid.ordered_fields:
        var building = field.in_progress_building
        if building == null:
            continue
        var key = _flat_of(field)
        var prev = _prev_progress.get(key, 0)
        _prev_progress[key] = building.building_progress
        total_progress += maxi(0, building.building_progress - prev)
    return RewardConfig.construction_bonus * float(total_progress)

func _surplus_penalty() -> float:
    var penalty = 0.0
    var min_stock = _min_stock()
    for resource in production_handler.current_production.keys():
        var net = production_handler.current_production[resource]
        if net <= RewardConfig.surplus_target:
            continue
        var threshold := maxf(min_stock * RewardConfig.surplus_stock_ratio, RewardConfig.surplus_stock_floor)
        if production_handler.town_resources.get(resource, 0) <= threshold:
            continue
        penalty -= RewardConfig.surplus_coef * min(RewardConfig.surplus_cap, float(net) - RewardConfig.surplus_target)
    return penalty

func _win_progress() -> float:
    var phi = RewardConfig.win_progress_coef * _completed_value
    var reward_value = RewardConfig.gamma * phi - _phi_applied
    _phi_applied = phi
    return reward_value

func _total_resources() -> float:
    var total = 0.0
    for resource in production_handler.town_resources.values():
        total += resource
    return total

func _set_reward_mode(action) -> RewardMode:
    if done:
        return RewardMode.FINAL_REWARD
    if action.size() == 0:
        return RewardMode.AFTER_SKIP
    match action.get(0):
        0:
            return RewardMode.AFTER_SKIP
        1:
            return RewardMode.AFTER_MOVE
        2:
            return RewardMode.AFTER_BUILD
        _:
            return RewardMode.AFTER_SKIP

func _on_add_to_reward(value: float, tag: String = "events") -> void:
    DebugLogger.trace("Adding to reward: " + str(value) + " (" + tag + ")")
    reward += value
    pending_components[tag] = pending_components.get(tag, 0.0) + value

func _result_score() -> float:
    var score = RewardConfig.win_bonus if is_game_won else _loss_penalty()
    score += _production_bonus()
    score += _progress_bonus()
    DebugLogger.debug("Final score calculated: " + str(score))

    return score

func _loss_penalty() -> float:
    return RewardConfig.loss_penalty

func _progress_bonus() -> float:
    var score = 0.0
    score += GameData.population * 0.1
    score += GameData.working_population * 0.1
    return score

func _production_bonus() -> float:
    var score = 0.0
    for production in production_handler.current_production.values():
        score += production * RewardConfig.production_bonus_coef
    return score

func _deficit_penalty() -> float:
    var penalty = 0.0
    for resource in production_handler.town_resources.keys():
        if production_handler.town_resources[resource] <= 0:
            penalty -= RewardConfig.deficit_coef * min(RewardConfig.deficit_cap, production_handler.current_deficit_duration[resource])
    DebugLogger.debug("Deficit penalty calculated: " + str(penalty))
    return penalty

func _production_penalty() -> float:
    var penalty = 0.0
    for resource in production_handler.current_production.keys():
        if production_handler.current_production[resource] <= 0:
            if production_handler.town_resources[resource] > 0:
                continue
            if _has_in_progress_producer(resource):
                continue
            penalty -= RewardConfig.production_penalty_coef * min(RewardConfig.production_penalty_cap, -production_handler.current_production[resource])
    DebugLogger.debug("Production penalty calculated: " + str(penalty))
    return penalty

func _has_in_progress_producer(resource: Enums.TownResource) -> bool:
    for field in field_grid.ordered_fields:
        var in_progress: Building = field.in_progress_building
        if in_progress is ProductionBuilding and in_progress.produced_resource == resource:
            return true
    return false

func _time_penalty() -> float:
    return RewardConfig.time_penalty

func _empty_components() -> Dictionary:
    var components = {}
    for key in COMPONENT_KEYS:
        components[key] = 0.0
    return components

func _accumulate_episode(components: Dictionary) -> void:
    for key in COMPONENT_KEYS:
        episode_components[key] = episode_components.get(key, 0.0) + components[key]

func _log_episode_breakdown() -> void:
    var result = "WON" if is_game_won else "LOST"
    DebugLogger.info(
        "Episode ended (%s). Turns: %d, Pop: %d/%d, Resources: %d, Production: %s, Started: %s, Completed: %s. Reward breakdown: %s"
        % [
            result,
            Turn.turn,
            GameData.population,
            GameData.working_population,
            int(_total_resources()),
            str(production_handler.current_production),
            str(_built_started),
            str(_built_completed),
            str(episode_components),
        ]
    )
