@tool
extends EditorPlugin

const Dock = preload("res://addons/annotated_screenshot/dock.gd")

var _dock: Control


func _enter_tree() -> void:
    _dock = Dock.new()
    _dock.name = "Annotated Screenshot"
    _dock.current_screen = "3D"
    add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
    main_screen_changed.connect(_on_main_screen_changed)
    scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
    if main_screen_changed.is_connected(_on_main_screen_changed):
        main_screen_changed.disconnect(_on_main_screen_changed)
    if scene_changed.is_connected(_on_scene_changed):
        scene_changed.disconnect(_on_scene_changed)
    remove_control_from_docks(_dock)
    _dock.queue_free()


func _on_main_screen_changed(screen_name: String) -> void:
    _dock.current_screen = screen_name


func _on_scene_changed(_scene_root: Node) -> void:
    _dock.refresh_nodes()
