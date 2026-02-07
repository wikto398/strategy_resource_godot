class_name ResourceIcon extends Icon 

@onready var icon_texture: TextureRect = $MarginContainer/HBoxContainer/TextureRect
@onready var amount_label: Label = $MarginContainer/HBoxContainer/Amount
@onready var current_production_label: Label = $MarginContainer/HBoxContainer/CurrentProduction

@export var resource_type: Enums.TownResource = Enums.TownResource.WOOD:
	set(value):
		resource_type = value
		if icon_texture:
			icon_texture.texture = Icons.resource_icons.get(resource_type, null)
@export var amount: int = 0:
	set(value):
		amount = value
		if amount_label:
			amount_label.text = str(amount)
@export var current_production: int = 0:
	set(value):
		current_production = value
		_set_current_production_label()
@export var include_current_production: bool = false:
	set(value):
		include_current_production = value
		if current_production_label:
			current_production_label.visible = include_current_production
			_set_current_production_label()

func _ready() -> void:
	icon_texture.texture = Icons.resource_icons.get(resource_type, null)
	amount_label.text = str(amount)
	_set_current_production_label()

func initialization(_resource_type: Enums.TownResource, _amount: int) -> void:
	resource_type = _resource_type
	amount = _amount

func _set_current_production_label() -> void:
	if not include_current_production:
		return
	var str_value = str(current_production)
	if current_production > 0:
		str_value = "+" + str_value
	elif current_production < 0:
		str_value = "-" + str_value
	current_production_label.text = str_value

func get_data():
	return {
		"resource_type": resource_type,
		"amount": amount,
		"current_production": current_production,
		"include_current_production": include_current_production
	}