class_name HousingBuilding extends Building

@export var population_increase: int = 1

func building_finished(field: Field = null) -> void:
    GameData.population += population_increase
    # Global.add_to_reward.emit(population_increase * 0.1)

func building_started(field: Field = null) -> void:
    pass
