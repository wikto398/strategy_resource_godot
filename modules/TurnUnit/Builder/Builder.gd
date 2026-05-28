class_name Builder extends TurnUnit

var state_mapping: Dictionary = {
	"idle": 0,
	"moving": 1,
	"building": 2
}

func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			unit_clicked.emit(self)
			viewport.set_input_as_handled()

func observation() -> Array:
	return [
		field.grid_position.x if field else -1,
		field.grid_position.y if field else -1,
		target_position.grid_position.x if target_position else -1,
		target_position.grid_position.y if target_position else -1,
		state_mapping.get(state_machine.current_state_name, -1)
	]

func reachable_fields() -> Array:
	return Pathing.dijkstra(field, -1, TerrainFieldGrid.instance, FieldIsWalkableCondition.new(), self)["reachable_fields"]
