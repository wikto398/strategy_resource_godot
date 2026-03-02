class_name HousingBuilding extends Building

func building_finished(field: Field = null) -> void:
    print("Housing building finished at ", field.grid_position)
    GameData.population += 1

func building_started(field: Field = null) -> void:
    pass
