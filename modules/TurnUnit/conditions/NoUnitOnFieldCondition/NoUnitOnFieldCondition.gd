class_name NoUnitOnFieldCondition extends Condition

func _evaluate(data: Dictionary = {}) -> bool:
	var neighbor: TerrainField = data.get("neighbor", null)
	if not neighbor:
		return false
	return not neighbor.unit
