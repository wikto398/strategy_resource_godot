class_name Idle extends State

func enter(_user: Node) -> void:
    print("{name} entered Idle state.".format({"name": _user.name}))

func exit(_user: Node) -> void:
    print("{name} exiting Idle state.".format({"name": _user.name}))

func update(_delta: float, _user: Node) -> void:
    print("{name} is idling.".format({"name": _user.name}))
    if _user.field.in_progress_building:
        print("{name} has a building to work on at {field}.".format({"name": _user.name, "field": _user.field.grid_position}))
        change_state.emit("building")
