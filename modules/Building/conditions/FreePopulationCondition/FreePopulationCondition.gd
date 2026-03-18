class_name FreePopulationCondition extends Condition

func _evaluate(data: Dictionary = {}) -> bool:
    var population = GameData.population
    var working_population = GameData.working_population
    return population > working_population
