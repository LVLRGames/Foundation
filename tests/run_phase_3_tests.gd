extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline := _test_rectangle_and_determinism()
	var rectangle_world := baseline[0] as FoundationWorldData
	_test_concave_l_shape()
	_test_adjacent_shared_faces()
	_test_crossing_planarization()
	_test_open_chains_and_spurs()
	_test_rejections_and_disconnected_components()
	_test_negative_boundary_ownership()
	_test_authored_regeneration_and_serialization()
	_test_non_mutation()
	_test_debug_contract(rectangle_world)
	_test_bounded_candidate_work()
	_test_demo_contract()
	_test_scope_exclusions(rectangle_world)

	if _failures.is_empty():
		print("Foundation Phase 3 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 3 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_rectangle_and_determinism() -> Array:
	var boundary := PackedVector2Array([
		Vector2(-64.0, -32.0), Vector2(0.0, -32.0), Vector2(64.0, -32.0),
		Vector2(64.0, 48.0), Vector2(-64.0, 48.0), Vector2(-64.0, -32.0),
	])
	var first_world := _make_world(3001)
	var second_world := _make_world(3001)
	_add_road(first_world, "rectangle", boundary)
	_add_road(second_world, "rectangle", boundary)
	var roads_before := _road_snapshot(first_world)
	var first_result := FoundationBlockExtractor.generate(first_world)
	var second_result := FoundationBlockExtractor.generate(second_world)
	_check(first_result.success and second_result.success, "rectangle extraction succeeds")
	_check(first_world.get_blocks().size() == 1, "simple rectangular loop produces exactly one bounded block")
	_check(
		_block_snapshot(first_world) == _block_snapshot(second_world)
		and JSON.stringify(first_result.to_dict()) == JSON.stringify(second_result.to_dict()),
		"same road topology and profile reproduce block IDs, polygons, metrics, provenance, diagnostics, and ordering"
	)
	var block := first_world.get_blocks()[0]
	_check(block.outer_boundary.size() == 4, "canonical rectangle removes duplicate closing and collinear points")
	_check(is_equal_approx(block.area, 10240.0) and is_equal_approx(block.perimeter, 416.0), "block area and perimeter are deterministic")
	_check(
		block.world_bounds == Rect2(-64.0, -32.0, 128.0, 80.0)
		and block.centroid.is_equal_approx(Vector2(0.0, 8.0)),
		"block bounds and polygon centroid are derived from the canonical face"
	)
	_check(
		block.outer_boundary[0] == Vector2(-64.0, -32.0)
		and FoundationBlockRecord._signed_area(block.outer_boundary) > 0.0,
		"block winding and canonical starting vertex are normalized"
	)
	_check(
		block.boundary_references.size() == 5
		and block.boundary_road_ids.size() == 1
		and is_equal_approx(float(block.frontage_by_road[block.boundary_road_ids[0]]), block.perimeter),
		"boundary provenance and frontage lengths retain source-road segment spans"
	)
	_check(Geometry2D.is_point_in_polygon(block.label_point, block.outer_boundary), "stable block label point lies inside its boundary")
	_check(_road_snapshot(first_world) == roads_before, "block extraction does not mutate source roads")
	_check(first_result.exterior_face_count == 1, "the unbounded exterior walk is counted but never registered")
	_check(
		first_world.get_layer(FoundationWorldData.BLOCK_LAYER).metadata.has("profile")
		and first_world.get_layer(FoundationWorldData.BLOCK_LAYER).metadata.has("diagnostics"),
		"block layer stores versioned profile and deterministic diagnostics metadata"
	)
	return [first_world, first_result]


func _test_concave_l_shape() -> void:
	var world := _make_world(3002)
	_add_road(world, "l-shape", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(120.0, 0.0), Vector2(120.0, 40.0),
		Vector2(40.0, 40.0), Vector2(40.0, 120.0), Vector2(0.0, 120.0),
		Vector2(0.0, 0.0),
	]))
	var result := FoundationBlockExtractor.generate(world)
	_check(result.success and world.get_blocks().size() == 1, "irregular concave L-shaped loop produces one valid block")
	var block := world.get_blocks()[0]
	_check(block.outer_boundary.size() == 6 and _is_concave(block.outer_boundary), "L-shaped block remains concave without rectangular assumptions")
	_check(is_equal_approx(block.area, 8000.0), "concave block metric uses its canonical polygon rather than bounds")
	_check(Geometry2D.is_point_in_polygon(block.label_point, block.outer_boundary), "concave block receives a stable interior label point")
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"blocks")
	var builder := registry.build(world)
	_check(
		builder.triangle_vertices.size() == (block.outer_boundary.size() - 2) * 3
		and is_equal_approx(_triangle_area(builder.triangle_vertices), block.area),
		"batched debug triangulation fills a concave block without covering its missing corner"
	)


func _test_adjacent_shared_faces() -> void:
	var world := _make_world(3003, Rect2(-64.0, -64.0, 384.0, 256.0))
	var left := _add_road(world, "left-loop", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0),
		Vector2(0.0, 100.0), Vector2(0.0, 0.0),
	]))
	var right := _add_road(world, "right-loop", PackedVector2Array([
		Vector2(100.0, 0.0), Vector2(200.0, 0.0), Vector2(200.0, 100.0),
		Vector2(100.0, 100.0), Vector2(100.0, 0.0),
	]))
	FoundationBlockExtractor.generate(world)
	_check(world.get_blocks().size() == 2, "adjacent loops produce two distinct bounded faces")
	var shared_consistent := true
	for block in world.get_blocks():
		shared_consistent = (
			shared_consistent
			and left.stable_id in block.boundary_road_ids
			and right.stable_id in block.boundary_road_ids
			and float(block.frontage_by_road.get(left.stable_id, 0.0)) > 0.0
			and float(block.frontage_by_road.get(right.stable_id, 0.0)) > 0.0
		)
	_check(shared_consistent, "adjacent faces preserve consistent shared-boundary road provenance")


func _test_crossing_planarization() -> void:
	var world := _make_world(3004)
	_add_road(world, "outer", PackedVector2Array([
		Vector2(-100.0, -100.0), Vector2(100.0, -100.0), Vector2(100.0, 100.0),
		Vector2(-100.0, 100.0), Vector2(-100.0, -100.0),
	]))
	_add_road(world, "horizontal", PackedVector2Array([Vector2(-100.0, 0.0), Vector2(100.0, 0.0)]))
	_add_road(world, "vertical", PackedVector2Array([Vector2(0.0, -100.0), Vector2(0.0, 100.0)]))
	var result := FoundationBlockExtractor.generate(world)
	_check(result.success and result.split_intersection_count > 0, "crossing road polylines are planarized deterministically")
	_check(world.get_blocks().size() == 4, "at-grade crossing chords split one outer loop into four bounded blocks")
	var all_areas_correct := true
	for block in world.get_blocks():
		all_areas_correct = all_areas_correct and is_equal_approx(block.area, 10000.0)
	_check(all_areas_correct, "planarized crossing faces retain correct canonical metrics")
	var separated_world := _make_world(3013)
	_add_road(separated_world, "grade-horizontal", PackedVector2Array([
		Vector2(-100.0, 0.0), Vector2(100.0, 0.0),
	]))
	_add_road(separated_world, "grade-vertical", PackedVector2Array([
		Vector2(0.0, -100.0), Vector2(0.0, 100.0),
	]), {"grade_separated": true, "grade_level": 1})
	var separated_result := FoundationBlockExtractor.generate(separated_world)
	_check(separated_result.split_intersection_count == 0, "explicit grade-separated metadata prevents an interior planar junction")


func _test_open_chains_and_spurs() -> void:
	var open_world := _make_world(3005)
	_add_road(open_world, "open-chain", PackedVector2Array([
		Vector2(-80.0, -20.0), Vector2(0.0, 40.0), Vector2(90.0, -10.0),
	]))
	_add_road(open_world, "dead-end", PackedVector2Array([Vector2(20.0, 80.0), Vector2(120.0, 120.0)]))
	var open_result := FoundationBlockExtractor.generate(open_world)
	_check(open_result.success and open_world.get_blocks().is_empty(), "open chains and dead ends produce no false blocks")
	_check(open_result.pruned_segment_count == open_result.input_segment_count, "degree-one open topology is pruned before face walking")

	var spur_world := _make_world(3006)
	_add_road(spur_world, "loop", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0),
		Vector2(0.0, 100.0), Vector2(0.0, 0.0),
	]))
	_add_road(spur_world, "culdesac-spur", PackedVector2Array([Vector2(0.0, 0.0), Vector2(45.0, 45.0)]))
	var spur_result := FoundationBlockExtractor.generate(spur_world)
	_check(spur_result.pruned_segment_count == 1 and spur_world.get_blocks().size() == 1, "cul-de-sac spur is removed without destroying its bounded loop")


func _test_rejections_and_disconnected_components() -> void:
	var tiny_world := _make_world(3007)
	_add_road(tiny_world, "tiny", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(4.0, 0.0), Vector2(4.0, 4.0),
		Vector2(0.0, 4.0), Vector2(0.0, 0.0),
	]))
	var tiny_result := FoundationBlockExtractor.generate(tiny_world)
	_check(tiny_world.get_blocks().is_empty() and tiny_result.rejected_face_count > 0, "faces below minimum area are rejected deterministically")
	_check(tiny_result.exterior_face_count == 0, "unbounded exterior never becomes a block record")
	var tiny_registry := FoundationDebugLayerRegistry.new()
	tiny_registry.register_phase_1_defaults()
	for provider_id in tiny_registry.get_provider_ids():
		tiny_registry.set_layer_enabled(provider_id, provider_id == &"blocks")
	var diagnostic_builder := tiny_registry.build(tiny_world)
	_check(
		diagnostic_builder.line_purposes.has(&"block_invalid")
		and not diagnostic_builder.labels.is_empty(),
		"located rejected-face diagnostics use the invalid debug marker and label state"
	)
	var self_intersection := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(100.0, 100.0),
		Vector2(0.0, 100.0), Vector2(100.0, 0.0),
	])
	_check(
		not FoundationBlockExtractor._is_simple_polygon(
			self_intersection,
			FoundationBlockGenerationProfile.new()
		),
		"self-intersecting candidate rings fail deterministic polygon validation"
	)

	var disconnected := _make_world(3008, Rect2(-256.0, -256.0, 1024.0, 512.0))
	_add_rectangle(disconnected, "west", Rect2(-180.0, -60.0, 80.0, 80.0))
	_add_rectangle(disconnected, "east", Rect2(420.0, -60.0, 80.0, 80.0))
	FoundationBlockExtractor.generate(disconnected)
	_check(disconnected.get_blocks().size() == 2, "disconnected road components independently produce their bounded faces")


func _test_negative_boundary_ownership() -> void:
	var world := _make_world(3009, Rect2(-512.0, -512.0, 1024.0, 1024.0))
	_add_rectangle(world, "signed-boundary", Rect2(-200.0, -160.0, 400.0, 320.0))
	FoundationBlockExtractor.generate(world)
	var block := world.get_blocks()[0]
	_check(
		Vector2i(-2, -2) in block.owning_chunks
		and Vector2i(1, 1) in block.owning_chunks,
		"negative and positive block extents use floor-based chunk ownership"
	)
	_check(block.owning_regions.size() > 1, "boundary-spanning block registers in every owning region")
	var indexed_everywhere := true
	for chunk in block.owning_chunks:
		indexed_everywhere = indexed_everywhere and block in world.get_records_in_chunk(chunk, FoundationWorldData.BLOCK_LAYER)
	for region in block.owning_regions:
		indexed_everywhere = indexed_everywhere and block in world.get_records_in_region(region, FoundationWorldData.BLOCK_LAYER)
	_check(indexed_everywhere, "block is directly queryable from all signed chunk and region buckets")


func _test_authored_regeneration_and_serialization() -> void:
	var world := _make_world(3010, Rect2(-128.0, -128.0, 1024.0, 384.0))
	_add_rectangle(world, "authored", Rect2(0.0, 0.0, 100.0, 100.0))
	FoundationBlockExtractor.generate(world)
	var block := world.get_blocks()[0]
	block.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	var locked_snapshot := JSON.stringify(block.to_dict())
	FoundationBlockExtractor.generate(world)
	_check(world.get_record(block.stable_id) == block and JSON.stringify(block.to_dict()) == locked_snapshot, "locked block survives regeneration exactly")

	block.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	var moved := PackedVector2Array()
	for point in block.outer_boundary:
		moved.append(point + Vector2(400.0, 0.0))
	block.set_outer_boundary(moved)
	var old_chunk := Vector2i(0, 0)
	var rerun := FoundationBlockExtractor.generate(world)
	_check(rerun.success and rerun.preserved_block_count == 1 and world.get_record(block.stable_id) == block, "overridden block object and authored data survive regeneration")
	_check(
		block.owning_chunks.has(Vector2i(3, 0))
		and block.owning_regions.has(Vector2i(1, 0))
		and block not in world.get_records_in_chunk(old_chunk, FoundationWorldData.BLOCK_LAYER),
		"authored block is reindexed across chunk and region boundaries without stale buckets"
	)
	_check(world.get_blocks().size() == 2, "deterministic repair identity preserves an authored collision and the extracted face")
	var repaired_snapshot := _block_snapshot(world)
	FoundationBlockExtractor.generate(world)
	_check(_block_snapshot(world) == repaired_snapshot, "authored collision repair identity reproduces on regeneration")

	var restored := FoundationWorldData.from_dict(world.to_dict())
	_check(_block_snapshot(restored) == _block_snapshot(world), "typed blocks, boundaries, provenance, metrics, states, and ownership serialize round-trip")
	var typed := true
	for restored_block in restored.get_blocks():
		typed = typed and restored_block is FoundationBlockRecord
	_check(typed, "world deserialization restores typed Node-free block records")
	_check(
		restored.get_layer(FoundationWorldData.BLOCK_LAYER).metadata.has("diagnostics")
		and restored.get_layer(FoundationWorldData.BLOCK_LAYER).metadata.has("profile"),
		"block diagnostics and generation profile metadata serialize with the layer"
	)
	var restored_profile := FoundationBlockGenerationProfile.from_dict(
		restored.get_layer(FoundationWorldData.BLOCK_LAYER).metadata["profile"]
	)
	_check(
		restored_profile.to_dict() == FoundationBlockGenerationProfile.new().to_dict(),
		"block generation profile has a versioned deterministic round-trip seam"
	)


func _test_non_mutation() -> void:
	var world := _make_world(3011)
	_add_rectangle(world, "non-mutating", Rect2(-80.0, -80.0, 160.0, 160.0))
	var anchor := FoundationCityAnchor.create(
		world.metadata,
		FoundationCityAnchor.CATEGORY_CITY_CENTER,
		Vector3(0.0, 0.0, 0.0),
		"phase-3-non-mutation"
	)
	world.register_record(anchor)
	var road_node := FoundationRoadNode.new(
		&"phase_3_non_mutation_road_node",
		Vector3(12.0, 0.0, 12.0),
		FoundationRoadNode.KIND_ANCHOR,
		anchor.stable_id
	)
	world.register_record(road_node)
	var terrain := FoundationTerrainData.new(
		3011,
		Vector2i(16, 16),
		4.0,
		1.0,
		Vector2i(32, 32),
		3,
		&"phase-3-tests"
	)
	var road_before := _road_snapshot(world)
	var anchor_before := JSON.stringify(anchor.to_dict())
	var terrain_before := _terrain_snapshot(terrain)
	FoundationBlockExtractor.generate(world)
	_check(_road_snapshot(world) == road_before, "block extraction does not mutate road nodes or edges")
	_check(JSON.stringify(anchor.to_dict()) == anchor_before, "block extraction does not mutate city anchors")
	_check(_terrain_snapshot(terrain) == terrain_before, "block extraction does not mutate authoritative terrain")


func _test_debug_contract(world: FoundationWorldData) -> void:
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"blocks")
	var provider := registry.get_provider(&"blocks")
	var builder := registry.build(world)
	_check(builder.line_purposes.has(&"block_generated"), "block debug provider emits state-colored outlines")
	_check(builder.triangle_purposes.has(&"block_fill_generated"), "block debug provider emits batched polygon fills")
	var has_label := false
	for label: Dictionary in builder.labels:
		var text := String(label.get("text", ""))
		has_label = has_label or ("A " in text and "roads" in text and "valid" in text)
	_check(has_label, "block debug labels expose stable ID, area, road count, and validation state")
	var invocation_count := provider.invocation_count
	registry.set_layer_enabled(&"blocks", false)
	var disabled := registry.build(world)
	_check(disabled.get_primitive_count() == 0 and provider.invocation_count == invocation_count, "disabled block debug performs zero provider work and creates no primitives")

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
	debug_view.show_road_topology = false
	debug_view.show_blocks = true
	debug_view.show_relationships = false
	world_node.add_child(debug_view)
	debug_view.rebuild()
	_check(debug_view.get_node_or_null("BatchedLines") != null, "runtime block outlines use one batched line mesh")
	_check(debug_view.get_node_or_null("BatchedFills") != null, "runtime block fills use one batched triangle mesh")
	world_node.free()


func _test_bounded_candidate_work() -> void:
	var world := _make_world(3012, Rect2(0.0, 0.0, 2600.0, 2600.0), false)
	var square_count := 64
	for index in range(square_count):
		var column := index % 8
		var row := index / 8
		_add_rectangle(
			world,
			"large-%03d" % index,
			Rect2(column * 300.0, row * 300.0, 40.0, 40.0)
		)
	var profile := FoundationBlockGenerationProfile.new()
	profile.intersection_bucket_size = 64.0
	var result := FoundationBlockExtractor.generate(world, profile)
	_check(result.success and world.get_blocks().size() == square_count, "larger disconnected synthetic graph extracts every local face")
	_check(
		result.candidate_pair_count * 10 < result.unrestricted_pair_count,
		"spatial bucketing bounds intersection candidates far below unrestricted all-pairs work"
	)
	_check(result.intersection_bucket_count > 1, "large-graph diagnostics expose deterministic spatial bucket work")


func _test_demo_contract() -> void:
	var scene := load("res://demo/spatial_model_demo.tscn") as PackedScene
	var demo := scene.instantiate()
	root.add_child(demo)
	var world_node := demo.get_node("FoundationWorld") as FoundationWorld
	var has_concave_block := false
	for block in world_node.world_data.get_blocks():
		has_concave_block = has_concave_block or _is_concave(block.outer_boundary)
	var open_fixture_id: StringName
	for edge in world_node.world_data.get_road_edges():
		if edge.metadata.get("phase_3_demo_fixture", false) and not edge.metadata.get("closed", true):
			open_fixture_id = edge.stable_id
	var open_component_bounded := false
	for block in world_node.world_data.get_blocks():
		open_component_bounded = open_component_bounded or open_fixture_id in block.boundary_road_ids
	_check(has_concave_block, "Phase 3 demo visibly includes an irregular concave bounded block")
	_check(not String(open_fixture_id).is_empty() and not open_component_bounded, "Phase 3 demo includes an open road component that produces no false block")
	demo.free()


func _test_scope_exclusions(world: FoundationWorldData) -> void:
	var block := world.get_blocks()[0]
	_check(
		ClassDB.is_parent_class(block.get_class(), "RefCounted")
		and not ClassDB.is_parent_class(block.get_class(), "Node"),
		"block contract remains abstract Node-free data"
	)
	var forbidden_methods := [
		&"subdivide_parcels", &"create_building", &"generate_district", &"build_road_mesh",
		&"create_lane", &"spawn_traffic", &"create_navigation_mesh", &"control_intersection",
		&"grade_terrain", &"place_parking", &"place_vegetation",
	]
	var has_forbidden := false
	for method_name in forbidden_methods:
		has_forbidden = has_forbidden or block.has_method(method_name) or world.has_method(method_name)
	_check(not has_forbidden, "Phase 3 exposes no parcel, building, district, road-mesh, traffic, navigation, grading, parking, or vegetation API")


func _make_world(
	seed: int,
	bounds := Rect2(-256.0, -256.0, 512.0, 512.0),
	initialize_partitions := true
) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 3
	metadata.content_pack_version = &"phase-3-tests"
	metadata.world_bounds = bounds
	var coordinates := FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(32, 32), Vector2i(2, 2))
	var world := FoundationWorldData.new(metadata, coordinates)
	world.initialize_default_layers()
	if initialize_partitions:
		world.initialize_partitions()
	return world


func _add_rectangle(world: FoundationWorldData, semantic_key: String, bounds: Rect2) -> FoundationRoadEdge:
	return _add_road(world, semantic_key, PackedVector2Array([
		bounds.position,
		Vector2(bounds.end.x, bounds.position.y),
		bounds.end,
		Vector2(bounds.position.x, bounds.end.y),
		bounds.position,
	]))


func _add_road(
	world: FoundationWorldData,
	semantic_key: String,
	points: PackedVector2Array,
	metadata: Dictionary = {}
) -> FoundationRoadEdge:
	var route := PackedVector3Array()
	for point in points:
		route.append(Vector3(point.x, 0.0, point.y))
	var stable_id := FoundationSpatialId.make(
		world.metadata.seed,
		3,
		world.metadata.content_pack_version,
		FoundationRoadEdge.ENTITY_TYPE,
		&"",
		semantic_key
	)
	var edge := FoundationRoadEdge.new(stable_id, &"", &"", route)
	edge.source_pass = &"phase_3_test_fixture"
	edge.metadata = metadata.duplicate(true)
	world.register_record(edge)
	return edge


func _is_concave(boundary: PackedVector2Array) -> bool:
	for index in range(boundary.size()):
		var previous := boundary[(index - 1 + boundary.size()) % boundary.size()]
		var current := boundary[index]
		var next := boundary[(index + 1) % boundary.size()]
		if (current - previous).cross(next - current) < 0.0:
			return true
	return false


func _triangle_area(vertices: PackedVector3Array) -> float:
	var area := 0.0
	for index in range(0, vertices.size(), 3):
		var a := Vector2(vertices[index].x, vertices[index].z)
		var b := Vector2(vertices[index + 1].x, vertices[index + 1].z)
		var c := Vector2(vertices[index + 2].x, vertices[index + 2].z)
		area += absf((b - a).cross(c - a)) * 0.5
	return area


func _block_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for block in world.get_blocks():
		records.append(block.to_dict())
	return JSON.stringify(records)


func _road_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for node in world.get_road_nodes():
		records.append(node.to_dict())
	for edge in world.get_road_edges():
		records.append(edge.to_dict())
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


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
