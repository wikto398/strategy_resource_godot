class_name Builder extends Unit

func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			unit_clicked.emit(self)
			viewport.set_input_as_handled()
