class_name CityCenter extends HousingBuilding

signal city_center_built(field: Field)

func building_finished(field: Field = null) -> void:
    super.building_finished(field)
    DebugLogger.debug("City Center finished at " + str(field.grid_position))
    city_center_built.emit(field)
