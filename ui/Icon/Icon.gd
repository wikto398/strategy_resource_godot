@abstract
class_name Icon extends PanelContainer 

signal clicked(data: Resource)

var data: Resource = null

func _ready() -> void:
    gui_input.connect(_on_gui_input)

@abstract func get_data()

func _on_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            print("Icon clicked: ", self)
            clicked.emit(data)