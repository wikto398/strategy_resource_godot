@abstract
class_name Unit extends Node2D

signal unit_clicked(unit: Unit)

var field: Field:
    set(value):
        if field:
            field.unit = null
        field = value
        if field:
            global_position = field.global_position
            field.unit = self

func _ready() -> void:
    z_index = 100