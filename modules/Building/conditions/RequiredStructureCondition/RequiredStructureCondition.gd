class_name RequiredStructureCondition extends Condition

@export var required_structure: Structure

func _evaluate(data: Dictionary = {}) -> bool:
    var field: Field = data.get("field")
    if field:
        return field.structure == required_structure
    return false
