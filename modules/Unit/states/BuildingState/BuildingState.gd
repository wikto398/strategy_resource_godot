class_name BuildingState extends State

func enter(_user: Node) -> void:
    print("{unit} has entered BuildingState.".format({unit = _user.name}))

func exit(_user: Node) -> void:
    print("{unit} is exiting BuildingState.".format({unit = _user.name}))

func update(_delta: float, _user: Node) -> void:
    for dummy in range(1 + GameData.builder_production_multiplier):
        if _user.field.in_progress_building:
            print("{unit} is currently building on {field}.".format({unit = _user.name, field = _user.field.grid_position}))
            if _user.field.in_progress_building.build():
                _user.field.finish_building()
                change_state.emit("idle")
        else:
            print("{unit} has no building to work on.".format({unit = _user.name}))
