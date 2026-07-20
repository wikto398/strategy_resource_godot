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
@export var max_deficit_duration: int = 10

var current_production: Dictionary[Enums.TownResource, int] = {
	Enums.TownResource.WOOD: 0,
	Enums.TownResource.STONE: 0,
	Enums.TownResource.FOOD: 0,
	Enums.TownResource.GOLD: 0
}

var last_production: Dictionary[Enums.TownResource, int] = {
	Enums.TownResource.WOOD: 0,
	Enums.TownResource.STONE: 0,
	Enums.TownResource.FOOD: 0,
	Enums.TownResource.GOLD: 0
}

var current_deficit_duration: Dictionary[Enums.TownResource, int] = {
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
	DebugLogger.debug("Starting production of building: " + building.name)
	for resource in building.build_cost.keys():
		town_resources[resource] -= building.build_cost[resource]
	building.building_started(field)
	field.in_progress_building = building
	resources_updated.emit(town_resources)
	field.building_finished.connect(_on_building_finished)
	if building.build_time == 0:
		field.finish_building()
	elif field.unit is Builder:
		field.unit.state_machine.change_state("building")

func setup():
	resources_updated.emit(town_resources)
	production_updated.emit(current_production)
	Turn.next_turn.connect(_on_next_turn)

func _on_building_finished(field: Field) -> void:
	var in_progress_building = field.in_progress_building
	if in_progress_building:
		if in_progress_building is ProductionBuilding:
			_on_production_building_finished(in_progress_building, field)
		_update_upkeep_costs(in_progress_building.upkeep_cost)
		field.building = in_progress_building
		field.in_progress_building = null
		production_updated.emit(current_production)
		field.building_finished.disconnect(_on_building_finished)
	else:
		DebugLogger.warning("No in_progress_building in progress to finish at field: " + str(field.grid_position))

func _on_next_turn() -> void:
	for resource in current_production.keys():
		town_resources[resource] = min(town_resources[resource] + current_production[resource], max_capacity)
		_update_current_deficit_duration(resource)
	resources_updated.emit(town_resources)

func _on_production_building_finished(building: ProductionBuilding, field: Field) -> void:
	var production_increase = building.production_rate - field.building.production_rate if field.building else building.production_rate
	current_production[building.produced_resource] += production_increase

func _update_current_deficit_duration(resource: Enums.TownResource) -> void:
	if town_resources[resource] <= 0 and current_production[resource] <= 0:
		DebugLogger.warning("Resource " + str(resource) + " is in deficit! Current amount: " + str(town_resources[resource]) + " Production: " + str(current_production[resource]))
		current_deficit_duration[resource] += 1
		# Global.add_to_reward.emit(-0.2)
	else:
		current_deficit_duration[resource] = 0
		return

	if current_deficit_duration[resource] >= max_deficit_duration:
		DebugLogger.error("Resource " + str(resource) + " has been in deficit for too long!")
		Global.game_lost.emit()

func _update_upkeep_costs(upkeep_change: Dictionary[Enums.TownResource, int]) -> void:
	for resource in upkeep_change.keys():
		current_production[resource] -= upkeep_change[resource]
	production_updated.emit(current_production)
