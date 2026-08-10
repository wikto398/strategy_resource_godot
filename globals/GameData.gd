extends Node

signal population_changed()
signal builder_added()

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
var builders_walk_on_water: bool = false
var current_builders: int = 3:
    set(value):
        if value < 0:
            push_error("current_builders cannot be negative. Attempted to set to %d" % value)
            return
        if value > MAX_BUILDERS:
            push_error("current_builders cannot exceed MAX_BUILDERS (%d). Attempted to set to %d" % [MAX_BUILDERS, value])
            return
        if value > current_builders:
            builder_added.emit()
        current_builders = value
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
    builders_walk_on_water = false
