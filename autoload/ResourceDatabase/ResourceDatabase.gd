extends Node

const BUILDING_PATH = "res://resources/buildings/"
const STRUCTURE_PATH = "res://resources/structures/"

var buildings: Array[Building] = []
var structures: Array[Structure] = []

func load_buildings() -> Array[Building]:
	if buildings.size() > 0:
		return buildings
	for building in _get_all_building_resources_from_path(BUILDING_PATH, true):
		if building is Building:
			buildings.append(building)
		else:
			push_warning("Resource at " + building.resource_path + " is not a Building.")
	return buildings

func load_structures() -> Array[Structure]:
	if structures.size() > 0:
		return structures
	for structure in _get_all_building_resources_from_path(STRUCTURE_PATH, true):
		if structure is Structure:
			structures.append(structure)
		else:
			push_warning("Resource at " + structure.resource_path + " is not a Structure.")
	return structures

func _get_all_building_resources_from_path(path: String, recursive: bool = false) -> Array[Resource]:
	var resources: Array[Resource] = []
	if DirAccess.dir_exists_absolute(path):
		for file in DirAccess.get_files_at(path):
			if file.ends_with(".tres"):
				var resource = ResourceLoader.load(path + "/" + file)
				if resource:
					resources.append(resource)
				else:
					push_error("Failed to load resource: " + path + "/" + file)
		if recursive:
			for dir in DirAccess.get_directories_at(path):
				resources.append_array(_get_all_building_resources_from_path(path + "/" + dir, true))
	return resources
