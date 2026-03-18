@abstract
class_name Building extends Resource

signal remove_from_selector(building: Building)

@export var name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var wip_icon: Texture2D
@export var upkeep_cost: Dictionary[Enums.TownResource, int] = {
	Enums.TownResource.WOOD: 0,
	Enums.TownResource.STONE: 0,
	Enums.TownResource.FOOD: 0,
	Enums.TownResource.GOLD: 0
}
@export var build_cost: Dictionary[Enums.TownResource, int] = {
	Enums.TownResource.WOOD: 0,
	Enums.TownResource.STONE: 0,
	Enums.TownResource.FOOD: 0,
	Enums.TownResource.GOLD: 0
}
@export var build_time: int = 5
@export var building_progress: int = 0
@export var conditions: Array[Condition] = []
@export var unique: bool = false

func build() -> bool:
	if GameData.population <= GameData.working_population:
		DebugLogger.trace("Not enough free population to continue building " + name)
		return false
	if building_progress < build_time:
		building_progress += 1
		DebugLogger.trace("Building {name}: {progress}/{total} progress.".format({name = name, progress = building_progress, total = build_time}))
		if building_progress >= build_time:
			return true
	else:
		DebugLogger.trace("{name} is fully built and operational.".format({name = name}))
	return false

@abstract func building_finished(field: Field = null) -> void
@abstract func building_started(field: Field = null) -> void

func validate_conditions(data: Dictionary = {}) -> bool:
	data["building"] = self
	for condition in conditions:
		if not condition.evaluate(data):
			return false
	return true

func remove_unique_building_from_selector():
	if unique:
		remove_from_selector.emit(self)
