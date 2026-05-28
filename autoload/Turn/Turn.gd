extends Node

var turn: int = 1
var max_turns: int = 10000

signal next_turn

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_T:
            go_to_next_turn()

func go_to_next_turn() -> void:
    turn += 1
    next_turn.emit()
