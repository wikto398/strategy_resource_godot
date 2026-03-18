class_name PopulationUI extends Control

@onready var all_population_label: Label = $PanelContainer/MarginContainer/HBoxContainer/All
@onready var working_population_label: Label = $PanelContainer/MarginContainer/HBoxContainer/Working

func _ready() -> void:
	update_population_labels()
	GameData.population_changed.connect(_on_population_changed)

func update_population_labels() -> void:
	all_population_label.text = str(GameData.population)
	working_population_label.text = str(GameData.working_population)

func _on_population_changed() -> void:
	update_population_labels()

