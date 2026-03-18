class_name ProductionUI extends Control

@onready var production_container: HBoxContainer = $PanelContainer/MarginContainer/ProductionContainer

var resource_icons: Dictionary[Enums.TownResource, ResourceIcon] = {}

var RESOURCE_ICON_SCENE: PackedScene = preload("uid://x4hnh42jglv4")

func _ready() -> void:
	for resource in Enums.TownResource.values():
		var resource_icon = RESOURCE_ICON_SCENE.instantiate() as ResourceIcon
		resource_icon.initialization(resource, 0)
		production_container.add_child(resource_icon)
		resource_icons[resource] = resource_icon
		var separator = VSeparator.new()
		production_container.add_child(separator)
	if production_container.get_child_count() > 0:
		var last_child = production_container.get_child(production_container.get_child_count() - 1)
		if last_child is VSeparator:
			production_container.remove_child(last_child)
			last_child.queue_free()

func _on_update_resources(town_resources: Dictionary[Enums.TownResource, int]) -> void:
	for resource in town_resources.keys():
		if resource_icons.has(resource):
			resource_icons[resource].amount = int(town_resources[resource])

func _on_update_production(current_production: Dictionary[Enums.TownResource, int]) -> void:
	DebugLogger.debug("Updating production UI with current production: {production}".format({production = current_production}))
	for resource in current_production.keys():
		if resource_icons.has(resource):
			resource_icons[resource].current_production = current_production[resource]
