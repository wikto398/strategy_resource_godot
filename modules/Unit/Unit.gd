@abstract
class_name Unit extends Node2D

signal unit_clicked(unit: Unit)

@onready var state_machine: StateMachine = $StateMachine

var field: Field:
	set(value):
		if field:
			field.unit = null
		field = value
		if field:
			global_position = field.global_position
			field.unit = self
var target_position: Field = null:
	set(value):
		target_position = value

func _ready() -> void:
	z_index = 100
