extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline := _test_determinism_and_connectivity()
	var world := baseline[0] as FoundationWorldData
	var terrain := baseline[1] as FoundationTerrainData
	var origin: Vector2i = baseline[2]
	_test_negative_and_boundary_ownership(world)
	_test_serialization_round_trip(world)
	_test_regeneration_states(terrain, origin)
	_test_preserved_edge_connectivity(terrain, origin)
	_test_preserved_record_reindex()
	_test_terrain_influence()
	_test_debug_contract(world)
	_test_issue_9_pattern_graph_contract()
	_test_issue_9_grading_and_validation()
	_test_issue_9_demo_contract()
	_test_scope_exclusions(world)

	if _failures.is_empty():
		print("Foundation Phase 2 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 2 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_determinism_and_connectivity() -> Array:
	var positions: Array[Vector3] = [
		Vector3(-132.0, 0.0, -132.0),
		Vector3(-128.0, 0.0, -1.0),
		Vector3(64.0, 0.0, -96.0),
		Vector3(132.0, 0.0, 132.0),
	]
	var first_world := _make_world(2026, positions)
	var second_world := _make_world(2026, positions)
	var first_terrain := _make_flat_terrain(2026, Vector2i(80, 80))
	var second_terrain := _make_flat_terrain(2026, Vector2i(80, 80))
	var origin := Vector2i(-40, -40)
	var terrain_before := _terrain_snapshot(first_terrain)
	var anchors_before := _anchor_snapshot(first_world)
	var first_result := FoundationRoadTopologyGenerator.generate(first_world, first_terrain, origin)
	var second_result := FoundationRoadTopologyGenerator.generate(second_world, second_terrain, origin)
	_check(first_result.success and second_result.success, "deterministic road generation succeeds for identical inputs")
	_check(
		_topology_snapshot(first_world) == _topology_snapshot(second_world),
		"same seed, anchors, terrain, origin, and profile reproduce identical topology"
	)
	_check(
		first_result.generated_node_count == positions.size(),
		"one abstract road node is generated for every city anchor"
	)
	_check(
		first_world.get_road_edges().size() == positions.size() - 1,
		"minimum deterministic topology connects anchors with a spanning tree"
	)
	_check(_is_connected(first_world), "every eligible city anchor participates in one connected topology")
	var every_anchor_linked := true
	for node in first_world.get_road_nodes():
		every_anchor_linked = every_anchor_linked and not String(node.source_anchor_id).is_empty()
		every_anchor_linked = every_anchor_linked and not node.incident_edge_ids.is_empty()
	_check(every_anchor_linked, "anchor road nodes retain source identity and deterministic incident edges")
	_check(_terrain_snapshot(first_terrain) == terrain_before, "road generation does not mutate authoritative terrain")
	_check(_anchor_snapshot(first_world) == anchors_before, "road generation does not mutate authoritative anchors")
	_check(
		_generated_edges_terminate_at_nodes(first_world),
		"authoritative generated routes terminate exactly at their road-node positions"
	)
	return [first_world, first_terrain, origin]


func _test_negative_and_boundary_ownership(world: FoundationWorldData) -> void:
	var boundary_node: FoundationRoadNode
	for node in world.get_road_nodes():
		var anchor := world.get_record(node.source_anchor_id) as FoundationCityAnchor
		if anchor != null and anchor.world_position == Vector3(-128.0, 0.0, -1.0):
			boundary_node = node
			break
	_check(boundary_node != null, "negative boundary anchor produces a road node")
	_check(
		boundary_node != null and boundary_node.owning_chunks == [Vector2i(-1, -1)],
		"road-node chunk ownership floors correctly at -128 m and -1 m"
	)
	var crosses_signed_chunks := false
	var crosses_regions := false
	for edge in world.get_road_edges():
		var has_negative := false
		var has_positive := false
		for chunk in edge.owning_chunks:
			has_negative = has_negative or chunk.x < 0 or chunk.y < 0
			has_positive = has_positive or chunk.x >= 0 or chunk.y >= 0
		crosses_signed_chunks = crosses_signed_chunks or (has_negative and has_positive)
		crosses_regions = crosses_regions or edge.owning_regions.size() > 1
	_check(crosses_signed_chunks, "terrain-aware edges index across negative and positive chunk boundaries")
	_check(crosses_regions, "terrain-aware edges index into every crossed region bucket")
	var indexed_everywhere := true
	for edge in world.get_road_edges():
		for chunk in edge.owning_chunks:
			indexed_everywhere = indexed_everywhere and edge in world.get_records_in_chunk(chunk, FoundationWorldData.ROAD_EDGE_LAYER)
		for region in edge.owning_regions:
			indexed_everywhere = indexed_everywhere and edge in world.get_records_in_region(region, FoundationWorldData.ROAD_EDGE_LAYER)
	_check(indexed_everywhere, "road edges are queryable from all owning chunk and region buckets")


func _test_serialization_round_trip(world: FoundationWorldData) -> void:
	var manifest := world.to_dict()
	var restored := FoundationWorldData.from_dict(manifest)
	_check(
		_topology_snapshot(restored) == _topology_snapshot(world),
		"road nodes, edges, route points, metrics, states, and adjacency serialize round-trip"
	)
	var typed_records := true
	for node in restored.get_road_nodes():
		typed_records = typed_records and node is FoundationRoadNode
	for edge in restored.get_road_edges():
		typed_records = typed_records and edge is FoundationRoadEdge
	_check(typed_records, "road topology restores through typed Node-free record contracts")
	var edge_layer := restored.get_layer(FoundationWorldData.ROAD_EDGE_LAYER)
	_check(
		edge_layer.metadata.has("profile") and edge_layer.metadata.has("terrain_origin_cell"),
		"serialized road layers preserve generation profile and terrain-origin metadata"
	)


func _test_regeneration_states(terrain: FoundationTerrainData, origin: Vector2i) -> void:
	var positions: Array[Vector3] = [
		Vector3(-132.0, 0.0, -132.0),
		Vector3(-128.0, 0.0, -1.0),
		Vector3(64.0, 0.0, -96.0),
		Vector3(132.0, 0.0, 132.0),
	]
	var world := _make_world(2026, positions)
	FoundationRoadTopologyGenerator.generate(world, terrain, origin)
	var locked_edge := world.get_road_edges()[0]
	locked_edge.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	locked_edge.terrain_cost = 9876.5
	locked_edge.metadata["review_marker"] = "preserved"
	var overridden_node := world.get_record(locked_edge.from_node_id) as FoundationRoadNode
	overridden_node.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	overridden_node.set_world_position(overridden_node.world_position + Vector3(1.0, 2.0, 1.0))
	var locked_edge_id := locked_edge.stable_id
	var overridden_node_id := overridden_node.stable_id
	var overridden_position := overridden_node.world_position
	var rerun := FoundationRoadTopologyGenerator.generate(world, terrain, origin)
	var restored_edge := world.get_record(locked_edge_id) as FoundationRoadEdge
	var restored_node := world.get_record(overridden_node_id) as FoundationRoadNode
	_check(rerun.success, "road topology regenerates with authored records present")
	_check(
		restored_edge == locked_edge
		and is_equal_approx(restored_edge.terrain_cost, 9876.5)
		and restored_edge.metadata.get("review_marker") == "preserved",
		"locked road edges survive regeneration without replacement"
	)
	_check(
		restored_node == overridden_node and restored_node.world_position == overridden_position,
		"overridden road nodes survive regeneration without replacement"
	)
	_check(
		locked_edge_id in restored_node.incident_edge_ids,
		"derived incident-edge metadata is rebuilt around preserved topology"
	)
	var generated_edges_follow_override := true
	for edge in world.get_road_edges():
		if edge.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
			continue
		var from_node := world.get_record(edge.from_node_id) as FoundationRoadNode
		var to_node := world.get_record(edge.to_node_id) as FoundationRoadNode
		generated_edges_follow_override = (
			generated_edges_follow_override
			and Vector2(edge.route_points[0].x, edge.route_points[0].z)
				== Vector2(from_node.world_position.x, from_node.world_position.z)
			and Vector2(edge.route_points[-1].x, edge.route_points[-1].z)
				== Vector2(to_node.world_position.x, to_node.world_position.z)
		)
	_check(
		generated_edges_follow_override,
		"regenerated edges route from preserved overridden road-node positions"
	)
	var state_manifest := FoundationWorldData.from_dict(world.to_dict())
	_check(
		state_manifest.get_record(locked_edge_id).authorship_state == FoundationSpatialRecord.AuthorshipState.LOCKED
		and state_manifest.get_record(overridden_node_id).authorship_state == FoundationSpatialRecord.AuthorshipState.OVERRIDDEN,
		"locked and overridden road authorship states serialize round-trip"
	)


func _test_preserved_edge_connectivity(terrain: FoundationTerrainData, origin: Vector2i) -> void:
	var positions: Array[Vector3] = [
		Vector3(-132.0, 0.0, -132.0),
		Vector3(-128.0, 0.0, -1.0),
		Vector3(64.0, 0.0, -96.0),
		Vector3(132.0, 0.0, 132.0),
	]
	var world := _make_world(2026, positions)
	FoundationRoadTopologyGenerator.generate(world, terrain, origin)
	var leaf_node: FoundationRoadNode
	for node in world.get_road_nodes():
		if node.incident_edge_ids.size() == 1:
			leaf_node = node
			break
	var changed_edge := world.get_record(leaf_node.incident_edge_ids[0]) as FoundationRoadEdge
	var duplicate_edge: FoundationRoadEdge
	for edge in world.get_road_edges():
		if edge != changed_edge:
			duplicate_edge = edge
			break
	var leaf_node_id := leaf_node.stable_id
	var changed_edge_id := changed_edge.stable_id
	changed_edge.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	changed_edge.from_node_id = duplicate_edge.from_node_id
	changed_edge.to_node_id = duplicate_edge.to_node_id
	var rerun := FoundationRoadTopologyGenerator.generate(world, terrain, origin)
	_check(rerun.success, "regeneration succeeds when an overridden edge changes endpoint identity")
	_check(
		world.get_record(changed_edge_id) == changed_edge,
		"endpoint-authored overridden edge data and object identity are preserved"
	)
	_check(
		_is_connected(world) and not (world.get_record(leaf_node_id) as FoundationRoadNode).incident_edge_ids.is_empty(),
		"actual preserved-edge connectivity seeds generation and reconnects the displaced leaf"
	)
	var repaired_snapshot := _topology_snapshot(world)
	FoundationRoadTopologyGenerator.generate(world, terrain, origin)
	_check(
		_topology_snapshot(world) == repaired_snapshot,
		"a deterministic repair edge reproduces when an authored edge occupies its original pair ID"
	)


func _test_preserved_record_reindex() -> void:
	var positions: Array[Vector3] = [Vector3(16.0, 0.0, 16.0), Vector3(600.0, 0.0, 16.0)]
	var world := _make_world(318, positions, Rect2(0.0, 0.0, 768.0, 256.0))
	var terrain := _make_flat_terrain(318, Vector2i(192, 64))
	FoundationRoadTopologyGenerator.generate(world, terrain)
	var moved_node: FoundationRoadNode
	for node in world.get_road_nodes():
		if is_equal_approx(node.world_position.x, 16.0):
			moved_node = node
			break
	var old_chunk := Vector2i(0, 0)
	var new_chunk := Vector2i(3, 0)
	var new_region := Vector2i(1, 0)
	moved_node.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	moved_node.set_world_position(Vector3(400.0, 5.0, 16.0))
	var rerun := FoundationRoadTopologyGenerator.generate(world, terrain)
	_check(rerun.success and world.get_record(moved_node.stable_id) == moved_node, "overridden node is retained while it is reindexed")
	_check(
		moved_node.owning_chunks == [new_chunk] and moved_node.owning_regions == [new_region],
		"preserved node ownership refreshes across chunk and region boundaries"
	)
	_check(
		moved_node not in world.get_records_in_chunk(old_chunk, FoundationWorldData.ROAD_NODE_LAYER)
		and moved_node in world.get_records_in_chunk(new_chunk, FoundationWorldData.ROAD_NODE_LAYER)
		and moved_node in world.get_records_in_region(new_region, FoundationWorldData.ROAD_NODE_LAYER),
		"preserved node moves from stale spatial buckets into its authored chunk and region"
	)
	_check(
		moved_node.stable_id not in world.get_chunk(old_chunk).get_record_ids(FoundationWorldData.ROAD_NODE_LAYER)
		and moved_node.stable_id in world.get_chunk(new_chunk).get_record_ids(FoundationWorldData.ROAD_NODE_LAYER),
		"abstract chunk record references are reindexed with preserved authored nodes"
	)
	_check(
		_generated_edges_terminate_at_nodes(world),
		"routes regenerated after reindexing terminate at the full 3D authored node positions"
	)


func _test_terrain_influence() -> void:
	var positions: Array[Vector3] = [Vector3(-52.0, 0.0, 0.0), Vector3(52.0, 0.0, 0.0)]
	var flat_world := _make_world(77, positions, Rect2(-64.0, -40.0, 128.0, 80.0))
	var blocked_world := _make_world(77, positions, Rect2(-64.0, -40.0, 128.0, 80.0))
	var ridge_world := _make_world(77, positions, Rect2(-64.0, -40.0, 128.0, 80.0))
	var surface_world := _make_world(77, positions, Rect2(-64.0, -40.0, 128.0, 80.0))
	var flat := _make_flat_terrain(77, Vector2i(32, 20))
	var blocked := _make_flat_terrain(77, Vector2i(32, 20))
	var ridge := _make_flat_terrain(77, Vector2i(32, 20))
	var surface := _make_flat_terrain(77, Vector2i(32, 20))
	for cell_y in range(1, 19):
		blocked.set_cell_flags(Vector2i(16, cell_y), FoundationTerrainData.CellFlag.PROTECTED, false)
		surface.set_cell_surface(Vector2i(16, cell_y), FoundationTerrainSurface.Type.WETLAND, false)
	for vertex_x in range(15, 19):
		for vertex_y in range(1, 20):
			ridge.set_vertex_height(
				Vector2i(vertex_x, vertex_y),
				40.0,
				FoundationTerrainData.ModificationSource.MANUAL,
				false
			)
	var blocked_revision := blocked.revision
	var origin := Vector2i(-16, -10)
	var profile := FoundationRoadGenerationProfile.new()
	profile.protected_penalty = 10000.0
	profile.wetland_penalty = 10000.0
	profile.slope_cost_weight = 100.0
	FoundationRoadTopologyGenerator.generate(flat_world, flat, origin, profile)
	FoundationRoadTopologyGenerator.generate(blocked_world, blocked, origin, profile)
	FoundationRoadTopologyGenerator.generate(ridge_world, ridge, origin, profile)
	FoundationRoadTopologyGenerator.generate(surface_world, surface, origin, profile)
	var flat_edge := flat_world.get_road_edges()[0]
	var blocked_edge := blocked_world.get_road_edges()[0]
	var ridge_edge := ridge_world.get_road_edges()[0]
	var surface_edge := surface_world.get_road_edges()[0]
	_check(
		_points_snapshot(flat_edge.route_points) != _points_snapshot(blocked_edge.route_points),
		"terrain flags influence the deterministic route polyline"
	)
	_check(
		blocked_edge.planar_length > flat_edge.planar_length,
		"terrain-aware routing accepts a longer corridor to avoid protected cells"
	)
	var avoids_protected := true
	for point in blocked_edge.route_points:
		var global_cell := Vector2i(floori(point.x / 4.0), floori(point.z / 4.0))
		var local_cell := global_cell - origin
		if blocked.is_valid_cell(local_cell):
			avoids_protected = avoids_protected and (blocked.get_cell_flags(local_cell) & FoundationTerrainData.CellFlag.PROTECTED) == 0
	_check(avoids_protected, "selected road route avoids high-penalty protected terrain")
	_check(
		_points_snapshot(ridge_edge.route_points) != _points_snapshot(flat_edge.route_points)
		and ridge_edge.planar_length > flat_edge.planar_length,
		"terrain height and slope costs cause a deterministic ridge detour"
	)
	_check(
		_points_snapshot(surface_edge.route_points) != _points_snapshot(flat_edge.route_points)
		and surface_edge.planar_length > flat_edge.planar_length,
		"explicit terrain surface costs influence deterministic routing"
	)
	_check(blocked.revision == blocked_revision, "terrain-aware routing reads but never grades or edits terrain")


func _test_debug_contract(world: FoundationWorldData) -> void:
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"road_topology")
	var provider := registry.get_provider(&"road_topology")
	var builder := registry.build(world)
	_check(builder.line_purposes.has(&"road_node_generated"), "road debug provider emits abstract node markers")
	_check(builder.line_purposes.has(&"road_edge_generated"), "road debug provider emits batched route-edge segments")
	var has_metadata_label := false
	for label: Dictionary in builder.labels:
		var text := String(label.get("text", ""))
		has_metadata_label = has_metadata_label or ("cost" in text and "max" in text)
	_check(has_metadata_label, "road debug labels expose useful topology cost and slope metadata")
	var first_edge := world.get_road_edges()[0]
	var debug_offset := float(
		world.get_layer(FoundationWorldData.ROAD_EDGE_LAYER).metadata["profile"]["debug_elevation_offset"]
	)
	_check(
		not builder.line_vertices.is_empty()
		and builder.line_vertices[0] == first_edge.route_points[0] + Vector3.UP * debug_offset,
		"road debug provider applies visual elevation without changing authoritative route points"
	)
	var invocation_count := provider.invocation_count
	registry.set_layer_enabled(&"road_topology", false)
	var disabled := registry.build(world)
	_check(disabled.get_primitive_count() == 0, "disabled road topology debug creates no primitives")
	_check(provider.invocation_count == invocation_count, "disabled road topology debug invokes no provider work")

	var world_node := FoundationWorld.new()
	world_node.initialize_on_ready = false
	world_node.world_data = world
	root.add_child(world_node)
	var debug_view := FoundationDebugView.new()
	debug_view.show_world_bounds = false
	debug_view.show_regions = false
	debug_view.show_chunks = false
	debug_view.show_terrain_grid = false
	debug_view.show_records = false
	debug_view.show_anchors = false
	debug_view.show_relationships = false
	debug_view.show_road_topology = true
	world_node.add_child(debug_view)
	debug_view.rebuild()
	_check(debug_view.get_node_or_null("BatchedLines") != null, "runtime topology visualization uses one batched line mesh")
	_check(debug_view.get_node_or_null("BatchedFills") != null, "runtime debug retains one shared fill batch instead of road meshes")
	world_node.free()


func _test_issue_9_pattern_graph_contract() -> void:
	var positions: Array[Vector3] = [
		Vector3(-180.0, 0.0, -180.0),
		Vector3(180.0, 0.0, -180.0),
		Vector3(0.0, 0.0, 180.0),
		Vector3(180.0, 0.0, 180.0),
	]
	var first_world := _make_world(9001, positions)
	var second_world := _make_world(9001, positions)
	var changed_world := _make_world(9002, positions)
	_add_issue_9_patterns(first_world, false)
	_add_issue_9_patterns(second_world, true)
	_add_issue_9_patterns(changed_world, false)
	var first_terrain := _make_flat_terrain(9001, Vector2i(128, 128))
	var second_terrain := _make_flat_terrain(9001, Vector2i(128, 128))
	var changed_terrain := _make_flat_terrain(9002, Vector2i(128, 128))
	var origin := Vector2i(-64, -64)
	var first_result := FoundationRoadTopologyGenerator.generate(first_world, first_terrain, origin)
	var second_result := FoundationRoadTopologyGenerator.generate(second_world, second_terrain, origin)
	var changed_result := FoundationRoadTopologyGenerator.generate(changed_world, changed_terrain, origin)
	_check(
		first_result.success and second_result.success and changed_result.success,
		"Issue #9 road graph generates for grid, suburban, and rural pattern inputs"
	)
	_check(
		_road_graph_snapshot(first_world) == _road_graph_snapshot(second_world),
		"dictionary and registration order do not perturb deterministic Phase 2 graph identity"
	)
	_check(
		_local_topology_snapshot(first_world) != _local_topology_snapshot(changed_world),
		"different world seeds change eligible local pattern topology"
	)
	var issue_codes := _validation_codes(first_result.validation_issues)
	var changed_issue_codes := _validation_codes(changed_result.validation_issues)
	_check(
		&"unreachable_mandatory_anchor" not in issue_codes
		and &"unreachable_mandatory_anchor" not in changed_issue_codes,
		"different seeds preserve mandatory anchor reachability"
	)
	_check(
		first_result.mandatory_anchor_count >= 3,
		"major centers, map exits, and external destinations carry explicit mandatory intent"
	)
	var pattern_families: Dictionary = {}
	var classes: Dictionary = {}
	var has_complete_edge_contract := true
	for edge in first_world.get_road_edges():
		classes[edge.road_class] = true
		if edge.metadata.has("pattern_family"):
			pattern_families[StringName(edge.metadata["pattern_family"])] = true
		has_complete_edge_contract = has_complete_edge_contract and (
			not String(edge.physical_profile_key).is_empty()
			and not String(edge.logical_road_id).is_empty()
			and not String(edge.directionality).is_empty()
			and not String(edge.access_control_policy).is_empty()
			and not edge.allowed_movement_modes.is_empty()
			and not edge.desired_elevation_samples.is_empty()
			and edge.grading_requirements.has("maximum_cut_depth")
		)
	_check(
		pattern_families.has(FoundationRoadPatternArea.DOWNTOWN_GRID)
		and pattern_families.has(FoundationRoadPatternArea.SUBURBAN_LOOPS)
		and pattern_families.has(FoundationRoadPatternArea.RURAL_TERRAIN_FOLLOWING),
		"three district-style pattern families produce visibly distinct abstract topology"
	)
	_check(
		classes.has(FoundationRoadEdge.CLASS_LOCAL)
		and classes.has(FoundationRoadEdge.CLASS_COLLECTOR)
		and classes.has(FoundationRoadEdge.CLASS_DIRT),
		"pattern inputs generate local, collector, and terrain-following dirt-road hierarchy"
	)
	var functional_classes: Array[StringName] = [
		FoundationRoadEdge.CLASS_HIGHWAY,
		FoundationRoadEdge.CLASS_ARTERIAL,
		FoundationRoadEdge.CLASS_COLLECTOR,
		FoundationRoadEdge.CLASS_LOCAL,
		FoundationRoadEdge.CLASS_ALLEY,
		FoundationRoadEdge.CLASS_DIRT,
	]
	var unique_classes: Dictionary = {}
	for road_class in functional_classes:
		unique_classes[road_class] = true
	_check(unique_classes.size() == 6, "all six Phase 2 functional road classes have stable distinct identities")
	_check(has_complete_edge_contract, "every generated edge preserves hierarchy, physical-form, access, movement, logical, and grading seams")
	_check(
		not first_world.get_logical_roads().is_empty()
		and first_result.generated_logical_road_count == first_world.get_logical_roads().size(),
		"deterministic logical-road records continue identity across graph edges"
	)
	_check(
		not first_world.get_road_intersections().is_empty()
		and first_result.generated_intersection_count == first_world.get_road_intersections().size(),
		"abstract intersection records expose degree and topology without physical geometry"
	)
	var extended_spatial_records: Array[FoundationSpatialRecord] = []
	extended_spatial_records.append_array(first_world.get_road_pattern_areas())
	extended_spatial_records.append_array(first_world.get_logical_roads())
	extended_spatial_records.append_array(first_world.get_road_intersections())
	var extended_indexed := true
	for record in extended_spatial_records:
		extended_indexed = extended_indexed and not record.owning_chunks.is_empty()
		for chunk in record.owning_chunks:
			extended_indexed = extended_indexed and record in first_world.get_records_in_chunk(chunk, record.layer_type)
	_check(extended_indexed, "patterns, logical roads, and intersections register in every owning spatial bucket")
	_check(
		FoundationRoadGenerationProfile.SEED_STREAMS == [
			&"road_anchor_candidates", &"road_major_connections", &"road_collectors",
			&"road_local_growth", &"road_loops", &"road_dead_ends", &"road_logical_identity",
		],
		"Phase 2 uses named independent deterministic seed streams"
	)
	_check(
		&"self_edge" not in issue_codes and &"duplicate_edge" not in issue_codes,
		"generated graph contains no self-edges or duplicate node-pair edges"
	)
	var restored := FoundationWorldData.from_dict(first_world.to_dict())
	_check(
		_road_graph_snapshot(restored) == _road_graph_snapshot(first_world),
		"extended road graph, patterns, logical roads, intersections, grading, and identity serialize round-trip"
	)
	_check(
		restored.get_road_pattern_areas()[0] is FoundationRoadPatternArea
		and restored.get_logical_roads()[0] is FoundationLogicalRoad
		and restored.get_road_intersections()[0] is FoundationIntersectionRecord,
		"extended Phase 2 serialization restores typed Node-free records"
	)
	var authored_pattern := first_world.get_road_pattern_areas()[0]
	var authored_logical := first_world.get_logical_roads()[0]
	var authored_intersection := first_world.get_road_intersections()[0]
	authored_pattern.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	authored_pattern.metadata["authored_marker"] = "pattern"
	authored_logical.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	authored_logical.metadata["authored_marker"] = "logical"
	authored_intersection.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	authored_intersection.metadata["authored_marker"] = "intersection"
	var authored_rerun := FoundationRoadTopologyGenerator.generate(first_world, first_terrain, origin)
	_check(
		authored_rerun.success
		and first_world.get_record(authored_pattern.stable_id) == authored_pattern
		and first_world.get_record(authored_logical.stable_id) == authored_logical
		and first_world.get_record(authored_intersection.stable_id) == authored_intersection,
		"pattern, logical-road, and intersection authored objects survive regeneration"
	)
	_check(
		authored_pattern.metadata.get("authored_marker") == "pattern"
		and authored_logical.metadata.get("authored_marker") == "logical"
		and authored_intersection.metadata.get("authored_marker") == "intersection",
		"extended Phase 2 authored data remains exact during regeneration"
	)
	var authored_restored := FoundationWorldData.from_dict(first_world.to_dict())
	_check(
		authored_restored.get_record(authored_pattern.stable_id).authorship_state == FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
		and authored_restored.get_record(authored_logical.stable_id).authorship_state == FoundationSpatialRecord.AuthorshipState.LOCKED
		and authored_restored.get_record(authored_intersection.stable_id).authorship_state == FoundationSpatialRecord.AuthorshipState.OVERRIDDEN,
		"extended generated/locked/overridden states serialize round-trip"
	)
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id in [&"road_topology", &"road_costs", &"road_candidates", &"road_validation"])
	var before_debug := _road_graph_snapshot(first_world)
	var builder := registry.build(first_world)
	_check(
		builder.line_purposes.has(&"road_class_local")
		and builder.line_purposes.has(&"road_pattern_grid")
		and builder.line_purposes.has(&"road_candidate_accepted")
		and builder.line_purposes.has(&"road_intersection")
		and not builder.triangle_vertices.is_empty(),
		"batched debug exposes hierarchy, patterns, candidates, intersections, and routing-cost heatmap"
	)
	var has_logical_label := false
	for label: Dictionary in builder.labels:
		has_logical_label = has_logical_label or "logical" in String(label.get("text", ""))
	_check(has_logical_label, "debug labels expose logical-road continuity and topology metadata")
	_check(_road_graph_snapshot(first_world) == before_debug, "rich road debug providers never mutate road or world data")
	var planning_invocations: Dictionary = {}
	for provider_id in registry.get_provider_ids():
		planning_invocations[provider_id] = registry.get_provider(provider_id).invocation_count
		registry.set_layer_enabled(provider_id, false)
	var fully_disabled := registry.build(first_world)
	var no_disabled_work := fully_disabled.get_primitive_count() == 0
	for provider_id in planning_invocations:
		no_disabled_work = no_disabled_work and (
			registry.get_provider(provider_id).invocation_count == int(planning_invocations[provider_id])
		)
	_check(no_disabled_work, "disabled topology, cost, candidate, and validation providers perform zero work")


func _test_issue_9_grading_and_validation() -> void:
	var world := _make_world(
		404,
		[Vector3(-52.0, 0.0, 0.0), Vector3(52.0, 0.0, 0.0)],
		Rect2(-64.0, -40.0, 128.0, 80.0)
	)
	var terrain := _make_flat_terrain(404, Vector2i(32, 20))
	for vertex_x in range(14, 19):
		for vertex_y in range(0, 21):
			terrain.set_vertex_height(
				Vector2i(vertex_x, vertex_y), 32.0,
				FoundationTerrainData.ModificationSource.MANUAL, false
			)
	var terrain_before := _terrain_snapshot(terrain)
	var profile := FoundationRoadGenerationProfile.new()
	profile.max_expanded_cells = 1
	var result := FoundationRoadTopologyGenerator.generate(world, terrain, Vector2i(-16, -10), profile)
	var edge := world.get_road_edges()[0]
	_check(result.success and edge.used_fallback_route, "difficult terrain retains mandatory connectivity through a reported fallback route")
	_check(
		float(edge.grading_requirements.get("maximum_cut_depth", 0.0)) > 0.0
		and bool(edge.grading_requirements.get("retaining_wall_candidate", false))
		and bool(edge.grading_requirements.get("infeasible_segment", false)),
		"difficult terrain records desired elevation, cut depth, and retaining-wall requirements"
	)
	_check(_terrain_snapshot(terrain) == terrain_before, "grading reports remain planning data and never deform terrain")

	var patterned := _make_world(
		405,
		[Vector3(-180.0, 0.0, -180.0), Vector3(180.0, 0.0, -180.0), Vector3(0.0, 0.0, 180.0)]
	)
	_add_issue_9_patterns(patterned, false)
	var patterned_result := FoundationRoadTopologyGenerator.generate(
		patterned,
		_make_flat_terrain(405, Vector2i(128, 128)),
		Vector2i(-64, -64)
	)
	var junction: FoundationRoadNode
	for intersection in patterned.get_road_intersections():
		var candidate := patterned.get_record(intersection.node_id) as FoundationRoadNode
		var has_local := false
		var collector_edge: FoundationRoadEdge
		for edge_id in candidate.incident_edge_ids:
			var candidate_edge := patterned.get_record(edge_id) as FoundationRoadEdge
			has_local = has_local or candidate_edge.road_class == FoundationRoadEdge.CLASS_LOCAL
			if candidate_edge.road_class == FoundationRoadEdge.CLASS_COLLECTOR:
				collector_edge = candidate_edge
		if has_local and collector_edge != null:
			junction = candidate
			collector_edge.road_class = FoundationRoadEdge.CLASS_HIGHWAY
			break
	var hierarchy_issues := FoundationRoadTopologyValidator.validate(patterned)
	_check(
		junction != null and &"class_incompatible_connection" in _validation_codes(hierarchy_issues),
		"topology validator rejects direct highway-to-local access"
	)
	_check(
		&"excessive_intersection_proximity" not in _validation_codes(patterned_result.validation_issues),
		"generator enforces configured minimum spacing for its abstract intersections"
	)


func _test_issue_9_demo_contract() -> void:
	var scene := load("res://demo/spatial_model_demo.tscn") as PackedScene
	var demo := scene.instantiate()
	root.add_child(demo)
	var demo_world := demo.get_node("FoundationWorld") as FoundationWorld
	var data := demo_world.world_data
	var classes: Dictionary = {}
	for edge in data.get_road_edges():
		classes[edge.road_class] = true
	_check(data.get_anchors().size() >= 5, "Phase 2 demo spans several meaningful city-anchor categories")
	_check(data.get_road_pattern_areas().size() == 3, "Phase 2 demo enables downtown, suburban, and rural pattern areas")
	_check(
		classes.has(FoundationRoadEdge.CLASS_ARTERIAL)
		and classes.has(FoundationRoadEdge.CLASS_COLLECTOR)
		and classes.has(FoundationRoadEdge.CLASS_LOCAL)
		and classes.has(FoundationRoadEdge.CLASS_DIRT),
		"Phase 2 demo visibly includes major roads, collectors, local roads, and rural dirt roads"
	)
	_check(
		not data.get_logical_roads().is_empty() and not data.get_road_intersections().is_empty(),
		"Phase 2 demo exposes logical-road labels and abstract intersection markers"
	)
	_check(
		demo.get_node_or_null("%SeedSpin") != null
		and demo.get_node_or_null("%RegenerateButton") != null
		and demo.get_node_or_null("%ClearRoadButton") != null,
		"Phase 2 demo provides seed/profile, selected-stage regeneration, and clear controls"
	)
	var before := _road_graph_snapshot(data)
	demo.call("_regenerate_selected_stage")
	_check(_road_graph_snapshot(data) == before, "same-seed full demo regeneration reproduces identical graph records")
	var stage_options := demo.get_node("%StageOptions") as OptionButton
	stage_options.select(1)
	demo.call("_regenerate_selected_stage")
	_check(_road_graph_snapshot(data) == before, "selected derived stage reproduces logical roads and intersections without rerouting")
	demo.call("_clear_road_data")
	_check(
		data.get_road_nodes().is_empty() and data.get_road_edges().is_empty()
		and data.get_logical_roads().is_empty() and data.get_road_intersections().is_empty()
		and data.get_road_pattern_areas().size() == 3,
		"clear control removes generated road outputs while preserving pattern inputs"
	)
	demo.free()


func _test_scope_exclusions(world: FoundationWorldData) -> void:
	var node := world.get_road_nodes()[0]
	var edge := world.get_road_edges()[0]
	_check(
		ClassDB.is_parent_class(node.get_class(), "RefCounted")
		and not ClassDB.is_parent_class(node.get_class(), "Node"),
		"road nodes remain abstract data rather than scene or mesh nodes"
	)
	_check(
		ClassDB.is_parent_class(edge.get_class(), "RefCounted")
		and not ClassDB.is_parent_class(edge.get_class(), "Node"),
		"road edges remain abstract data rather than scene or mesh nodes"
	)
	var pattern := FoundationRoadPatternArea.new()
	var logical := FoundationLogicalRoad.new()
	var intersection := FoundationIntersectionRecord.new()
	var elevation_sample := FoundationRoadElevationSample.new()
	var validation_issue := FoundationRoadValidationIssue.new()
	var extended_contracts: Array[RefCounted] = [pattern, logical, intersection, elevation_sample, validation_issue]
	var all_node_free := true
	for record in extended_contracts:
		all_node_free = all_node_free and not ClassDB.is_parent_class(record.get_class(), "Node")
	_check(all_node_free, "pattern, logical-road, intersection, grading, and validation contracts remain Node-free data")
	var forbidden_methods := [
		&"build_road_mesh", &"create_lane", &"add_lane", &"create_physical_intersection",
		&"spawn_traffic", &"grade_terrain", &"find_gameplay_path", &"create_navigation_mesh",
		&"create_block", &"subdivide_parcels", &"generate_addresses",
	]
	var has_out_of_scope_api := false
	for method_name in forbidden_methods:
		has_out_of_scope_api = (
			has_out_of_scope_api
			or node.has_method(method_name)
			or edge.has_method(method_name)
			or world.has_method(method_name)
		)
	_check(not has_out_of_scope_api, "Phase 2 exposes no road mesh, lane, navigation, traffic, physical intersection, grading, block, parcel, or address API")


func _make_world(
	seed: int,
	positions: Array[Vector3],
	bounds := Rect2(-256.0, -256.0, 512.0, 512.0)
) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 2
	metadata.content_pack_version = &"phase-2-tests"
	metadata.world_bounds = bounds
	var coordinates := FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(32, 32), Vector2i(2, 2))
	var world := FoundationWorldData.new(metadata, coordinates)
	world.initialize_default_layers()
	world.initialize_partitions()
	var categories: Array[StringName] = [
		FoundationCityAnchor.CATEGORY_CITY_CENTER,
		FoundationCityAnchor.CATEGORY_MAP_EXIT,
		FoundationCityAnchor.CATEGORY_DISTRICT_SEED,
		FoundationCityAnchor.CATEGORY_EXTERNAL_DESTINATION,
	]
	for index in range(positions.size()):
		var anchor := FoundationCityAnchor.create(
			metadata,
			categories[index % categories.size()],
			positions[index],
			"phase-2-anchor-%d" % index,
			0.0,
			1.0 - minf(0.6, index * 0.1)
		)
		anchor.source_pass = &"phase_2_test_fixture"
		world.register_record(anchor)
	return world


func _make_flat_terrain(seed: int, grid_cells: Vector2i) -> FoundationTerrainData:
	var terrain := FoundationTerrainData.new(seed, grid_cells, 4.0, 1.0, Vector2i(32, 32), 1, &"phase-2-tests")
	terrain.clear_dirty_chunks()
	return terrain


func _add_issue_9_patterns(world: FoundationWorldData, reverse_order: bool) -> void:
	var downtown := FoundationRoadPatternArea.create(
		world.metadata, "downtown-test", Rect2(-140.0, -130.0, 100.0, 100.0),
		FoundationRoadPatternArea.DOWNTOWN_GRID
	)
	downtown.preferred_orientation_degrees = 0.0
	downtown.preferred_spacing = 28.0
	downtown.grid_strength = 1.0
	var suburban := FoundationRoadPatternArea.create(
		world.metadata, "suburban-test", Rect2(20.0, -130.0, 120.0, 100.0),
		FoundationRoadPatternArea.SUBURBAN_LOOPS
	)
	suburban.preferred_orientation_degrees = 18.0
	suburban.preferred_spacing = 24.0
	suburban.curvature_allowance = 1.0
	suburban.loop_preference = 1.0
	var rural := FoundationRoadPatternArea.create(
		world.metadata, "rural-test", Rect2(-80.0, 50.0, 160.0, 90.0),
		FoundationRoadPatternArea.RURAL_TERRAIN_FOLLOWING
	)
	rural.preferred_orientation_degrees = 12.0
	rural.preferred_spacing = 32.0
	rural.terrain_following_strength = 1.0
	var patterns: Array[FoundationRoadPatternArea] = [downtown, suburban, rural]
	if reverse_order:
		patterns.reverse()
	for pattern in patterns:
		pattern.source_pass = &"phase_2_test_pattern"
		world.register_record(pattern)


func _is_connected(world: FoundationWorldData) -> bool:
	var nodes := world.get_road_nodes()
	if nodes.is_empty():
		return true
	var visited: Dictionary = {}
	var pending: Array[StringName] = [nodes[0].stable_id]
	while not pending.is_empty():
		var node_id: StringName = pending.pop_front()
		if visited.has(node_id):
			continue
		visited[node_id] = true
		var node := world.get_record(node_id) as FoundationRoadNode
		for edge_id in node.incident_edge_ids:
			var edge := world.get_record(edge_id) as FoundationRoadEdge
			var other := edge.other_node(node_id)
			if not visited.has(other):
				pending.append(other)
	return visited.size() == nodes.size()


func _generated_edges_terminate_at_nodes(world: FoundationWorldData) -> bool:
	for edge in world.get_road_edges():
		if edge.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
			continue
		if edge.route_points.is_empty():
			return false
		var from_node := world.get_record(edge.from_node_id) as FoundationRoadNode
		var to_node := world.get_record(edge.to_node_id) as FoundationRoadNode
		if from_node == null or to_node == null:
			return false
		if edge.route_points[0] != from_node.world_position:
			return false
		if edge.route_points[-1] != to_node.world_position:
			return false
	return true


func _topology_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for node in world.get_road_nodes():
		records.append(node.to_dict())
	for edge in world.get_road_edges():
		records.append(edge.to_dict())
	return JSON.stringify(records)


func _road_graph_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for pattern in world.get_road_pattern_areas():
		records.append(pattern.to_dict())
	for node in world.get_road_nodes():
		records.append(node.to_dict())
	for edge in world.get_road_edges():
		records.append(edge.to_dict())
	for logical in world.get_logical_roads():
		records.append(logical.to_dict())
	for intersection in world.get_road_intersections():
		records.append(intersection.to_dict())
	return JSON.stringify(records)


func _local_topology_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for edge in world.get_road_edges():
		if edge.generation_source in [&"pattern_growth", &"pattern_connection"]:
			records.append({
				"class": String(edge.road_class),
				"points": _points_snapshot(edge.route_points),
			})
	return JSON.stringify(records)


func _validation_codes(issues: Array[FoundationRoadValidationIssue]) -> Array[StringName]:
	var codes: Array[StringName] = []
	for issue in issues:
		if issue.code not in codes:
			codes.append(issue.code)
	codes.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return codes


func _anchor_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for anchor in world.get_anchors():
		records.append(anchor.to_dict())
	return JSON.stringify(records)


func _terrain_snapshot(terrain: FoundationTerrainData) -> String:
	return JSON.stringify({
		"revision": terrain.revision,
		"heights": Array(terrain.vertex_heights),
		"flags": Array(terrain.cell_flags),
		"surfaces": Array(terrain.cell_surfaces),
		"diagonals": Array(terrain.cell_diagonals),
		"dirty": terrain.get_dirty_chunks(),
	})


func _points_snapshot(points: PackedVector3Array) -> String:
	var serialized: Array[Dictionary] = []
	for point in points:
		serialized.append({"x": point.x, "y": point.y, "z": point.z})
	return JSON.stringify(serialized)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
