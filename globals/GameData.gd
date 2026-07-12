extends Node

signal population_changed()

const MAX_BUILDERS: int = 5

func observation() -> Array:
    return [
        Turn.turn,
        Turn.max_turns,
        population,
        working_population,
        max_builders,
        builder_speed_multiplier,
        builder_production_multiplier
    ]

var builder_speed_multiplier: int = 0
var builder_production_multiplier: int = 0
var max_builders: int = 3
var population: int = 0:
    set(value):
        population = value
        population_changed.emit()
var working_population: int = 0:
    set(value):
        working_population = value
        population_changed.emit()
