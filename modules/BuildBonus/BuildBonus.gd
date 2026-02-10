class_name BuildBonus extends Resource

enum BonusType {
    MULTIPLIER,
    FLAT
}

@export var terrain_type: Terrain.TerrainType
@export var nearby_terrain_type: Terrain.TerrainType
@export var nearby_building: Building
@export var bonus_amount: int = 0
@export var bonus_type: BonusType = BonusType.FLAT
@export var produced_resource: Enums.TownResource

func _check_bonus_conditions(field: Field, neighbors: Array[Field]) -> bool:
    if nearby_terrain_type != null and not _check_nearby_terrain(neighbors):
        return false
    if nearby_building != null and not _check_nearby_building(neighbors):
        return false
    return true

func _check_nearby_terrain(neighbors: Array[Field]) -> bool:
    for neighbor in neighbors:
        if neighbor.terrain_type == nearby_terrain_type:
            return true
    return false

func _check_nearby_building(neighbors: Array[Field]) -> bool:
    for neighbor in neighbors:
        if neighbor.building == nearby_building:
            return true
    return false
