class_name ProductionHandler extends Node

@export var town_resources: Dictionary[Enums.TownResouce, float] = {
    Enums.TownResouce.WOOD: 0,
    Enums.TownResouce.STONE: 0,
    Enums.TownResouce.FOOD: 0,
    Enums.TownResouce.GOLD: 0
} 

var buildings: Array[Building] = []
var in_production: Array[Building] = [] 

func _process(delta: float) -> void:
    _process_building_production(delta)
    _process_resource_production(delta)

func can_afford(cost: Dictionary[Enums.TownResouce, int]) -> bool:
    for resource in cost.keys():
        if town_resources.get(resource, 0) < cost[resource]:
            return false
    return true

func start_production(building: Building) -> void:
    print("Starting production of building: ", building.name)
    for resource in building.build_cost.keys():
        town_resources[resource] -= building.build_cost[resource]
    in_production.append(building)

func _process_building_production(delta: float) -> void:
    for building in in_production:
        building.building_progress += delta
        if building.building_progress >= building.build_time:
            print("Finished production of building: ", building.name)
            buildings.append(building)
            in_production.erase(building)
            building.building_progress = 0.0

func _process_resource_production(delta: float) -> void:
    for building in buildings:
        town_resources[building.produced_resource] += building.production_rate * delta