class_name SetGameDataVariableSpecial extends Special

@export var variable_name: String
@export var value: Variant = true

func activate() -> void:
	if variable_name in GameData:
		GameData[variable_name] = value
	else:
		push_error("GameData does not have a variable named '%s'" % variable_name)
		return
