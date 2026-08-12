@tool
class_name FoundationDebugEditorDock
extends ScrollContainer

## Editor controls expose disposable debug presentation and explicit generation actions.

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
		[&"parcels", "Parcels, frontage, access state, and validation"],
		[&"buildings", "Building footprints, primitive massing, and validation"],
		[&"facades", "Modular facade grids, windows, entrances, and validation"],
		[&"districts", "District coverage, character, use policy, and validation"],
		[&"terrain_grading", "Terrain grading roads, pads, bridges, cut/fill, and validation"],
		[&"parking_facilities", "Parking demand, footprints, stalls, access, and validation"],
		[&"public_features", "Public sites, service radii, anchor lineage, and validation"],
		[&"overrides", "Authored modifications, creations, tombstones, and conflicts"],
		[&"streaming", "Chunk streaming lifecycle and visual LOD"],
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

	var generate_parcels := Button.new()
	generate_parcels.text = "Generate / Regenerate Parcels"
	generate_parcels.pressed.connect(_generate_parcels_pressed)
	_content.add_child(generate_parcels)
	var clear_parcels := Button.new()
	clear_parcels.text = "Clear Generated Parcels"
	clear_parcels.pressed.connect(_clear_parcels_pressed)
	_content.add_child(clear_parcels)
	var generate_buildings := Button.new()
	generate_buildings.text = "Generate / Regenerate Buildings"
	generate_buildings.pressed.connect(_generate_buildings_pressed)
	_content.add_child(generate_buildings)
	var clear_buildings := Button.new()
	clear_buildings.text = "Clear Generated Buildings"
	clear_buildings.pressed.connect(_clear_buildings_pressed)
	_content.add_child(clear_buildings)
	var generate_facades := Button.new()
	generate_facades.text = "Generate / Regenerate Facades"
	generate_facades.pressed.connect(_generate_facades_pressed)
	_content.add_child(generate_facades)
	var clear_facades := Button.new()
	clear_facades.text = "Clear Generated Facades"
	clear_facades.pressed.connect(_clear_facades_pressed)
	_content.add_child(clear_facades)
	var generate_districts := Button.new()
	generate_districts.text = "Generate / Regenerate Districts"
	generate_districts.pressed.connect(_generate_districts_pressed)
	_content.add_child(generate_districts)
	var clear_districts := Button.new()
	clear_districts.text = "Clear Generated Districts"
	clear_districts.pressed.connect(_clear_districts_pressed)
	_content.add_child(clear_districts)
	var generate_site_features := Button.new()
	generate_site_features.text = "Generate / Regenerate Parking + Public Features"
	generate_site_features.pressed.connect(_generate_site_features_pressed)
	_content.add_child(generate_site_features)
	var clear_site_features := Button.new()
	clear_site_features.text = "Clear Generated Parking + Public Features"
	clear_site_features.pressed.connect(_clear_site_features_pressed)
	_content.add_child(clear_site_features)
	var apply_grading := Button.new()
	apply_grading.text = "Plan / Apply Terrain Grading"
	apply_grading.pressed.connect(_apply_terrain_grading_pressed)
	_content.add_child(apply_grading)
	var revert_grading := Button.new()
	revert_grading.text = "Revert Terrain Grading"
	revert_grading.pressed.connect(_revert_terrain_grading_pressed)
	_content.add_child(revert_grading)


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
	_layer_toggles[&"parcels"].button_pressed = _view.show_parcels
	_layer_toggles[&"buildings"].button_pressed = _view.show_buildings
	_layer_toggles[&"facades"].button_pressed = _view.show_facades
	_layer_toggles[&"districts"].button_pressed = _view.show_districts
	_layer_toggles[&"terrain_grading"].button_pressed = _view.show_terrain_grading
	_layer_toggles[&"parking_facilities"].button_pressed = _view.show_parking_facilities
	_layer_toggles[&"public_features"].button_pressed = _view.show_public_features
	_layer_toggles[&"overrides"].button_pressed = _view.show_overrides
	_layer_toggles[&"streaming"].button_pressed = _view.show_streaming
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
		&"parcels": _view.show_parcels = value
		&"buildings": _view.show_buildings = value
		&"facades": _view.show_facades = value
		&"districts": _view.show_districts = value
		&"terrain_grading": _view.show_terrain_grading = value
		&"parking_facilities": _view.show_parking_facilities = value
		&"public_features": _view.show_public_features = value
		&"overrides": _view.show_overrides = value
		&"streaming": _view.show_streaming = value
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
			_selection_details.text = "%s\nBounds: %s\nDirty: %s\nRuntime: %d\nLOD: %d\nTransitions: %d" % [
				chunk.stable_id, chunk.world_bounds, chunk.get_dirty_layers(),
				chunk.runtime_state, chunk.runtime_lod_level, chunk.runtime_transition_serial,
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
			elif record is FoundationParcelRecord:
				var parcel := record as FoundationParcelRecord
				_selection_details.text = "%s\nParent: %s\nKind: %s\nArea: %.2f\nFrontage: %.2f\nDepth: %.2f\nAccess: %s\nBuildable: %s\nValidation: %s\nChunks: %s\nRegions: %s" % [
					parcel.stable_id, parcel.parent_id, parcel.parcel_kind, parcel.area,
					parcel.approximate_frontage_width, parcel.approximate_depth,
					parcel.access_state, parcel.buildable, parcel.validation_state,
					parcel.owning_chunks, parcel.owning_regions,
				]
			elif record is FoundationBuildingRecord:
				var building := record as FoundationBuildingRecord
				_selection_details.text = "%s\nParcel: %s\nBlock: %s\nFootprint: %.2f\nCoverage: %.3f / %.3f target\nFloors: %d\nHeight: %.2f\nFront road: %s\nValidation: %s\nChunks: %s\nRegions: %s" % [
					building.stable_id, building.parent_id, building.parent_block_id,
					building.footprint_area, building.coverage_ratio,
					building.target_coverage_ratio, building.floor_count, building.height,
					building.primary_road_edge_id, building.validation_state,
					building.owning_chunks, building.owning_regions,
				]
			elif record is FoundationFacadeRecord:
				var facade := record as FoundationFacadeRecord
				_selection_details.text = "%s\nBuilding: %s\nRole: %s\nGrammar: %s\nLength: %.2f\nFloors / bays: %d / %d\nModules: %d\nGlazing: %.1f%%\nEntrance: %s\nValidation: %s\nChunks: %s\nRegions: %s" % [
					facade.stable_id, facade.parent_id, facade.facade_role, facade.grammar_id,
					facade.facade_length, facade.floor_count, facade.bay_count,
					facade.modules.size(), facade.glazing_ratio * 100.0,
					facade.entrance_module_id, facade.validation_state,
					facade.owning_chunks, facade.owning_regions,
				]
			elif record is FoundationDistrictRecord:
				var district := record as FoundationDistrictRecord
				_selection_details.text = "%s\nCharacter: %s\nPrimary / allowed: %s / %s\nBlocks: %s\nArea: %.2f\nDensity / intensity: %.2f / %.2f\nHeight: %.1f-%.1f\nAnchor: %s\nPatterns: %s\nValidation: %s\nChunks: %s\nRegions: %s" % [
					district.stable_id, district.character_key, district.primary_use,
					district.allowed_uses, district.member_block_ids, district.total_area,
					district.target_density, district.target_intensity,
					district.minimum_height, district.maximum_height,
					district.source_anchor_id, district.source_pattern_ids,
					district.validation_state, district.owning_chunks, district.owning_regions,
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


func _generate_parcels_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	if not _revert_grading_before_upstream_change(world_node):
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	var cleared_districts := FoundationDistrictGenerator.clear_generated(world_node.world_data)
	var cleared_facades := FoundationFacadeGenerator.clear_generated(world_node.world_data)
	var cleared_buildings := FoundationBuildingGenerator.clear_generated(world_node.world_data)
	var result := FoundationParcelSubdivider.generate(world_node.world_data)
	_status.text = "Parcel generation %s: %d generated, %d preserved; %d buildings, %d facades, and %d districts cleared." % [
		"completed" if result.success else "failed",
		result.generated_parcel_count,
		result.preserved_parcel_count,
		cleared_buildings,
		cleared_facades,
		cleared_districts,
	]
	_populate_selection_options()


func _clear_parcels_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	if not _revert_grading_before_upstream_change(world_node):
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	var removed_districts := FoundationDistrictGenerator.clear_generated(world_node.world_data)
	var removed_facades := FoundationFacadeGenerator.clear_generated(world_node.world_data)
	var removed_buildings := FoundationBuildingGenerator.clear_generated(world_node.world_data)
	var removed := FoundationParcelSubdivider.clear_generated(world_node.world_data)
	_status.text = "Cleared %d generated parcel, %d building, %d facade, and %d district record(s); authored records were preserved." % [removed, removed_buildings, removed_facades, removed_districts]
	_populate_selection_options()


func _generate_buildings_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	if not _revert_grading_before_upstream_change(world_node):
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	var cleared_districts := FoundationDistrictGenerator.clear_generated(world_node.world_data)
	var cleared_facades := FoundationFacadeGenerator.clear_generated(world_node.world_data)
	var result := FoundationBuildingGenerator.generate(world_node.world_data)
	_status.text = "Building generation %s: %d generated, %d preserved, %d parcels skipped; %d facades and %d districts cleared." % [
		"completed" if result.success else "failed",
		result.generated_building_count,
		result.preserved_building_count,
		result.skipped_parcel_count,
		cleared_facades,
		cleared_districts,
	]
	_populate_selection_options()


func _clear_buildings_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	if not _revert_grading_before_upstream_change(world_node):
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	var removed_districts := FoundationDistrictGenerator.clear_generated(world_node.world_data)
	var removed_facades := FoundationFacadeGenerator.clear_generated(world_node.world_data)
	var removed := FoundationBuildingGenerator.clear_generated(world_node.world_data)
	_status.text = "Cleared %d generated building, %d facade, and %d district record(s); authored records were preserved." % [removed, removed_facades, removed_districts]
	_populate_selection_options()


func _generate_facades_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	var cleared_districts := FoundationDistrictGenerator.clear_generated(world_node.world_data)
	var result := FoundationFacadeGenerator.generate(world_node.world_data)
	_status.text = "Facade generation %s: %d generated, %d preserved, %d buildings skipped, %d modules; %d districts cleared." % [
		"completed" if result.success else "failed",
		result.generated_facade_count,
		result.preserved_facade_count,
		result.skipped_building_count,
		result.generated_module_count,
		cleared_districts,
	]
	_populate_selection_options()


func _clear_facades_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	var removed_districts := FoundationDistrictGenerator.clear_generated(world_node.world_data)
	var removed := FoundationFacadeGenerator.clear_generated(world_node.world_data)
	_status.text = "Cleared %d generated facade and %d district record(s); authored records were preserved." % [removed, removed_districts]
	_populate_selection_options()


func _generate_districts_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	var result := FoundationDistrictGenerator.generate(world_node.world_data)
	_status.text = "District generation %s: %d generated, %d preserved, %d blocks assigned, %d adjacency edges." % [
		"completed" if result.success else "failed", result.generated_district_count,
		result.preserved_district_count, result.assigned_block_count, result.adjacency_edge_count,
	]
	_populate_selection_options()


func _clear_districts_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	var removed := FoundationDistrictGenerator.clear_generated(world_node.world_data)
	_status.text = "Cleared %d generated district record(s); authored districts were preserved." % removed
	_populate_selection_options()


func _generate_site_features_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	var result := FoundationSiteFeatureGenerator.generate(
		world_node.world_data, null, world_node.terrain_data, world_node.terrain_origin_cell
	)
	_view.rebuild()
	_status.text = "Phase 10 generation %s: %d parking, %d public, %d/%d spaces, %d unmet." % [
		"completed" if result.success else "failed", result.generated_parking_count,
		result.generated_public_feature_count, result.supplied_spaces_total,
		result.demand_spaces_total, result.unmet_demand_total,
	]
	_populate_selection_options()


func _clear_site_features_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	var removed := FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	_view.rebuild()
	_status.text = "Cleared %d parking and %d public-feature record(s); authored records were preserved." % [
		removed["parking"], removed["public_features"],
	]
	_populate_selection_options()


func _apply_terrain_grading_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node first."
		return
	if world_node.terrain_data == null:
		_status.text = "Register authoritative terrain data with FoundationWorld before grading."
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	if world_node.world_data.terrain_grading_plan != null and world_node.world_data.terrain_grading_plan.state == FoundationTerrainGradingPlan.STATE_APPLIED:
		var revert := FoundationTerrainGrader.revert_plan(world_node.world_data, world_node.terrain_data, world_node.world_data.terrain_grading_plan)
		if not revert.success:
			_status.text = "Terrain grading could not replace the existing applied plan safely."
			return
	var planned := FoundationTerrainGrader.create_plan(world_node.world_data, world_node.terrain_data, world_node.terrain_origin_cell)
	if not planned.success:
		world_node.world_data.terrain_grading_plan = planned.plan
		_view.rebuild()
		_status.text = "Terrain grading plan failed validation with %d issue(s)." % planned.validation_issues.size()
		return
	var applied := FoundationTerrainGrader.apply_plan(world_node.world_data, world_node.terrain_data, planned.plan)
	_view.rebuild()
	_status.text = "Terrain grading %s: %d operation(s), %d changed vertices, %d dirty chunks." % [
		"applied" if applied.success else "failed", planned.plan.operations.size(),
		applied.changed_vertex_count, applied.dirty_chunk_count,
	]


func _revert_terrain_grading_pressed() -> void:
	var world_node := _selected_world()
	if world_node == null or world_node.terrain_data == null or world_node.world_data.terrain_grading_plan == null:
		_status.text = "No registered terrain grading plan is available to revert."
		return
	FoundationSiteFeatureGenerator.clear_generated(world_node.world_data)
	var result := FoundationTerrainGrader.revert_plan(world_node.world_data, world_node.terrain_data, world_node.world_data.terrain_grading_plan)
	_view.rebuild()
	_status.text = "Terrain grading %s: %d restored vertices, %d dirty chunks." % [
		"reverted" if result.success else "revert refused", result.changed_vertex_count, result.dirty_chunk_count,
	]


func _revert_grading_before_upstream_change(world_node: FoundationWorld) -> bool:
	if world_node.terrain_data == null or world_node.world_data.terrain_grading_plan == null:
		return true
	if world_node.world_data.terrain_grading_plan.state != FoundationTerrainGradingPlan.STATE_APPLIED:
		return true
	var result := FoundationTerrainGrader.revert_plan(
		world_node.world_data, world_node.terrain_data, world_node.world_data.terrain_grading_plan
	)
	if result.success:
		return true
	_status.text = "Upstream regeneration was refused because applied terrain grading could not be safely reverted."
	return false


func _selected_world() -> FoundationWorld:
	if _view == null:
		return null
	var world_node := _view.get_node_or_null(_view.world_path) as FoundationWorld
	if world_node != null and world_node.world_data == null:
		world_node.initialize_world()
	return world_node
