extends Node

# Win related
signal game_won()

var in_reset: bool = false
var connected_to_trainer: bool = false
## Map RNG seed from CLI (--seed=) or RESET:<seed>. Valid even when negative.
var map_seed: int = 0
var map_seed_valid: bool = false
var win_conditions_met: int = 0:
    set(value):
        win_conditions_met = value
        if win_conditions_met >= total_win_conditions:
            game_won.emit()
var total_win_conditions: int = 1

# Lost related
signal game_lost()

func _ready() -> void:
    if ArgsParser.kwargs.has("seed"):
        map_seed = int(ArgsParser.kwargs["seed"])
        map_seed_valid = true

func reset_environment() -> void:
    if in_reset:
        return
    in_reset = true
    win_conditions_met = 0
    for building in ResourceDatabase.buildings:
        building.already_built = false
    GameData.reset()
    Turn.reset()
    await get_tree().reload_current_scene()
    in_reset = false

# AI related
signal add_to_reward(value: float)
