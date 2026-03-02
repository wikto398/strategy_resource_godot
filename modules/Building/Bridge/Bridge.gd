class_name Bridge extends Building

func building_started(field: Field = null) -> void:
    field.walkable = true

func building_finished(field: Field = null) -> void:
    pass
