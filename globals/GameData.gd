extends Node

signal population_changed()

const MAX_BUILDERS: int = 5

func observation() -> Array:
    return [
        Turn.turn,
        Turn.max_turns,
        population,
        working_population,
        current_builders,
        builder_speed_multiplier,
        builder_production_multiplier
    ]

var builder_speed_multiplier: int = 0
var builder_production_multiplier: int = 0
var current_builders: int = 3
var population: int = 0:
    set(value):
        population = value
        population_changed.emit()
var working_population: int = 0:
    set(value):
        working_population = value
        population_changed.emit()

func reset() -> void:
    population = 0
    working_population = 0
    current_builders = 3
    builder_speed_multiplier = 0
    builder_production_multiplier = 0
