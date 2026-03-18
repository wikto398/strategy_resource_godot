extends Node

signal population_changed()

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

