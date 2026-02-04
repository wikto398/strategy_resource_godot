class_name ProductionUI extends Control

@onready var production_container: HBoxContainer = $ProductionContainer

var RESOURCE_ICON_SCENE: PackedScene = preload("res://ui/ResourceIcon/ResourceIcon.tscn") 

func _ready() -> void:
    for resource in Enums.TownResouce.values():
        var resource_icon = RESOURCE_ICON_SCENE.instantiate() as ResourceIcon
        resource_icon.initialization(resource, 0)
        production_container.add_child(resource_icon)
        var separator = VSeparator.new()
        production_container.add_child(separator)
    if production_container.get_child_count() > 0:
        var last_child = production_container.get_child(production_container.get_child_count() - 1)
        if last_child is VSeparator:
            production_container.remove_child(last_child)
            last_child.queue_free()