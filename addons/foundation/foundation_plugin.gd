@tool
extends EditorPlugin

const TERRAIN_SCRIPT := preload("res://addons/foundation/terrain/terrain_chunk_manager.gd")
const TERRAIN_DOCK_SCRIPT := preload("res://addons/foundation/editor/terrain_editor_dock.gd")

var _dock: FoundationTerrainEditorDock


func _enter_tree() -> void:
	add_custom_type("FoundationTerrain", "Node3D", TERRAIN_SCRIPT, null)
	_dock = TERRAIN_DOCK_SCRIPT.new()
	_dock.initialize(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	remove_custom_type("FoundationTerrain")
	if is_instance_valid(_dock):
		_dock.shutdown()
		remove_control_from_docks(_dock)
		_dock.queue_free()
