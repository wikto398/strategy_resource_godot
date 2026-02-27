class_name ProductionBuilding extends Building

@export var produced_resource: Enums.TownResource
@export var production_rate: int = 1

func _building_finished() -> void:
    pass
