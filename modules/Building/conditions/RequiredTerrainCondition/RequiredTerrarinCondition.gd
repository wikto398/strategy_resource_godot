class_name RequiredTerrainCondition extends Condition

@export var required_terrain: Terrain.TerrainType = Terrain.TerrainType.GRASS

func _evaluate(data: Dictionary = {}) -> bool:
    var field: Field = data.get("field")
    if field:
        return field.terrain_type == required_terrain
    return false
