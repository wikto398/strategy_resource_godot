extends Node

var turn: int = 1
var max_turns: int = 2000

signal next_turn

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_T:
            go_to_next_turn()

func go_to_next_turn() -> void:
    turn += 1
    if turn > max_turns:
        DebugLogger.info("Max turns reached. Game over.")
        Global.game_lost.emit()
    next_turn.emit()

func reset() -> void:
    turn = 1
