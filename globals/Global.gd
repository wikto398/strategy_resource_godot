extends Node

# Win related
signal game_won()

var win_conditions_met: int = 0:
    set(value):
        win_conditions_met = value
        if win_conditions_met >= total_win_conditions:
            game_won.emit()
var total_win_conditions: int = 1

# Lost related
signal game_lost()
