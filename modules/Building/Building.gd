class_name Building extends Resource

@export var name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var produced_resource: Enums.TownResource
@export var production_rate: int = 1
@export var upkeep_cost: int = 0
@export var build_cost: Dictionary[Enums.TownResource, int] = {
    Enums.TownResource.WOOD: 0,
    Enums.TownResource.STONE: 0,
    Enums.TownResource.FOOD: 0,
    Enums.TownResource.GOLD: 0
}
@export var build_time: float = 5.0
@export var building_progress: float = 0.0
@export var required_terrain: Terrain.TerrainType = Terrain.TerrainType.GRASS
@export var required_nearby_terrain: Array[Terrain.TerrainType] = []
@export var required_nearby_buildings: Array[Building] = []
@export var grid_location: Vector2i = Vector2i.ZERO
@export var current_level: int = 1 
@export var max_level: int = 3
@export var upgrade_costs: Dictionary[Enums.TownResource, int] = {
    Enums.TownResource.WOOD: 0,
    Enums.TownResource.STONE: 0,
    Enums.TownResource.FOOD: 0,
    Enums.TownResource.GOLD: 0
}