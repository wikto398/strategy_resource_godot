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

var buildings: Array[Building] = []
var in_production: Dictionary[Field, Building] = {} 

func can_afford(cost: Dictionary[Enums.TownResource, int]) -> bool:
	for resource in cost.keys():
		if town_resources.get(resource, 0) < cost[resource]:
			return false
	return true

func start_production(building: Building, field: Field) -> void:
	print("Starting production of building: ", building.name)
	for resource in building.build_cost.keys():
		town_resources[resource] -= building.build_cost[resource]
	in_production[field] = building
	resources_updated.emit(town_resources)

func _process_building_production() -> void:
	for field in in_production:
		var building: Building = in_production[field]
		if not field.unit or not field.unit is Builder:
			print("No builder assigned to field at ", field.grid_position, " for building ", building.name)
			continue
		print("Processing production for building: ", building.name, " at field: ", field.grid_position, " - Progress: ", building.building_progress, "/", building.build_time)
		building.building_progress += 1
		if building.building_progress >= building.build_time:
			_building_finished(building, field)

func _process_resource_production() -> void:
	for resource in current_production:
		town_resources[resource] = clamp(
			town_resources[resource] + current_production[resource],
			0.0,
			max_capacity
		)
	resources_updated.emit(town_resources)

func _building_finished(building: Building, field: Field) -> void:
	print("Building finished: ", building.name, " at field: ", field.grid_position)
	buildings.append(building)
	in_production.erase(field)
	building.building_progress = 0.0
	resources_updated.emit(town_resources)
	_update_production()

func _update_production() -> void:
	current_production.clear()
	for resource in Enums.TownResource.values():
		current_production[resource] = 0
	for building in buildings:
		current_production[building.produced_resource] += building.production_rate
	production_updated.emit(current_production)

func _on_next_turn() -> void:
	_process_resource_production()
	_process_building_production()

func setup():
	Turn.next_turn.connect(_on_next_turn)
	resources_updated.emit(town_resources)
	production_updated.emit(current_production)
