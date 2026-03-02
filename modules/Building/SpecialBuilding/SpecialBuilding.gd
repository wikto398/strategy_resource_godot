class_name SpecialBuilding extends Building

@export var specials: Array[Special] = []

func building_finished(field: Field = null) -> void:
    for special in specials:
        special.activate()

func building_started(field: Field = null) -> void:
    pass
