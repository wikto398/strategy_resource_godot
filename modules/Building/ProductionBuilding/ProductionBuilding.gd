class_name ProductionBuilding extends Building

@export var produced_resource: Enums.TownResource
@export var production_rate: int = 1

func building_finished(field: Field = null) -> void:
	GameData.working_population += 1
	var reward_value = production_rate * 0.3
	DebugLogger.debug("Adding reward for production building " + name + " finished: " + str(reward_value))
	Global.add_to_reward.emit(reward_value, "build_finish")

func building_started(field: Field = null) -> void:
	pass
