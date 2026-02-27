class_name SpecialBuilding extends Building

@export var specials: Array[Special] = []

func _building_finished() -> void:
    for special in specials:
        special.activate()
