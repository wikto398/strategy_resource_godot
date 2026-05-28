class_name FieldIsWalkableCondition extends Condition

func _evaluate(data: Dictionary = {}) -> bool:
	var neighbor: TerrainField = data.get("neighbor", null)
	if not neighbor:
		return false
	return neighbor.walkable
