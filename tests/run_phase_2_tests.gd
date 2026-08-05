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
	_test_terrain_influence()
	_test_debug_contract(world)
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
	var forbidden_methods := [
		&"build_mesh", &"create_lane", &"add_lane", &"create_intersection",
		&"spawn_traffic", &"grade_terrain", &"find_gameplay_path", &"create_navigation_mesh",
	]
	var has_out_of_scope_api := false
	for method_name in forbidden_methods:
		has_out_of_scope_api = (
			has_out_of_scope_api
			or node.has_method(method_name)
			or edge.has_method(method_name)
			or world.has_method(method_name)
		)
	_check(not has_out_of_scope_api, "Phase 2 exposes no mesh, lane, navigation, traffic, intersection, or grading API")


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


func _topology_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for node in world.get_road_nodes():
		records.append(node.to_dict())
	for edge in world.get_road_edges():
		records.append(edge.to_dict())
	return JSON.stringify(records)


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
