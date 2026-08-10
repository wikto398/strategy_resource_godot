class_name ObservationCollector extends ObservationCollectorInterface

const GAMMA: float = 0.99
const STOCK_WARNING_THRESHOLD: float = 100.0
const STOCK_WARNING_COEF: float = 0.05
const DEFICIT_CAP: float = 10.0
const PRODUCTION_PENALTY_CAP: float = 10.0
const PRODUCTION_PENALTY_COEF: float = 0.05
const ECONOMY_COEF: float = 0.05
const PRODUCTIVE_BONUS: float = 0.15
const FIRST_BUILD_BONUS: float = 1.0
const WIN_PROGRESS_COEF: float = 0.002
const POP_MILESTONES: Array = [4, 6, 8, 10]
const PROD_MILESTONES: Array = [5, 10, 20, 30]

@export var field_grid: TerrainFieldGrid
@export var build_handler: BuildHandler
@export var production_handler: ProductionHandler
@export var builder_controller: BuilderController
@export var action_executor: ActionExecutor

var is_game_won: bool = false
var done: bool = false
var reward = 0.0
var last_action: Array = []

const COMPONENT_KEYS: Array = ["time", "deficit", "production", "economy", "stock_warning", "milestones", "productive", "win_progress", "build_start", "build_finish", "first_build", "events", "move", "skip", "build", "terminal"]

var episode_components: Dictionary = {}
var pending_components: Dictionary = {}
var _peak_total: float = 0.0
var _phi_applied: float = 0.0
var _completed_value: float = 0.0
var _built_types: Dictionary = {}
var _built_started: Dictionary = {}
var _built_completed: Dictionary = {}
var _pop_milestones: Dictionary = {}
var _prod_milestones: Dictionary = {}

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
    _peak_total = _total_resources()

func _on_action_executed(action: Array) -> void:
    last_action = action

func _on_building_started(building: Building) -> void:
    _built_started[building.name] = _built_started.get(building.name, 0) + 1

func _on_building_completed(building: Building) -> void:
    _built_completed[building.name] = _built_completed.get(building.name, 0) + 1
    var total_cost = 0
    for resource in building.build_cost.values():
        total_cost += resource
    _completed_value += total_cost
    var first = not _built_types.has(building.name)
    _built_types[building.name] = true
    if first:
        _on_add_to_reward(FIRST_BUILD_BONUS, "first_build")

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
                var stock_warning = _stock_warning()
                var milestones = _milestones()
                var productive = _productive_turn()
                var win_progress = _win_progress()
                total += skip + time + deficit + production + economy + stock_warning + milestones + productive + win_progress
                components["skip"] = skip
                components["time"] = time
                components["deficit"] = deficit
                components["production"] = production
                components["economy"] = economy
                components["stock_warning"] = stock_warning
                components["milestones"] = milestones
                components["productive"] = productive
                components["win_progress"] = win_progress

        RewardMode.AFTER_MOVE:
            var move = _move_reward()
            total += move
            components["move"] = move

        RewardMode.AFTER_BUILD:
            var build = _build_reward()
            total += build
            components["build"] = build

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
    return {"buildable_cells": field_masks, "available_buildings": available_buildings, "moveable_cells": moveable_cells, "available_builders": available_builders}

func _field_masks() -> Array:
    var field_masks = []

    for building in ResourceDatabase.buildings:
        var current_field_building_masks = []

        if not can_build(building):
            for field in field_grid.ordered_fields:
                current_field_building_masks.append(0)
        else:
            for field in field_grid.ordered_fields:
                if build_handler.can_build_on_field(field, building):
                    current_field_building_masks.append(1)
                else:
                    current_field_building_masks.append(0)

        field_masks.append(current_field_building_masks)

    return field_masks

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
    var movable_cells = []
    for builder in builder_controller.builders:
        var builder_cells = []
        var reachable_fields = builder.reachable_fields()
        for field in field_grid.ordered_fields:
            if reachable_fields.has(field):
                builder_cells.append(1)
            else:
                builder_cells.append(0)
        movable_cells.append(builder_cells)
    while movable_cells.size() < GameData.MAX_BUILDERS:
        var empty_cells = []
        for field in field_grid.ordered_fields:
            empty_cells.append(0)
        movable_cells.append(empty_cells)
    return movable_cells

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

func _skip_reward() -> float:
    return -0.05

func _economy_reward() -> float:
    var reward_value = 0.0
    for production in production_handler.current_production.values():
        if production > 0:
            reward_value += production * ECONOMY_COEF
    return reward_value

func _stock_warning() -> float:
    var penalty = 0.0
    for resource in production_handler.town_resources.keys():
        var stock = production_handler.town_resources[resource]
        var shortfall = max(0.0, 1.0 - stock / STOCK_WARNING_THRESHOLD)
        penalty -= STOCK_WARNING_COEF * min(3.0, shortfall)
    return penalty

func _milestones() -> float:
    var reward_value = 0.0
    var pop = GameData.population
    for level in POP_MILESTONES:
        if pop >= level and not _pop_milestones.has(level):
            _pop_milestones[level] = true
            reward_value += 1.0
    var net_production = 0
    for production in production_handler.current_production.values():
        net_production += production
    for level in PROD_MILESTONES:
        if net_production >= level and not _prod_milestones.has(level):
            _prod_milestones[level] = true
            reward_value += 1.0
    var total = _total_resources()
    if total > _peak_total:
        reward_value += 0.02 * (total - _peak_total)
        _peak_total = total
    return reward_value

func _productive_turn() -> float:
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
    return PRODUCTIVE_BONUS if productive else 0.0

func _win_progress() -> float:
    var phi = WIN_PROGRESS_COEF * _completed_value
    var reward_value = GAMMA * phi - _phi_applied
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
    var score = 10.0 if is_game_won else -10.0
    score += _production_bonus()
    score += _progress_bonus()
    DebugLogger.debug("Final score calculated: " + str(score))

    return score

func _progress_bonus() -> float:
    var score = 0.0
    score += GameData.population * 0.1
    score += GameData.working_population * 0.1
    return score

func _production_bonus() -> float:
    var score = 0.0
    for production in production_handler.current_production.values():
        score += production * 0.1
    return score

func _deficit_penalty() -> float:
    var penalty = 0.0
    for resource in production_handler.town_resources.keys():
        if production_handler.town_resources[resource] <= 0:
            penalty -= 0.1 * min(DEFICIT_CAP, production_handler.current_deficit_duration[resource])
    DebugLogger.debug("Deficit penalty calculated: " + str(penalty))
    return penalty

func _production_penalty() -> float:
    var penalty = 0.0
    for resource in production_handler.current_production.keys():
        if production_handler.current_production[resource] <= 0:
            penalty -= PRODUCTION_PENALTY_COEF * min(PRODUCTION_PENALTY_CAP, -production_handler.current_production[resource])
    DebugLogger.debug("Production penalty calculated: " + str(penalty))
    return penalty

func _time_penalty() -> float:
    var time_penalty = -0.01
    return time_penalty

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
