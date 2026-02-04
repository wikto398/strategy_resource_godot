class_name GameData extends Resource

@export var town_resources: Dictionary[Enums.TownResouce, int] = {
    Enums.TownResouce.WOOD: 0,
    Enums.TownResouce.STONE: 0,
    Enums.TownResouce.FOOD: 0,
    Enums.TownResouce.GOLD: 0
} 

@export var population: int = 1:
    set(value):
        population = max(value, 0)
@export_range(0, 100) var happiness: int = 0:
    set(value):
        happiness = clamp(value, 0, 100)
