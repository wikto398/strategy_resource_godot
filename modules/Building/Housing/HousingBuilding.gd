class_name HousingBuilding extends Building

@export var population_increase: int = 1

func building_finished(field: Field = null) -> void:
    if GameData.working_population >= GameData.population:
        var reward_value = 0.2 * population_increase
        DebugLogger.debug("Adding reward for housing building " + name + " finished: " + str(reward_value))
        Global.add_to_reward.emit(reward_value, "events")
    GameData.population += population_increase

func building_started(field: Field = null) -> void:
    pass
