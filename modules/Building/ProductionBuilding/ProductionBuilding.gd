class_name ProductionBuilding extends Building

@export var produced_resource: Enums.TownResource
@export var production_rate: int = 1

func building_finished(field: Field = null) -> void:
	GameData.working_population += 1

func building_started(field: Field = null) -> void:
	pass
