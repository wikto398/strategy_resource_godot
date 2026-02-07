class_name GameData extends Resource

@export var town_resources: Dictionary[Enums.TownResource, int] = {
    Enums.TownResource.WOOD: 0,
    Enums.TownResource.STONE: 0,
    Enums.TownResource.FOOD: 0,
    Enums.TownResource.GOLD: 0
} 

@export var population: int = 1:
    set(value):
        population = max(value, 0)
@export_range(0, 100) var happiness: int = 0:
    set(value):
        happiness = clamp(value, 0, 100)
