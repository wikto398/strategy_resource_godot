class_name IncreaseGameDataVariableSpecial extends Special

@export var variable_name: String
@export var increment_value: Variant = 1

func activate() -> void:
	if variable_name in GameData:
		GameData[variable_name] += increment_value
	else:
		push_error("GameData does not have a variable named '%s'" % variable_name)
		return
