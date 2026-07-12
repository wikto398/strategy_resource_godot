class_name ObservationCollector extends ObservationCollectorInterface

@export var field_grid: TerrainFieldGrid
@export var build_handler: BuildHandler
@export var production_handler: ProductionHandler
@export var builder_controller: BuilderController

var time_penalty: float = 0.01
var is_game_won: bool = false
var done: bool = false

enum RewardMode {
    AFTER_SKIP,
    AFTER_BUILD,
    AFTER_MOVE,
    FINAL_REWARD
}

var reward_mode: RewardMode = RewardMode.AFTER_SKIP

func _ready() -> void:
    super._ready()
    Global.game_won.connect(_on_game_won)
    Global.game_lost.connect(_on_game_lost)

func _reward() -> float:
    var reward := -time_penalty

    match reward_mode:
        RewardMode.AFTER_BUILD:
            reward += _build_reward()

        RewardMode.AFTER_MOVE:
            reward += _move_reward()

        RewardMode.AFTER_SKIP:
            reward -= 0.02

        RewardMode.FINAL_REWARD:
            reward += 100.0 if is_game_won else -100.0

    return reward

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
    return {"buildable_cells": field_masks, "available_buildings": available_buildings, "moveable_cells": moveable_cells}

func _field_masks() -> Array:
    var field_masks = []
    for building in ResourceDatabase.buildings:
        var current_field_building_masks = []
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

func can_build(building: Building) -> bool:
    if building.already_built:
        return false
    return production_handler.can_afford(building.build_cost)

func _available_builders() -> Array:
    var available_builders = []
    for builder in builder_controller.builders:
        if builder.state_machine.current_state_name == "idle":
            available_builders.append(1)
        else:
            available_builders.append(0)
    while available_builders.size() < GameData.MAX_BUILDERS:
        available_builders.append(0)
    return available_builders

func _move_reward() -> float:
    var reward = 0.0
    return reward

func _build_reward() -> float:
    var reward = 0.5
    return reward
