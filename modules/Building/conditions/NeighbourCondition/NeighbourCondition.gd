class_name NeighbourCondition extends Condition

@export var conditions: Array[Condition] = []

func _evaluate(data: Dictionary = {}) -> bool:
	var field: Field = data.get("field")
	if field:
		for neighbour in TerrainFieldGrid.instance.get_neighbours(field.grid_position):
			var neighbour_data = data.duplicate()
			neighbour_data["field"] = neighbour
			var all_conditions_met = true
			for condition in conditions:
				if not condition.evaluate(neighbour_data):
					all_conditions_met = false
					break
			if all_conditions_met:
				return true
	return false
