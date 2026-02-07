class_name BuildingIcon extends Icon

@onready var icon: TextureRect = $MarginContainer/TextureRect

func _ready() -> void:
	super._ready()
	if data:
		icon.texture = data.icon

func get_data():
	return {
		# Add building-specific data here when needed
	}
