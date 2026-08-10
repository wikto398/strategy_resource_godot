class_name FieldIsWalkableCondition extends Condition

func _evaluate(data: Dictionary = {}) -> bool:
	var neighbor: TerrainField = data.get("neighbor", null)
	if not neighbor:
		return false
	if neighbor.walkable:
		return true
	var unit: Unit = data.get("unit", null)
	return unit is Builder and neighbor.terrain_type == Terrain.TerrainType.WATER and GameData.builders_walk_on_water
