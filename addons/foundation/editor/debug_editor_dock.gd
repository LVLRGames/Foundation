@tool
class_name FoundationDebugEditorDock
extends ScrollContainer

## Editor controls affect only disposable debug presentation, never world generation.

var _editor_interface: EditorInterface
var _content: VBoxContainer
var _view: FoundationDebugView
var _status: Label
var _global_toggle: CheckBox
var _follow_selection: CheckBox
var _selection_options: OptionButton
var _selection_details: Label
var _layer_toggles: Dictionary = {}


func initialize(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	if is_node_ready():
		_connect_selection()


func _ready() -> void:
	name = "Foundation Debug"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
	_build_interface()
	_connect_selection()
	_editor_selection_changed()


func shutdown() -> void:
	if _editor_interface == null:
		return
	var selection := _editor_interface.get_selection()
	if selection.selection_changed.is_connected(_editor_selection_changed):
		selection.selection_changed.disconnect(_editor_selection_changed)


func _build_interface() -> void:
	var heading := Label.new()
	heading.text = "Foundation Debug View"
	heading.add_theme_font_size_override("font_size", 18)
	_content.add_child(heading)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)

	_global_toggle = CheckBox.new()
	_global_toggle.text = "Debug rendering enabled"
	_global_toggle.toggled.connect(_global_toggled)
	_content.add_child(_global_toggle)

	for layer_data in [
		[&"world_bounds", "World bounds"],
		[&"regions", "Regions and IDs"],
		[&"chunks", "Chunks and dirty state"],
		[&"terrain_grid", "Terrain cell grid"],
		[&"records", "Spatial records"],
		[&"anchors", "City anchor markers and IDs"],
		[&"road_topology", "Road topology, hierarchy, and logical identity"],
		[&"road_costs", "Terrain routing-cost heatmap"],
		[&"road_candidates", "Accepted and rejected anchor candidates"],
		[&"road_validation", "Grading and topology validation warnings"],
		[&"blocks", "Block outlines, fills, metrics, and diagnostics"],
		[&"relationships", "Parent/child relationships"],
	]:
		var toggle := CheckBox.new()
		toggle.text = layer_data[1]
		toggle.toggled.connect(_layer_toggled.bind(layer_data[0]))
		_layer_toggles[layer_data[0]] = toggle
		_content.add_child(toggle)

	_follow_selection = CheckBox.new()
	_follow_selection.text = "Follow editor selection"
	_follow_selection.button_pressed = true
	_content.add_child(_follow_selection)

	var selection_label := Label.new()
	selection_label.text = "Debug selection"
	_content.add_child(selection_label)
	_selection_options = OptionButton.new()
	_selection_options.item_selected.connect(_debug_selection_changed)
	_content.add_child(_selection_options)

	_selection_details = Label.new()
	_selection_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_selection_details)

	var rebuild_button := Button.new()
	rebuild_button.text = "Rebuild Debug Display"
	rebuild_button.pressed.connect(_rebuild_pressed)
	_content.add_child(rebuild_button)


func _connect_selection() -> void:
	if _editor_interface == null:
		return
	var selection := _editor_interface.get_selection()
	if not selection.selection_changed.is_connected(_editor_selection_changed):
		selection.selection_changed.connect(_editor_selection_changed)


func _editor_selection_changed() -> void:
	if _editor_interface == null or (_follow_selection != null and not _follow_selection.button_pressed):
		return
	_view = null
	for node in _editor_interface.get_selection().get_selected_nodes():
		if node is FoundationDebugView:
			_view = node
			break
		if node is FoundationWorld:
			for child in node.get_children():
				if child is FoundationDebugView:
					_view = child
					break
	if _view == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node."
		_selection_options.clear()
		return
	_sync_from_view()


func _sync_from_view() -> void:
	_global_toggle.button_pressed = _view.debug_enabled
	_layer_toggles[&"world_bounds"].button_pressed = _view.show_world_bounds
	_layer_toggles[&"regions"].button_pressed = _view.show_regions
	_layer_toggles[&"chunks"].button_pressed = _view.show_chunks
	_layer_toggles[&"terrain_grid"].button_pressed = _view.show_terrain_grid
	_layer_toggles[&"records"].button_pressed = _view.show_records
	_layer_toggles[&"anchors"].button_pressed = _view.show_anchors
	_layer_toggles[&"road_topology"].button_pressed = _view.show_road_topology
	_layer_toggles[&"road_costs"].button_pressed = _view.show_road_costs
	_layer_toggles[&"road_candidates"].button_pressed = _view.show_road_candidates
	_layer_toggles[&"road_validation"].button_pressed = _view.show_road_validation
	_layer_toggles[&"blocks"].button_pressed = _view.show_blocks
	_layer_toggles[&"relationships"].button_pressed = _view.show_relationships
	_status.text = "Editing %s. Visibility changes never regenerate world data." % _view.name
	_populate_selection_options()


func _populate_selection_options() -> void:
	_selection_options.clear()
	var world_node := _view.get_node_or_null(_view.world_path) as FoundationWorld
	if world_node == null:
		return
	if world_node.world_data == null:
		world_node.initialize_world()
	_selection_options.add_item("World")
	_selection_options.set_item_metadata(0, {"kind": "world"})
	for chunk in world_node.world_data.get_sorted_chunks():
		_selection_options.add_item("Chunk %d, %d" % [chunk.coordinate.x, chunk.coordinate.y])
		_selection_options.set_item_metadata(
			_selection_options.item_count - 1,
			{"kind": "chunk", "coordinate": chunk.coordinate}
		)
	for record in world_node.world_data.spatial_index.get_all_records():
		_selection_options.add_item(String(record.stable_id))
		_selection_options.set_item_metadata(
			_selection_options.item_count - 1,
			{"kind": "record", "stable_id": record.stable_id}
		)
	_debug_selection_changed(0)


func _global_toggled(value: bool) -> void:
	if _view != null:
		_view.set_debug_enabled(value)


func _layer_toggled(value: bool, layer_id: StringName) -> void:
	if _view == null:
		return
	match layer_id:
		&"world_bounds": _view.show_world_bounds = value
		&"regions": _view.show_regions = value
		&"chunks": _view.show_chunks = value
		&"terrain_grid": _view.show_terrain_grid = value
		&"records": _view.show_records = value
		&"anchors": _view.show_anchors = value
		&"road_topology": _view.show_road_topology = value
		&"road_costs": _view.show_road_costs = value
		&"road_candidates": _view.show_road_candidates = value
		&"road_validation": _view.show_road_validation = value
		&"blocks": _view.show_blocks = value
		&"relationships": _view.show_relationships = value
	_status.text = "Visibility updated. Use Rebuild Debug Display to apply it."


func _debug_selection_changed(index: int) -> void:
	if _view == null or index < 0 or index >= _selection_options.item_count:
		return
	var selection: Dictionary = _selection_options.get_item_metadata(index)
	_view.selected_record_id = &""
	_view.selected_chunk = Vector2i(2147483647, 2147483647)
	var world_node := _view.get_node_or_null(_view.world_path) as FoundationWorld
	match selection.get("kind", "world"):
		"chunk":
			_view.selected_chunk = selection["coordinate"]
			var chunk := world_node.world_data.get_chunk(_view.selected_chunk)
			_selection_details.text = "%s\nBounds: %s\nDirty: %s" % [
				chunk.stable_id, chunk.world_bounds, chunk.get_dirty_layers(),
			]
		"record":
			_view.selected_record_id = selection["stable_id"]
			var record := world_node.world_data.get_record(_view.selected_record_id)
			if record is FoundationCityAnchor:
				var anchor := record as FoundationCityAnchor
				_selection_details.text = "%s\nCategory: %s\nPosition: %s\nInfluence: %s\nPriority: %.2f\nChunks: %s\nRegions: %s" % [
					anchor.stable_id,
					anchor.anchor_category,
					anchor.world_position,
					anchor.world_bounds,
					anchor.priority_weight,
					anchor.owning_chunks,
					anchor.owning_regions,
				]
			elif record is FoundationRoadNode:
				var road_node := record as FoundationRoadNode
				_selection_details.text = "%s\nKind: %s\nAnchor: %s\nPosition: %s\nDegree: %d\nChunks: %s\nRegions: %s" % [
					road_node.stable_id,
					road_node.node_kind,
					road_node.source_anchor_id,
					road_node.world_position,
					road_node.incident_edge_ids.size(),
					road_node.owning_chunks,
					road_node.owning_regions,
				]
			elif record is FoundationRoadPatternArea:
				var pattern := record as FoundationRoadPatternArea
				_selection_details.text = "%s\nPattern: %s\nBounds: %s\nOrientation: %.1f deg\nSpacing: %.1f\nTerrain following: %.2f" % [
					pattern.stable_id, pattern.pattern_family, pattern.world_bounds,
					pattern.preferred_orientation_degrees, pattern.preferred_spacing,
					pattern.terrain_following_strength,
				]
			elif record is FoundationLogicalRoad:
				var logical := record as FoundationLogicalRoad
				_selection_details.text = "%s\nClass: %s\nEdges: %s\nContinuity priority: %.2f\nNaming key: %s\nRoles: %s -> %s" % [
					logical.stable_id, logical.functional_class, logical.edge_ids,
					logical.continuity_priority, logical.provisional_naming_key,
					logical.start_semantic_role, logical.end_semantic_role,
				]
			elif record is FoundationIntersectionRecord:
				var intersection := record as FoundationIntersectionRecord
				_selection_details.text = "%s\nNode: %s\nType: %s\nDegree: %d\nIncoming: %s\nOutgoing: %s\nClass relationships: %s" % [
					intersection.stable_id, intersection.node_id,
					intersection.provisional_intersection_type, intersection.intersection_degree,
					intersection.incoming_edge_ids, intersection.outgoing_edge_ids,
					intersection.road_class_relationships,
				]
			elif record is FoundationRoadEdge:
				var road_edge := record as FoundationRoadEdge
				_selection_details.text = "%s\nClass: %s\nNodes: %s -> %s\nLength: %.2f\nCost: %.2f\nMax slope: %.2f°\nChunks: %s\nRegions: %s" % [
					road_edge.stable_id,
					road_edge.road_class,
					road_edge.from_node_id,
					road_edge.to_node_id,
					road_edge.planar_length,
					road_edge.terrain_cost,
					road_edge.maximum_slope_degrees,
					road_edge.owning_chunks,
					road_edge.owning_regions,
				]
			elif record is FoundationBlockRecord:
				var block := record as FoundationBlockRecord
				_selection_details.text = "%s\nArea: %.2f\nPerimeter: %.2f\nVertices: %d\nBoundary roads: %d\nValidation: %s\nChunks: %s\nRegions: %s" % [
					block.stable_id,
					block.area,
					block.perimeter,
					block.outer_boundary.size(),
					block.boundary_road_ids.size(),
					block.validation_state,
					block.owning_chunks,
					block.owning_regions,
				]
			else:
				_selection_details.text = "%s\nBounds: %s\nParent: %s\nLayer: %s" % [
					record.stable_id, record.world_bounds, record.parent_id, record.layer_type,
				]
		_:
			_selection_details.text = "World bounds: %s" % world_node.world_data.metadata.world_bounds


func _rebuild_pressed() -> void:
	if _view == null:
		return
	var primitive_count := _view.rebuild()
	_status.text = "Rebuilt %d disposable debug primitive(s)." % primitive_count
