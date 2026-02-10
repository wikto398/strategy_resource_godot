class_name ProductionHandler extends Node

signal resources_updated(town_resources: Dictionary[Enums.TownResource, int])
signal production_updated(current_production: Dictionary[Enums.TownResource, int])

@export var town_resources: Dictionary[Enums.TownResource, int] = {
	Enums.TownResource.WOOD: 100,
	Enums.TownResource.STONE: 100,
	Enums.TownResource.FOOD: 100,
	Enums.TownResource.GOLD: 100
}
@export var max_capacity: int = 10000

var current_production: Dictionary[Enums.TownResource, int] = {
	Enums.TownResource.WOOD: 0,
	Enums.TownResource.STONE: 0,
	Enums.TownResource.FOOD: 0,
	Enums.TownResource.GOLD: 0
}

func can_afford(cost: Dictionary[Enums.TownResource, int]) -> bool:
	for resource in cost.keys():
		if town_resources.get(resource, 0) < cost[resource]:
			return false
	return true

func start_production(building: Building, field: Field) -> void:
	print("Starting production of building: ", building.name)
	for resource in building.build_cost.keys():
		town_resources[resource] -= building.build_cost[resource]
	field.in_progress_building = building
	if field.unit is Builder:
		field.unit.state_machine.change_state("building")
	resources_updated.emit(town_resources)
	field.building_finished.connect(_on_building_finished)

func setup():
	resources_updated.emit(town_resources)
	production_updated.emit(current_production)

func _on_building_finished(field: Field) -> void:
	var in_progress_building = field.in_progress_building
	if in_progress_building:
		var production_increase = in_progress_building.production_rate - field.building.production_rate if field.building else in_progress_building.production_rate
		var upkeep_increase = in_progress_building.upkeep_cost - field.building.upkeep_cost if field.building else in_progress_building.upkeep_cost
		in_progress_building.resource_produced.connect(_on_building_resource_produced)
		current_production[in_progress_building.produced_resource] += production_increase
		current_production[Enums.TownResource.GOLD] -= upkeep_increase
		field.building = in_progress_building
		field.in_progress_building = null
		production_updated.emit(current_production)
		field.building_finished.disconnect(_on_building_finished)
	else:
		print("No in_progress_building in progress to finish at field: ", field.grid_position)

func _on_building_resource_produced(resource: Enums.TownResource, amount: int) -> void:
	town_resources[resource] = clamp(
		town_resources[resource] + amount,
		0.0,
		max_capacity
	)
	resources_updated.emit(town_resources)
