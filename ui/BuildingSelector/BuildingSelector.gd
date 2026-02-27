class_name BuildingSelector extends Control

const BUILDING_ICON_SCENE: PackedScene = preload("uid://l5uuhltemx1j")

signal building_selected(building: Building)

@onready var buildings: HBoxContainer = %Buildings
@onready var main_foldable: FoldableContainer = $FoldableContainer

var foldables_by_town_resources: Dictionary[Enums.TownResource, FoldableContainer] = {}
var special_foldable: FoldableContainer

func _ready() -> void:
	_add_foldables_for_all_town_resources()
	_add_buildings_to_foldables()

func _add_foldables_for_all_town_resources() -> void:
	var children_foldable_group = FoldableGroup.new()
	children_foldable_group.allow_folding_all = true
	for town_resource in Enums.TownResource:
		var foldable = _add_foldable(town_resource)
		foldables_by_town_resources[Enums.TownResource[town_resource]] = foldable
		foldable.foldable_group = children_foldable_group

	special_foldable = _add_foldable("SPECIAL")
	special_foldable.foldable_group = children_foldable_group

func _add_foldable(town_resource: String) -> FoldableContainer:
	var foldable = FoldableContainer.new()
	foldable.title = str(town_resource)
	foldable.title_position = FoldableContainer.TitlePosition.POSITION_BOTTOM
	foldable.folded = true
	buildings.add_child(foldable)
	return foldable

func _add_buildings_to_foldables() -> void:
	var buildings_list = ResourceDatabase.load_buildings()
	for building in buildings_list:
		var building_icon = BUILDING_ICON_SCENE.instantiate() as BuildingIcon
		building_icon.data = building
		if building is ProductionBuilding:
			_add_production_building_to_foldable(building)
		else:
			_add_special_building_to_foldable(building)

func _on_building_icon_clicked(building: Building) -> void:
	main_foldable.folded = true
	_set_children_folded_state(true)
	building_selected.emit(building)

func _set_children_folded_state(folded: bool) -> void:
	for child in buildings.get_children():
		if child is FoldableContainer:
			child.folded = folded

func _add_production_building_to_foldable(building: ProductionBuilding) -> void:
	var building_icon = BUILDING_ICON_SCENE.instantiate() as BuildingIcon
	building_icon.data = building
	if foldables_by_town_resources.has(building.produced_resource):
		foldables_by_town_resources[building.produced_resource].add_child(building_icon)
		building_icon.clicked.connect(_on_building_icon_clicked)
	else:
		push_error("No foldable found for building's produced resource: " + str(building.produced_resource))

func _add_special_building_to_foldable(building: Building) -> void:
	var building_icon = BUILDING_ICON_SCENE.instantiate() as BuildingIcon
	building_icon.data = building
	special_foldable.add_child(building_icon)
	building_icon.clicked.connect(_on_building_icon_clicked)
