extends Node

# Win related
signal game_won()

var in_reset: bool = false
var connected_to_trainer: bool = false
var win_conditions_met: int = 0:
    set(value):
        win_conditions_met = value
        if win_conditions_met >= total_win_conditions:
            game_won.emit()
var total_win_conditions: int = 1

# Lost related
signal game_lost()

func reset_environment() -> void:
    if in_reset:
        return
    in_reset = true
    win_conditions_met = 0
    await get_tree().reload_current_scene()
    in_reset = false
