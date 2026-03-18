class_name HousingBuilding extends Building

@export var population_increase: int = 1

func building_finished(field: Field = null) -> void:
    GameData.population += population_increase

func building_started(field: Field = null) -> void:
    pass
