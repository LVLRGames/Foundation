extends Node3D

@onready var world: FoundationWorld = $FoundationWorld
@onready var debug_view: FoundationDebugView = $FoundationWorld/FoundationDebugView
@onready var record_options: OptionButton = %RecordOptions
@onready var status_label: Label = %StatusLabel

var terrain_data: FoundationTerrainData
var terrain_origin_cell := Vector2i(-64, -64)
var road_result: FoundationRoadGenerationResult
var block_result: FoundationBlockGenerationResult
var parcel_result: FoundationParcelGenerationResult
var building_result: FoundationBuildingGenerationResult


func _ready() -> void:
	_configure_generation_controls()
	_add_synthetic_records()
	_register_selected_patterns()
	_generate_road_topology()
	_add_phase_3_road_fixtures()
	road_result = FoundationRoadTopologyGenerator.regenerate_derived_topology(world.world_data)
	block_result = FoundationBlockExtractor.generate(world.world_data)
	parcel_result = FoundationParcelSubdivider.generate(world.world_data)
	building_result = FoundationBuildingGenerator.generate(world.world_data)
	_bind_controls()
	_populate_record_options()
	debug_view.set_debug_enabled(true)
	debug_view.show_terrain_grid = %GridToggle.button_pressed
	debug_view.show_road_topology = %RoadToggle.button_pressed
	debug_view.show_road_costs = %CostToggle.button_pressed
	debug_view.show_road_candidates = %CandidateToggle.button_pressed
	debug_view.show_road_validation = %ValidationToggle.button_pressed
	debug_view.show_blocks = %BlockToggle.button_pressed
	debug_view.show_parcels = %ParcelToggle.button_pressed
	debug_view.show_buildings = %BuildingToggle.button_pressed
	debug_view.rebuild()
	$Camera3D.look_at(Vector3.ZERO, Vector3.UP)
	_update_status()


func _add_synthetic_records() -> void:
	var data := world.world_data
	data.register_layer_type(&"sample")
	var parent_id := _make_id(&"sample_site", &"", "western-campus")
	var child_id := _make_id(&"sample_feature", parent_id, "central-court")
	var spanning_id := _make_id(&"sample_feature", parent_id, "multi-chunk-envelope")

	var parent := FoundationSpatialRecord.new(
		parent_id,
		&"sample_site",
		&"sample",
		Rect2(-190.0, -74.0, 44.0, 44.0)
	)
	parent.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	parent.tags = PackedStringArray(["synthetic", "locked"])
	parent.source_pass = &"phase_1_demo_fixture"

	var child := FoundationSpatialRecord.new(
		child_id,
		&"sample_feature",
		&"sample",
		Rect2(-44.0, 24.0, 48.0, 32.0),
		parent_id
	)
	child.tags = PackedStringArray(["synthetic", "generated"])
	child.source_pass = &"phase_1_demo_fixture"

	var spanning := FoundationSpatialRecord.new(
		spanning_id,
		&"sample_feature",
		&"sample",
		Rect2(-24.0, -28.0, 184.0, 76.0),
		parent_id
	)
	spanning.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	spanning.tags = PackedStringArray(["synthetic", "multi_chunk", "overridden"])
	spanning.source_pass = &"phase_1_demo_fixture"

	parent.add_child(child_id)
	parent.add_child(spanning_id)
	data.register_record(parent)
	data.register_record(child)
	data.register_record(spanning)

	var city_center := FoundationCityAnchor.create(
		data.metadata,
		FoundationCityAnchor.CATEGORY_CITY_CENTER,
		Vector3(-96.0, 0.0, -32.0),
		"western-city-center",
		28.0,
		1.0
	)
	city_center.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	city_center.tags = PackedStringArray(["synthetic", "anchor", "primary"])
	city_center.metadata = {"display_name": "Western City Center"}
	city_center.source_pass = &"phase_1_demo_fixture"

	var map_exit := FoundationCityAnchor.create(
		data.metadata,
		FoundationCityAnchor.CATEGORY_MAP_EXIT,
		Vector3(128.0, 0.0, 0.0),
		"east-map-exit",
		24.0,
		0.8
	)
	map_exit.tags = PackedStringArray(["synthetic", "anchor", "multi_chunk_influence"])
	map_exit.metadata = {"display_name": "Eastern Map Exit"}
	map_exit.source_pass = &"phase_1_demo_fixture"

	var district_seed := FoundationCityAnchor.create(
		data.metadata,
		FoundationCityAnchor.CATEGORY_DISTRICT_SEED,
		Vector3(72.0, 0.0, 164.0),
		"north-district-seed",
		0.0,
		0.55
	)
	district_seed.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	district_seed.tags = PackedStringArray(["synthetic", "anchor", "point"])
	district_seed.metadata = {"display_name": "Northern District Seed"}
	district_seed.source_pass = &"phase_1_demo_fixture"

	data.register_record(city_center)
	data.register_record(map_exit)
	data.register_record(district_seed)
	var commercial_center := FoundationCityAnchor.create(
		data.metadata,
		FoundationCityAnchor.CATEGORY_COMMERCIAL_CENTER,
		Vector3(12.0, 0.0, -164.0),
		"southern-commercial-center",
		20.0,
		0.7
	)
	commercial_center.metadata = {"display_name": "Southern Commercial Center"}
	commercial_center.source_pass = &"phase_2_demo_fixture"
	var highway_entrance := FoundationCityAnchor.create(
		data.metadata,
		FoundationCityAnchor.CATEGORY_HIGHWAY_ENTRANCE,
		Vector3(-190.0, 0.0, 150.0),
		"northwest-highway-entrance",
		24.0,
		0.95
	)
	highway_entrance.metadata = {"display_name": "Northwest Highway Entrance"}
	highway_entrance.source_pass = &"phase_2_demo_fixture"
	data.register_record(commercial_center)
	data.register_record(highway_entrance)
	data.mark_layer_dirty(&"sample", Rect2(-4.0, -4.0, 8.0, 8.0))


func _register_selected_patterns() -> void:
	for pattern in world.world_data.get_road_pattern_areas():
		world.world_data.unregister_record(pattern.stable_id)
	var patterns: Array[FoundationRoadPatternArea] = []
	if %DowntownPatternToggle.button_pressed:
		var downtown := FoundationRoadPatternArea.create(
			world.world_data.metadata, "demo-downtown", Rect2(-150.0, -120.0, 100.0, 88.0),
			FoundationRoadPatternArea.DOWNTOWN_GRID
		)
		downtown.preferred_orientation_degrees = 0.0
		downtown.preferred_spacing = 28.0
		patterns.append(downtown)
	if %SuburbanPatternToggle.button_pressed:
		var suburban := FoundationRoadPatternArea.create(
			world.world_data.metadata, "demo-suburban", Rect2(34.0, -96.0, 130.0, 108.0),
			FoundationRoadPatternArea.SUBURBAN_LOOPS
		)
		suburban.preferred_orientation_degrees = 20.0
		suburban.preferred_spacing = 28.0
		suburban.curvature_allowance = 1.0
		patterns.append(suburban)
	if %RuralPatternToggle.button_pressed:
		var rural := FoundationRoadPatternArea.create(
			world.world_data.metadata, "demo-rural", Rect2(-70.0, 72.0, 160.0, 100.0),
			FoundationRoadPatternArea.RURAL_TERRAIN_FOLLOWING
		)
		rural.preferred_orientation_degrees = 8.0
		rural.preferred_spacing = 34.0
		rural.terrain_following_strength = 1.0
		patterns.append(rural)
	for pattern in patterns:
		pattern.source_pass = &"phase_2_demo_pattern"
		world.world_data.register_record(pattern)


func _generate_road_topology() -> void:
	world.world_data.metadata.seed = int(%SeedSpin.value)
	var terrain_profile := FoundationTerrainProfile.new()
	terrain_profile.seed = world.world_data.metadata.seed
	terrain_profile.grid_cells = Vector2i(128, 128)
	terrain_profile.cell_size = world.world_data.coordinate_system.cell_size
	terrain_profile.height_step = world.world_data.coordinate_system.height_step
	terrain_profile.chunk_cells = world.world_data.coordinate_system.chunk_cells
	terrain_profile.height_amplitude = 18.0
	terrain_data = FoundationTerrainGenerator.generate(terrain_profile)
	world.register_terrain_extent(terrain_data, terrain_origin_cell)
	var road_profile := FoundationRoadGenerationProfile.new()
	road_profile.extra_edge_count = 1
	match %ProfileOptions.selected:
		1:
			road_profile.slope_cost_weight = 40.0
			road_profile.protected_penalty = 1200.0
			road_profile.water_penalty = 500.0
		2:
			road_profile.search_diagonals = false
			road_profile.slope_cost_weight = 8.0
	road_result = FoundationRoadTopologyGenerator.generate(
		world.world_data,
		terrain_data,
		terrain_origin_cell,
		road_profile
	)


func _add_phase_3_road_fixtures() -> void:
	var l_boundary := PackedVector2Array([
		Vector2(-236.0, -236.0), Vector2(-116.0, -236.0),
		Vector2(-116.0, -196.0), Vector2(-176.0, -196.0),
		Vector2(-176.0, -116.0), Vector2(-236.0, -116.0),
		Vector2(-236.0, -236.0),
	])
	_register_demo_road("phase-3-l-shaped-loop", l_boundary, true)
	_register_demo_road("phase-3-open-component", PackedVector2Array([
		Vector2(-236.0, 204.0), Vector2(-164.0, 232.0), Vector2(-84.0, 208.0),
	]), false)
	_register_demo_road("phase-4-access-required-triangle", PackedVector2Array([
		Vector2(184.0, -236.0), Vector2(208.0, -236.0),
		Vector2(184.0, -224.0), Vector2(184.0, -236.0),
	]), true)


func _register_demo_road(semantic_key: String, points: PackedVector2Array, closed: bool) -> void:
	var route := PackedVector3Array()
	var sampler := FoundationTerrainSampler.new(terrain_data)
	var terrain_origin := Vector2(terrain_origin_cell) * terrain_data.cell_size
	for point in points:
		var local := point - terrain_origin
		route.append(Vector3(point.x, sampler.get_height_at_world(local), point.y))
	var edge := FoundationRoadEdge.new(
		_make_id(FoundationRoadEdge.ENTITY_TYPE, &"", semantic_key),
		&"",
		&"",
		route,
		FoundationRoadEdge.CLASS_CONNECTOR
	)
	edge.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	edge.source_pass = &"phase_3_demo_fixture"
	edge.tags = PackedStringArray([
		"phase_3", "demo", "bounded_loop" if closed else "open_component",
	])
	edge.metadata = {"phase_3_demo_fixture": true, "closed": closed}
	world.world_data.register_record(edge)


func _make_id(entity_type: StringName, parent_id: StringName, semantic_key: String) -> StringName:
	return FoundationSpatialId.make(
		world.world_data.metadata.seed,
		world.world_data.metadata.generator_version,
		world.world_data.metadata.content_pack_version,
		entity_type,
		parent_id,
		semantic_key
	)


func _bind_controls() -> void:
	%DebugToggle.toggled.connect(_debug_toggled)
	%WorldToggle.toggled.connect(_layer_toggled.bind(&"world_bounds"))
	%RegionToggle.toggled.connect(_layer_toggled.bind(&"regions"))
	%ChunkToggle.toggled.connect(_layer_toggled.bind(&"chunks"))
	%GridToggle.toggled.connect(_layer_toggled.bind(&"terrain_grid"))
	%RecordToggle.toggled.connect(_layer_toggled.bind(&"records"))
	%AnchorToggle.toggled.connect(_layer_toggled.bind(&"anchors"))
	%RoadToggle.toggled.connect(_layer_toggled.bind(&"road_topology"))
	%CostToggle.toggled.connect(_layer_toggled.bind(&"road_costs"))
	%CandidateToggle.toggled.connect(_layer_toggled.bind(&"road_candidates"))
	%ValidationToggle.toggled.connect(_layer_toggled.bind(&"road_validation"))
	%BlockToggle.toggled.connect(_layer_toggled.bind(&"blocks"))
	%ParcelToggle.toggled.connect(_layer_toggled.bind(&"parcels"))
	%BuildingToggle.toggled.connect(_layer_toggled.bind(&"buildings"))
	%RelationshipToggle.toggled.connect(_layer_toggled.bind(&"relationships"))
	%RebuildButton.pressed.connect(_rebuild_debug)
	%RegenerateButton.pressed.connect(_regenerate_selected_stage)
	%ClearRoadButton.pressed.connect(_clear_road_data)
	%ApplyStateButton.pressed.connect(_apply_selected_state)
	record_options.item_selected.connect(_record_selected)


func _populate_record_options() -> void:
	record_options.clear()
	record_options.add_item("No record selected")
	record_options.set_item_metadata(0, "")
	for record in world.world_data.spatial_index.get_all_records():
		record_options.add_item("%s [%s]" % [record.stable_id, record.layer_type])
		record_options.set_item_metadata(record_options.item_count - 1, String(record.stable_id))


func _debug_toggled(enabled: bool) -> void:
	debug_view.set_debug_enabled(enabled)
	if enabled:
		debug_view.rebuild()
	_update_status()


func _layer_toggled(enabled: bool, layer_id: StringName) -> void:
	match layer_id:
		&"world_bounds": debug_view.show_world_bounds = enabled
		&"regions": debug_view.show_regions = enabled
		&"chunks": debug_view.show_chunks = enabled
		&"terrain_grid": debug_view.show_terrain_grid = enabled
		&"records": debug_view.show_records = enabled
		&"anchors": debug_view.show_anchors = enabled
		&"road_topology": debug_view.show_road_topology = enabled
		&"road_costs": debug_view.show_road_costs = enabled
		&"road_candidates": debug_view.show_road_candidates = enabled
		&"road_validation": debug_view.show_road_validation = enabled
		&"blocks": debug_view.show_blocks = enabled
		&"parcels": debug_view.show_parcels = enabled
		&"buildings": debug_view.show_buildings = enabled
		&"relationships": debug_view.show_relationships = enabled
	_rebuild_debug()


func _record_selected(index: int) -> void:
	debug_view.selected_record_id = StringName(record_options.get_item_metadata(index))
	var record := world.world_data.get_record(debug_view.selected_record_id)
	if record != null:
		%StateOptions.select(int(record.authorship_state))
	_rebuild_debug()


func _rebuild_debug() -> void:
	debug_view.rebuild()
	_update_status()


func _configure_generation_controls() -> void:
	%ProfileOptions.clear()
	%ProfileOptions.add_item("Balanced")
	%ProfileOptions.add_item("Terrain following")
	%ProfileOptions.add_item("Rectilinear")
	%StageOptions.clear()
	%StageOptions.add_item("Full Phase 2 + Phase 3 + Phase 4 + Phase 5")
	%StageOptions.add_item("Logical roads + intersections")
	%StageOptions.add_item("Block extraction")
	%StageOptions.add_item("Parcel subdivision")
	%StageOptions.add_item("Building footprints + massing")
	%StateOptions.clear()
	%StateOptions.add_item("Generated")
	%StateOptions.add_item("Locked")
	%StateOptions.add_item("Overridden")


func _regenerate_selected_stage() -> void:
	match %StageOptions.selected:
		0:
			FoundationBuildingGenerator.clear_generated(world.world_data)
			FoundationParcelSubdivider.clear_generated(world.world_data)
			_register_selected_patterns()
			_generate_road_topology()
			_add_phase_3_road_fixtures()
			road_result = FoundationRoadTopologyGenerator.regenerate_derived_topology(world.world_data)
			block_result = FoundationBlockExtractor.generate(world.world_data)
			parcel_result = FoundationParcelSubdivider.generate(world.world_data)
			building_result = FoundationBuildingGenerator.generate(world.world_data)
		1:
			road_result = FoundationRoadTopologyGenerator.regenerate_derived_topology(world.world_data)
		2:
			FoundationBuildingGenerator.clear_generated(world.world_data)
			FoundationParcelSubdivider.clear_generated(world.world_data)
			block_result = FoundationBlockExtractor.generate(world.world_data)
		3:
			FoundationBuildingGenerator.clear_generated(world.world_data)
			parcel_result = FoundationParcelSubdivider.generate(world.world_data)
		_:
			building_result = FoundationBuildingGenerator.generate(world.world_data)
	_populate_record_options()
	_rebuild_debug()


func _clear_road_data() -> void:
	FoundationBuildingGenerator.clear_generated(world.world_data)
	FoundationParcelSubdivider.clear_generated(world.world_data)
	FoundationRoadTopologyGenerator.clear_generated_road_data(world.world_data)
	for edge in world.world_data.get_road_edges():
		if bool(edge.metadata.get("phase_3_demo_fixture", false)):
			world.world_data.unregister_record(edge.stable_id)
	FoundationRoadTopologyGenerator.clear_generated_road_data(world.world_data)
	for block in world.world_data.get_blocks():
		if block.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.world_data.unregister_record(block.stable_id)
	_populate_record_options()
	_rebuild_debug()


func _apply_selected_state() -> void:
	var record := world.world_data.get_record(debug_view.selected_record_id)
	if record == null:
		return
	record.authorship_state = %StateOptions.selected as FoundationSpatialRecord.AuthorshipState
	_rebuild_debug()


func _update_status() -> void:
	var issue_count := road_result.validation_issues.size() if road_result != null else 0
	status_label.text = "%d anchors | %d patterns | %d nodes | %d edges | %d logical | %d intersections | %d issues | %d blocks | %d parcels | %d buildings | %d debug" % [
		world.world_data.get_anchors().size(),
		world.world_data.get_road_pattern_areas().size(),
		world.world_data.get_road_nodes().size(),
		world.world_data.get_road_edges().size(),
		world.world_data.get_logical_roads().size(),
		world.world_data.get_road_intersections().size(),
		issue_count,
		world.world_data.get_blocks().size(),
		world.world_data.get_parcels().size(),
		world.world_data.get_buildings().size(),
		debug_view.last_primitive_count,
	]
