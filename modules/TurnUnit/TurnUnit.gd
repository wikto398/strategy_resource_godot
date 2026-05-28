class_name TurnUnit extends StateMachineUnit

func _setup() -> void:
    state_machine.setup(Turn.next_turn)
