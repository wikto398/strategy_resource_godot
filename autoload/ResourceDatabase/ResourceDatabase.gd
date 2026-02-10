extends Node

const BUILDING_PATH = "res://resources/buildings/production/"

func load_buildings() -> Array[Building]:
	var buildings: Array[Building] = []
	for building_resource_type in DirAccess.get_directories_at(BUILDING_PATH):
		var building_resource_dir = BUILDING_PATH + building_resource_type + "/"
		for building_resource_file in DirAccess.get_files_at(building_resource_dir):
			if building_resource_file.ends_with(".tres"):
				var building_resource = ResourceLoader.load(building_resource_dir + building_resource_file)
				if building_resource and building_resource is Building:
					buildings.append(building_resource)
					print("Loaded building: ", building_resource.name)
				else:
					push_error("Failed to load building resource: " + building_resource_dir + building_resource_file)
	return buildings
