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
    var reward = -time_penalty
    match reward_mode:
        RewardMode.AFTER_SKIP:
            reward += production_handler.get_production_reward()
        RewardMode.AFTER_BUILD:
            reward = production_handler.get_production_reward()
        RewardMode.AFTER_MOVE:
            reward = production_handler.get_production_reward()
        RewardMode.FINAL_REWARD:
            if is_game_won:
                reward = 100.0
            else:
                reward = -100.0
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
    return {"buildable_cells": field_masks, "available_buildings": available_buildings, "moveable_cells": moveable_cells}

func _field_masks() -> Array:
    var field_masks = []
    for building in ResourceDatabase.buildings:
        var current_field_building_masks = []
        for field in field_grid.fields.values():
            if build_handler.can_build_on_field(field, building):
                current_field_building_masks.append(1)
            else:
                current_field_building_masks.append(0)
        field_masks.append(current_field_building_masks)
    return field_masks

func _available_buildings() -> Array:
    var available_buildings = []
    for building in ResourceDatabase.buildings:
        if production_handler.can_afford(building.build_cost):
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
        for field in field_grid.fields.values():
            if reachable_fields.has(field):
                builder_cells.append(1)
            else:
                builder_cells.append(0)
        movable_cells.append(builder_cells)
    return movable_cells

func _on_game_won() -> void:
    is_game_won = true
    done = true

func _on_game_lost() -> void:
    done = true

func _done() -> bool:
    return done
