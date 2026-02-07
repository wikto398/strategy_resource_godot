extends Camera2D

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            var scroll_amount = event.factor * 100
            if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                scroll_amount = -scroll_amount
            var new_zoom = zoom + Vector2(scroll_amount, scroll_amount) * 0.01
            if new_zoom == Vector2.ZERO:
                return
            zoom = new_zoom
            get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_MIDDLE:
            if event.pressed:
                zoom = Vector2(1, 1)
                get_viewport().set_input_as_handled()