@tool
extends EditorPlugin

const TERRAIN_SCRIPT := preload("res://addons/foundation/terrain/terrain_chunk_manager.gd")
const TERRAIN_DOCK_SCRIPT := preload("res://addons/foundation/editor/terrain_editor_dock.gd")
const WORLD_SCRIPT := preload("res://addons/foundation/world/foundation_world.gd")
const DEBUG_VIEW_SCRIPT := preload("res://addons/foundation/debug/debug_view.gd")
const DEBUG_DOCK_SCRIPT := preload("res://addons/foundation/editor/debug_editor_dock.gd")
const AUTHORING_DOCK_SCRIPT := preload("res://addons/foundation/editor/authoring_editor_dock.gd")

var _terrain_dock: FoundationTerrainEditorDock
var _debug_dock: FoundationDebugEditorDock
var _authoring_dock: FoundationAuthoringEditorDock


func _enter_tree() -> void:
	add_custom_type("FoundationTerrain", "Node3D", TERRAIN_SCRIPT, null)
	add_custom_type("FoundationWorld", "Node3D", WORLD_SCRIPT, null)
	add_custom_type("FoundationDebugView", "Node3D", DEBUG_VIEW_SCRIPT, null)
	_terrain_dock = TERRAIN_DOCK_SCRIPT.new()
	_terrain_dock.initialize(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _terrain_dock)
	_debug_dock = DEBUG_DOCK_SCRIPT.new()
	_debug_dock.initialize(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _debug_dock)
	_authoring_dock = AUTHORING_DOCK_SCRIPT.new()
	_authoring_dock.initialize(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _authoring_dock)


func _exit_tree() -> void:
	remove_custom_type("FoundationTerrain")
	remove_custom_type("FoundationWorld")
	remove_custom_type("FoundationDebugView")
	if is_instance_valid(_terrain_dock):
		_terrain_dock.shutdown()
		remove_control_from_docks(_terrain_dock)
		_terrain_dock.queue_free()
	if is_instance_valid(_debug_dock):
		_debug_dock.shutdown()
		remove_control_from_docks(_debug_dock)
		_debug_dock.queue_free()
	if is_instance_valid(_authoring_dock):
		_authoring_dock.shutdown()
		remove_control_from_docks(_authoring_dock)
		_authoring_dock.queue_free()
