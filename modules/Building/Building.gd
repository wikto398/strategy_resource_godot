@abstract
class_name Building extends Resource


@export var name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var wip_icon: Texture2D
@export var upkeep_cost: Dictionary[Enums.TownResource, int] = {
    Enums.TownResource.WOOD: 0,
    Enums.TownResource.STONE: 0,
    Enums.TownResource.FOOD: 0,
    Enums.TownResource.GOLD: 0
}
@export var build_cost: Dictionary[Enums.TownResource, int] = {
    Enums.TownResource.WOOD: 0,
    Enums.TownResource.STONE: 0,
    Enums.TownResource.FOOD: 0,
    Enums.TownResource.GOLD: 0
}
@export var build_time: int = 5
@export var building_progress: int = 0
@export var required_terrain: Terrain.TerrainType = Terrain.TerrainType.GRASS
@export var required_nearby_terrain: Array[Terrain.TerrainType] = []
@export var required_nearby_buildings: Array[Building] = []
@export var unique: bool = false

func build() -> bool:
    if building_progress < build_time:
        building_progress += 1
        print("Building {name}: {progress}/{total} progress.".format({name = name, progress = building_progress, total = build_time}))
        if building_progress >= build_time:
            _building_finished()
            return true
    else:
        print("{name} is fully built and operational.".format({name = name}))
    return false

@abstract func _building_finished() -> void
