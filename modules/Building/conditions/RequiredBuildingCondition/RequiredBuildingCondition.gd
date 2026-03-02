class_name RequiredBuildingCondition extends Condition

@export var required_building: Building
@export var required_building_by_name: String

func _evaluate(data: Dictionary = {}) -> bool:
	var field: Field = data.get("field")
	if field and field.building:
		if required_building:
			return _evaluate_by_building(data)
		elif required_building_by_name != "":
			return _evaluate_by_name(data)
	return false

func _evaluate_by_name(data: Dictionary = {}) -> bool:
	var field: Field = data.get("field")
	if field and field.building:
		return field.building.name.to_lower() == required_building_by_name.to_lower()
	return false

func _evaluate_by_building(data: Dictionary = {}) -> bool:
	var field: Field = data.get("field")
	if field and field.building:
		return field.building.name.to_lower() == required_building.name.to_lower()
	return false
