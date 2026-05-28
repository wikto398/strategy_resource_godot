extends Control

@onready var turn_counter: Label = %TurnCounter
@onready var next_turn_button: Button = %NextTurnButton

func _ready() -> void:
	Turn.next_turn.connect(_on_next_turn)

func _on_next_turn() -> void:
	turn_counter.text = str(Turn.turn) + " / " + str(Turn.max_turns)
