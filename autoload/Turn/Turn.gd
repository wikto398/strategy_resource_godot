extends Node

signal next_turn

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_T:
            next_turn.emit()