extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profile_round_trip_and_generation()
	_test_directionality_movements_and_controls()
	_test_determinism_serialization_and_authoring()
	_test_caps_collision_repair_and_validation()
	_test_debug_queries_and_scope()
	if _failures.is_empty():
		print("Foundation Phase 13 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 13 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_profile_round_trip_and_generation() -> void:
	var profile := FoundationTrafficMetadataProfile.new()
	profile.policy_id = &"phase_13_test_policy"
	profile.default_lane_width = 3.35
	profile.maximum_movements_per_intersection = 64
	var restored := FoundationTrafficMetadataProfile.from_dict(profile.to_dict())
	_check(restored.to_dict() == profile.to_dict(), "traffic metadata profile has a versioned deterministic round trip")
	_check(restored.validation_errors().is_empty(), "restored traffic metadata profile remains valid")
	var world := _make_fixture(13001)
	var topology_before := _topology_snapshot(world)
	var result := FoundationTrafficMetadataGenerator.generate(world, profile)
	_check(result.success and result.generated_cross_section_count == 4, "each Phase 2 edge receives one typed cross-section record")
	_check(result.generated_lane_count == 16, "arterial two-way fixture receives deterministic paired travel lanes")
	_check(result.generated_intersection_traffic_count == 1 and result.generated_approach_count == 4, "Phase 2 intersection receives four typed approaches")
	_check(result.generated_movement_count == 16, "lane turn permissions produce the bounded canonical movement set")
	_check(_topology_snapshot(world) == topology_before, "Phase 13 generation does not mutate Phase 2 road or intersection inputs")
	var issues := FoundationTrafficMetadataValidator.validate(world, profile)
	if not issues.is_empty():
		for issue in issues:
			print("Phase 13 generation diagnostic: ", issue.to_dict())
	_check(issues.is_empty(), "generated cross-sections and traffic metadata pass lineage, identity, geometry, and ownership validation")


func _test_directionality_movements_and_controls() -> void:
	var world := _make_fixture(13002)
	var result := FoundationTrafficMetadataGenerator.generate(world)
	var east_cross := world.get_cross_section_for_edge(&"p13_edge_e")
	var traffic := world.get_traffic_for_node(&"p13_center")
	_check(result.success and east_cross != null and traffic != null, "edge and node lineage queries resolve Phase 13 records")
	_check(east_cross.lanes_for_direction(FoundationRoadLane.DIRECTION_FORWARD).size() == 2 and east_cross.lanes_for_direction(FoundationRoadLane.DIRECTION_REVERSE).size() == 2, "two-way arterial cross section exposes two lanes in each direction")
	var forward := east_cross.lanes_for_direction(FoundationRoadLane.DIRECTION_FORWARD)[0]
	var reverse := east_cross.lanes_for_direction(FoundationRoadLane.DIRECTION_REVERSE)[0]
	_check(forward.centerline[0].distance_to(reverse.centerline[-1]) > 1.0, "opposing lane centerlines occupy opposite deterministic offsets")
	_check(forward.turn_permissions == PackedStringArray(["left", "through"]) and east_cross.lanes_for_direction(FoundationRoadLane.DIRECTION_FORWARD)[1].turn_permissions == PackedStringArray(["through", "right"]), "multi-lane turn permissions assign inner and outer lane roles")
	_check(traffic.control_type == FoundationIntersectionTrafficRecord.CONTROL_SIGNAL_PLAN and traffic.phase_groups.size() == 4, "four arterial approaches receive an abstract signal plan with deterministic phase groups")
	var turn_kinds: Dictionary = {}
	for movement in traffic.movements:
		turn_kinds[movement.turn_type] = true
	_check(turn_kinds.has(FoundationTurnMovement.TURN_LEFT) and turn_kinds.has(FoundationTurnMovement.TURN_THROUGH) and turn_kinds.has(FoundationTurnMovement.TURN_RIGHT), "intersection movements classify left, through, and right turns without U-turns")

	var one_way_world := _make_fixture(13003)
	(one_way_world.get_record(&"p13_edge_e") as FoundationRoadEdge).directionality = FoundationRoadEdge.DIRECTION_ONE_WAY_FORWARD
	FoundationTrafficMetadataGenerator.generate(one_way_world)
	var one_way_cross := one_way_world.get_cross_section_for_edge(&"p13_edge_e")
	var one_way_approach: FoundationTrafficApproach
	for approach in one_way_world.get_traffic_for_node(&"p13_center").approaches:
		if approach.road_edge_id == &"p13_edge_e":
			one_way_approach = approach
	_check(one_way_cross.lanes.size() == 2 and one_way_approach.outbound_lane_ids.size() == 2 and one_way_approach.inbound_lane_ids.is_empty(), "one-way directionality becomes explicit outbound-only lane membership at its from-node intersection")


func _test_determinism_serialization_and_authoring() -> void:
	var world := _make_fixture(13004)
	FoundationTrafficMetadataGenerator.generate(world)
	var first_cross := world.get_cross_section_for_edge(&"p13_edge_n")
	var first_traffic := world.get_traffic_for_node(&"p13_center")
	var first := FoundationSpatialRecordCodec.canonical_json({
		"cross_sections": _record_dicts(world.get_road_cross_sections()),
		"traffic": _record_dicts(world.get_intersection_traffic()),
	})
	FoundationTrafficMetadataGenerator.generate(world)
	var second := FoundationSpatialRecordCodec.canonical_json({
		"cross_sections": _record_dicts(world.get_road_cross_sections()),
		"traffic": _record_dicts(world.get_intersection_traffic()),
	})
	_check(first == second, "same seed, topology, and profile regenerate byte-stable lane and movement data")
	var restored := FoundationWorldData.from_dict(world.to_dict())
	_check(FoundationSpatialRecordCodec.canonical_json(restored.to_dict()) == FoundationSpatialRecordCodec.canonical_json(world.to_dict()), "world manifest round-trips typed nested Phase 13 data")
	var restored_cross := restored.get_cross_section_for_edge(&"p13_edge_n")
	var translated_cross := FoundationSpatialRecordCodec.record_from_dict(
		FoundationSpatialRecordCodec.translate_record_data(restored_cross.to_dict(), Vector2(11.0, -7.0))
	) as FoundationRoadCrossSectionRecord
	_check(translated_cross.lanes[0].centerline[0] == restored_cross.lanes[0].centerline[0] + Vector3(11.0, 0.0, -7.0), "authoring codec translates nested lane centerlines")
	var restored_traffic := restored.get_traffic_for_node(&"p13_center")
	var translated_traffic := FoundationSpatialRecordCodec.record_from_dict(
		FoundationSpatialRecordCodec.translate_record_data(restored_traffic.to_dict(), Vector2(-3.0, 5.0))
	) as FoundationIntersectionTrafficRecord
	_check(translated_traffic.movements[0].path_hint[0] == restored_traffic.movements[0].path_hint[0] + Vector3(-3.0, 0.0, 5.0), "authoring codec translates nested movement path hints")
	var policy := FoundationAuthoringPolicy.new()
	_check(FoundationWorldData.ROAD_CROSS_SECTION_LAYER in policy.supported_layers() and FoundationWorldData.INTERSECTION_TRAFFIC_LAYER in policy.supported_layers(), "Phase 11 authoring dependency policy includes Phase 13 layers")
	_check(FoundationRoadCrossSectionRecord.RECORD_KIND in policy.supported_record_kinds() and FoundationIntersectionTrafficRecord.RECORD_KIND in policy.supported_record_kinds(), "Phase 11 authoring policy restores both Phase 13 record kinds")
	first_cross = world.get_cross_section_for_edge(&"p13_edge_n")
	first_traffic = world.get_traffic_for_node(&"p13_center")
	first_cross.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	first_traffic.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	var locked_snapshot := FoundationSpatialRecordCodec.canonical_json(first_cross.to_dict())
	var overridden_snapshot := FoundationSpatialRecordCodec.canonical_json(first_traffic.to_dict())
	var regenerated := FoundationTrafficMetadataGenerator.generate(world)
	_check(regenerated.preserved_cross_section_count == 1 and FoundationSpatialRecordCodec.canonical_json(world.get_record(first_cross.stable_id).to_dict()) == locked_snapshot, "regeneration preserves locked cross-section object data and stable identity")
	_check(regenerated.preserved_intersection_traffic_count == 1 and FoundationSpatialRecordCodec.canonical_json(world.get_record(first_traffic.stable_id).to_dict()) == overridden_snapshot, "regeneration preserves overridden intersection-traffic data and stable identity")


func _test_caps_collision_repair_and_validation() -> void:
	var capped_world := _make_fixture(13005)
	var cap_profile := FoundationTrafficMetadataProfile.new()
	cap_profile.maximum_generation_operations = 1
	var capped := FoundationTrafficMetadataGenerator.generate(capped_world, cap_profile)
	_check(not capped.success and capped_world.get_road_cross_sections().is_empty() and capped_world.get_intersection_traffic().is_empty(), "operation-cap failure removes partial generator-owned Phase 13 data")
	var single_edge_world := _make_fixture(13010)
	for record_id in [&"p13_intersection", &"p13_edge_n", &"p13_edge_s", &"p13_edge_w", &"p13_north", &"p13_south", &"p13_west"]:
		single_edge_world.unregister_record(record_id)
	var single_capped := FoundationTrafficMetadataGenerator.generate(single_edge_world, cap_profile)
	_check(not single_capped.success and single_edge_world.get_road_cross_sections().is_empty(), "operation-cap failure is atomic even when the capped edge is the final input record")
	var preflight_world := _make_fixture(13006)
	var preflight_profile := FoundationTrafficMetadataProfile.new()
	preflight_profile.maximum_cross_sections = 1
	var preflight := FoundationTrafficMetadataGenerator.generate(preflight_world, preflight_profile)
	_check(not preflight.success and preflight_world.get_road_cross_sections().is_empty(), "record cap rejects excessive topology before mutating Phase 13 layers")

	var collision_world := _make_fixture(13007)
	var profile := FoundationTrafficMetadataProfile.new()
	var canonical_id := FoundationSpatialId.make(
		collision_world.metadata.seed, profile.generator_version, collision_world.metadata.content_pack_version,
		FoundationRoadCrossSectionRecord.ENTITY_TYPE, &"p13_edge_e", FoundationTrafficMetadataGenerator.cross_section_semantic(profile)
	)
	var blocker := FoundationSpatialRecord.new(canonical_id, &"collision_fixture", &"sample", Rect2())
	_register(collision_world, blocker)
	FoundationTrafficMetadataGenerator.generate(collision_world, profile)
	var repaired := collision_world.get_cross_section_for_edge(&"p13_edge_e")
	_check(repaired != null and repaired.stable_id != canonical_id and FoundationTrafficMetadataValidator.validate(collision_world, profile).is_empty(), "stable-ID collisions use deterministic repair identities accepted by validation")

	var invalid_world := _make_fixture(13008)
	FoundationTrafficMetadataGenerator.generate(invalid_world)
	var invalid_cross := invalid_world.get_cross_section_for_edge(&"p13_edge_w")
	invalid_cross.lanes[0].width = -1.0
	var invalid_traffic := invalid_world.get_traffic_for_node(&"p13_center")
	invalid_traffic.movements[0].from_lane_id = &"missing_lane"
	var kinds: Dictionary = {}
	for issue in FoundationTrafficMetadataValidator.validate(invalid_world):
		kinds[issue.kind] = true
	_check(kinds.has(&"invalid_lane_policy") and kinds.has(&"invalid_movement_lane"), "validator reports corrupted lane policy and movement lineage deterministically")


func _test_debug_queries_and_scope() -> void:
	var world := _make_fixture(13009)
	FoundationTrafficMetadataGenerator.generate(world)
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"traffic_metadata")
	var geometry := registry.build(world)
	_check(geometry.get_primitive_count() > 0 and registry.last_provider_invocations == 1, "traffic debug provider emits disposable batched lanes, movement hints, controls, and labels")
	registry.enabled = false
	_check(registry.build(world).get_primitive_count() == 0 and registry.last_provider_invocations == 0, "disabled debug registry retains the true zero-work path with Phase 13 registered")
	var cross := world.get_cross_section_for_edge(&"p13_edge_s")
	var queried := world.query_bounds(cross.world_bounds.grow(0.1), [FoundationWorldData.ROAD_CROSS_SECTION_LAYER])
	_check(cross in queried and world.get_traffic_for_intersection(&"p13_intersection") != null, "Phase 13 data participates in bounded spatial queries and typed lineage queries")
	var demo_source := FileAccess.get_file_as_string("res://demo/spatial_model_demo.gd")
	var demo_scene_source := FileAccess.get_file_as_string("res://demo/spatial_model_demo.tscn")
	var dock_source := FileAccess.get_file_as_string("res://addons/foundation/editor/debug_editor_dock.gd")
	_check(demo_source.contains("FoundationTrafficMetadataGenerator") and demo_scene_source.contains("TrafficToggle") and demo_scene_source.contains("Phase 13"), "runtime demo exposes Phase 13 generation, regeneration, and independent visualization")
	_check(dock_source.contains("Generate / Regenerate Traffic Metadata") and dock_source.contains("Clear Generated Traffic Metadata") and dock_source.contains("FoundationRoadCrossSectionRecord") and dock_source.contains("FoundationIntersectionTrafficRecord"), "editor dock exposes Phase 13 generation, clearing, and typed inspection")
	var packed_scene := load("res://demo/spatial_model_demo.tscn") as PackedScene
	var demo := packed_scene.instantiate()
	root.add_child(demo)
	var demo_world := demo.get_node("FoundationWorld") as FoundationWorld
	var demo_debug := demo.get_node("FoundationWorld/FoundationDebugView") as FoundationDebugView
	_check(not demo_world.world_data.get_road_cross_sections().is_empty() and not demo_world.world_data.get_intersection_traffic().is_empty(), "Phase 13 demo produces inspectable cross-section and intersection-traffic records")
	_check(demo_debug.show_traffic_metadata and demo.get_node("%TrafficToggle").button_pressed, "Phase 13 demo enables its disposable overlay independently")
	demo.queue_free()
	var forbidden := [&"spawn_vehicle", &"simulate_traffic", &"build_navmesh", &"create_collision", &"instantiate_signal", &"build_road_mesh"]
	var found := false
	for method_name in forbidden:
		found = found or FoundationTrafficMetadataGenerator.new().has_method(method_name)
	_check(not found, "Phase 13 adds metadata without vehicles, simulation, navigation, collision, signal props, or production road meshes")


func _make_fixture(seed: int) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 13
	metadata.content_pack_version = &"phase-13-tests"
	metadata.world_bounds = Rect2(-128.0, -128.0, 256.0, 256.0)
	var world := FoundationWorldData.new(metadata, FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(16, 16), Vector2i(2, 2)))
	world.initialize_default_layers()
	world.initialize_partitions()
	var center := FoundationRoadNode.new(&"p13_center", Vector3.ZERO, FoundationRoadNode.ROLE_INTERSECTION)
	var north := FoundationRoadNode.new(&"p13_north", Vector3(0.0, 2.0, -80.0), FoundationRoadNode.ROLE_MAP_EXIT)
	var east := FoundationRoadNode.new(&"p13_east", Vector3(80.0, 1.0, 0.0), FoundationRoadNode.ROLE_MAP_EXIT)
	var south := FoundationRoadNode.new(&"p13_south", Vector3(0.0, -1.0, 80.0), FoundationRoadNode.ROLE_MAP_EXIT)
	var west := FoundationRoadNode.new(&"p13_west", Vector3(-80.0, 0.0, 0.0), FoundationRoadNode.ROLE_MAP_EXIT)
	for node in [center, north, east, south, west]:
		_register(world, node)
	var edge_n := FoundationRoadEdge.new(&"p13_edge_n", center.stable_id, north.stable_id, PackedVector3Array([center.world_position, Vector3(0.0, 1.0, -40.0), north.world_position]), FoundationRoadEdge.CLASS_ARTERIAL)
	var edge_e := FoundationRoadEdge.new(&"p13_edge_e", center.stable_id, east.stable_id, PackedVector3Array([center.world_position, Vector3(40.0, 0.5, 0.0), east.world_position]), FoundationRoadEdge.CLASS_ARTERIAL)
	var edge_s := FoundationRoadEdge.new(&"p13_edge_s", center.stable_id, south.stable_id, PackedVector3Array([center.world_position, Vector3(0.0, -0.5, 40.0), south.world_position]), FoundationRoadEdge.CLASS_ARTERIAL)
	var edge_w := FoundationRoadEdge.new(&"p13_edge_w", center.stable_id, west.stable_id, PackedVector3Array([center.world_position, Vector3(-40.0, 0.0, 0.0), west.world_position]), FoundationRoadEdge.CLASS_ARTERIAL)
	for edge in [edge_n, edge_e, edge_s, edge_w]:
		edge.logical_road_id = &"p13_logical_ns" if edge in [edge_n, edge_s] else &"p13_logical_ew"
		edge.physical_profile_key = &"arterial_two_way"
		edge.source_pass = &"phase_13_fixture"
		_register(world, edge)
		center.add_incident_edge(edge.stable_id)
		(world.get_record(edge.to_node_id) as FoundationRoadNode).add_incident_edge(edge.stable_id)
	var intersection := FoundationIntersectionRecord.new(&"p13_intersection", center.stable_id, center.world_position)
	intersection.connected_edge_ids = center.incident_edge_ids.duplicate()
	intersection.incoming_edge_ids = center.incident_edge_ids.duplicate()
	intersection.outgoing_edge_ids = center.incident_edge_ids.duplicate()
	intersection.intersection_degree = 4
	intersection.provisional_intersection_type = &"crossroads"
	_register(world, intersection)
	return world


func _topology_snapshot(world: FoundationWorldData) -> String:
	return FoundationSpatialRecordCodec.canonical_json({
		"nodes": _record_dicts(world.get_road_nodes()),
		"edges": _record_dicts(world.get_road_edges()),
		"intersections": _record_dicts(world.get_road_intersections()),
	})


func _record_dicts(records: Array) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for record in records:
		values.append(record.to_dict())
	return values


func _register(world: FoundationWorldData, record: FoundationSpatialRecord) -> void:
	record.set_owning_chunks(world.coordinate_system.world_bounds_to_chunks(record.world_bounds))
	var region_set: Dictionary = {}
	for chunk in record.owning_chunks:
		region_set[world.coordinate_system.chunk_to_region(chunk)] = true
	var regions: Array[Vector2i] = []
	for region: Vector2i in region_set:
		regions.append(region)
	record.set_owning_regions(regions)
	world.register_record(record)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
