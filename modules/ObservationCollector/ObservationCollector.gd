class_name ObservationCollector extends ObservationCollectorInterface

@export var field_grid: FieldGrid
@export var build_handler: BuildHandler
@export var production_handler: ProductionHandler

func _reward() -> float:
    return 0.0

func _observation() -> Array:
    return [
        field_grid.observation()
    ]

func _action_mask() -> Dictionary:
    var available_buildings = _available_buildings()
    var field_masks = _field_masks()
    return {"field_masks": field_masks, "available_buildings": available_buildings}

func _field_masks() -> Array:
    var field_masks = []
    for field in field_grid.fields.values():
        var current_field_building_masks = [0]
        for building in ResourceDatabase.buildings:
            if build_handler.can_build_on_field(field, building):
                current_field_building_masks.append(1)
            else:
                current_field_building_masks.append(0)
        field_masks.append(current_field_building_masks)
    return field_masks

func _available_buildings() -> Array:
    var available_buildings = [1]
    for building in ResourceDatabase.buildings:
        if production_handler.can_afford(building.build_cost):
            available_buildings.append(1)
        else:
            available_buildings.append(0)
    return available_buildings
