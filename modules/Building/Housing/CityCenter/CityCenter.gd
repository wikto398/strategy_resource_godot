class_name CityCenter extends HousingBuilding

signal city_center_built(field: Field)

func building_finished(field: Field = null) -> void:
    print("City Center finished at ", field.grid_position)
    GameData.population += 3
    city_center_built.emit(field)
