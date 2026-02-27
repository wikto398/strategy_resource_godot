extends Node

const BUILDING_PATH = "res://resources/buildings/"

func load_buildings() -> Array[Building]:
	var buildings: Array[Building] = []
	for building in _get_all_building_resources_from_path(BUILDING_PATH, true):
		if building is Building:
			buildings.append(building)
		else:
			push_warning("Resource at " + building.resource_path + " is not a Building.")
	return buildings

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
