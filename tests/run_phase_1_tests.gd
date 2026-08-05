extends SceneTree

const DEBUG_EDITOR_DOCK_SCRIPT := preload("res://addons/foundation/editor/debug_editor_dock.gd")
const TERRAIN_EDITOR_DOCK_SCRIPT := preload("res://addons/foundation/editor/terrain_editor_dock.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var coordinates := FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(32, 32), Vector2i(2, 2))
	_test_coordinate_conversions(coordinates)
	_test_stable_ids()
	var world := _make_world(coordinates)
	var records := _test_registration_and_index(world)
	var representative_anchor := _test_city_anchor_contract(world)
	_test_dirty_bounds(world)
	_test_serialization_round_trip(world, records[0], representative_anchor)
	_test_terrain_adapter(world)
	_test_anchor_debug_output(world, representative_anchor)
	_test_debug_contract(world)
	_test_runtime_debug_view(world)
	_test_editor_dock_layout()

	if _failures.is_empty():
		print("Foundation Phase 1 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 1 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_coordinate_conversions(coordinates: FoundationCoordinateSystem) -> void:
	var boundary_cases := {
		-129.0: -2,
		-128.0: -1,
		-1.0: -1,
		0.0: 0,
		127.0: 0,
		128.0: 1,
	}
	var boundaries_correct := true
	for meters: float in boundary_cases:
		var expected_chunk: int = boundary_cases[meters]
		if coordinates.world_to_chunk(Vector3(meters, 0.0, meters)) != Vector2i(expected_chunk, expected_chunk):
			boundaries_correct = false
			break
	_check(boundaries_correct, "negative and positive world boundaries use floor-based chunk coordinates")

	var cell_cases := {
		-33: -2,
		-32: -1,
		-1: -1,
		0: 0,
		31: 0,
		32: 1,
	}
	var cells_correct := true
	for cell_value: int in cell_cases:
		var expected_chunk: int = cell_cases[cell_value]
		if coordinates.terrain_cell_to_chunk(Vector2i(cell_value, cell_value)) != Vector2i(expected_chunk, expected_chunk):
			cells_correct = false
			break
	_check(cells_correct, "cell-to-chunk conversion floors correctly across negative boundaries")
	_check(
		coordinates.local_cell_in_chunk(Vector2i(-1, -1)) == Vector2i(31, 31),
		"negative cells resolve positive local coordinates within their chunk"
	)
	_check(
		coordinates.chunk_local_cell_to_terrain_cell(Vector2i(-1, 2), Vector2i(31, 4)) == Vector2i(-1, 68),
		"chunk/local cell coordinates convert back to authoritative terrain cells"
	)
	_check(
		coordinates.chunk_local_vertex_to_terrain_vertex(Vector2i(-1, 2), Vector2i(32, 0)) == Vector2i(0, 64),
		"chunk-local shared vertices convert back to authoritative terrain vertices"
	)
	_check(
		coordinates.world_to_terrain_cell(Vector3(-0.1, 0.0, -4.1)) == Vector2i(-1, -2),
		"world-to-cell conversion is centralized and floor-based"
	)
	var cell := Vector2i(-7, 9)
	_check(
		coordinates.world_to_terrain_cell(coordinates.terrain_cell_to_world(cell)) == cell,
		"world and terrain cell origins round-trip"
	)
	var vertex := Vector2i(-4, 7)
	_check(
		coordinates.world_to_terrain_vertex(coordinates.terrain_vertex_to_world(vertex)) == vertex,
		"world and terrain vertex coordinates round-trip"
	)
	_check(
		coordinates.chunk_to_world_bounds(Vector2i(-1, 1)) == Rect2(-128.0, 128.0, 128.0, 128.0),
		"default 32-cell chunks have exact 128 m bounds"
	)
	_check(coordinates.snap_1m(Vector3(1.49, 2.51, -1.51)) == Vector3(1.0, 3.0, -2.0), "1 m snapping is exact")
	_check(coordinates.snap_2m(Vector3(1.1, 3.1, -3.1)) == Vector3(2.0, 4.0, -4.0), "2 m snapping is exact")
	_check(coordinates.snap_4m(Vector3(2.1, 5.9, -6.1)) == Vector3(4.0, 4.0, -8.0), "4 m snapping is exact")


func _test_stable_ids() -> void:
	var first := FoundationSpatialId.make(42, 1, &"pack-a", &"site", &"region_0_0", "lot-7")
	var second := FoundationSpatialId.make(42, 1, &"pack-a", &"site", &"region_0_0", "lot-7")
	var different := FoundationSpatialId.make(42, 1, &"pack-a", &"site", &"region_0_0", "lot-8")
	_check(first == second, "stable IDs reproduce from the same semantic context")
	_check(first != different, "different semantic keys generate different stable IDs")
	_check(FoundationSpatialId.for_chunk(Vector2i(-3, 5)) == &"chunk_-3_5", "chunk IDs encode signed coordinates")


func _make_world(coordinates: FoundationCoordinateSystem) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = 42
	metadata.generator_version = 1
	metadata.content_pack_version = &"phase-1-tests"
	metadata.world_bounds = Rect2(-256.0, -256.0, 512.0, 512.0)
	var world := FoundationWorldData.new(metadata, coordinates)
	world.initialize_default_layers()
	world.register_layer_type(&"sample")
	world.initialize_partitions()
	_check(world.get_chunk(Vector2i(-1, 0)) is FoundationChunkData, "chunks are abstract data, not rendered nodes")
	_check(world.get_region(Vector2i(-1, 0)) is FoundationRegionData, "regions are represented independently from scene nodes")
	return world


func _test_registration_and_index(world: FoundationWorldData) -> Array[FoundationSpatialRecord]:
	var parent_id := FoundationSpatialId.make(42, 1, &"phase-1-tests", &"sample", &"", "parent")
	var child_id := FoundationSpatialId.make(42, 1, &"phase-1-tests", &"sample", parent_id, "child")
	var spanning_id := FoundationSpatialId.make(42, 1, &"phase-1-tests", &"sample", &"", "spanning")
	var parent := FoundationSpatialRecord.new(parent_id, &"sample", &"sample", Rect2(8.0, 8.0, 24.0, 24.0))
	parent.source_pass = &"phase_1_fixture"
	parent.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	var child := FoundationSpatialRecord.new(child_id, &"sample", &"sample", Rect2(40.0, 8.0, 16.0, 16.0), parent_id)
	child.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	parent.add_child(child_id)
	var spanning := FoundationSpatialRecord.new(
		spanning_id,
		&"sample",
		&"sample",
		Rect2(-20.0, -20.0, 200.0, 200.0)
	)

	_check(world.register_record(parent), "records register through their renderer-independent layer")
	_check(world.register_record(child), "child records register with stable parent identity")
	_check(world.register_record(spanning), "multi-chunk records register")
	_check(world.get_record(parent_id) == parent, "direct stable-ID lookup returns the registered record")
	_check(spanning.owning_chunks.size() == 9, "a multi-chunk record appears in every intersected chunk bucket")
	var every_bucket_contains_record := true
	for chunk_coordinate in spanning.owning_chunks:
		if spanning_id not in world.get_chunk(chunk_coordinate).get_record_ids(&"sample"):
			every_bucket_contains_record = false
			break
	_check(every_bucket_contains_record, "abstract chunks reference every spanning record")

	var queried := world.query_bounds(Rect2(-32.0, -32.0, 256.0, 256.0), [&"sample"])
	var query_ids: Array[String] = []
	for record in queried:
		query_ids.append(String(record.stable_id))
	var sorted_ids := query_ids.duplicate()
	sorted_ids.sort()
	_check(query_ids == sorted_ids, "bounds queries return deterministic stable-ID order")
	_check(world.get_records_in_chunk(Vector2i.ZERO, &"sample").size() == 3, "chunk queries use buckets instead of full-world scans")
	var temporary := FoundationSpatialRecord.new(&"sample_temporary", &"sample", &"sample", Rect2(4.0, 4.0, 2.0, 2.0))
	world.register_record(temporary)
	_check(world.unregister_record(temporary.stable_id), "records unregister through their owning layer and shared index")
	_check(world.get_record(temporary.stable_id) == null, "unregistered stable IDs leave direct lookup")
	return [parent, child, spanning]


func _test_dirty_bounds(world: FoundationWorldData) -> void:
	var dirty := world.mark_layer_dirty(&"sample", Rect2(-1.0, -1.0, 2.0, 2.0))
	var expected: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0),
	]
	_check(dirty == expected, "dirty bounds identify only intersected chunks in deterministic order")
	var every_chunk_dirty := true
	for chunk_coordinate in expected:
		if not world.get_chunk(chunk_coordinate).is_layer_dirty(&"sample"):
			every_chunk_dirty = false
	_check(every_chunk_dirty, "dirty layer state is represented on abstract chunk data")


func _test_city_anchor_contract(world: FoundationWorldData) -> FoundationCityAnchor:
	var first := FoundationCityAnchor.create(
		world.metadata,
		FoundationCityAnchor.CATEGORY_MAP_EXIT,
		Vector3(128.0, 0.0, 0.0),
		"boundary-exit",
		24.0,
		0.75
	)
	var reproduced := FoundationCityAnchor.create(
		world.metadata,
		FoundationCityAnchor.CATEGORY_MAP_EXIT,
		Vector3(128.0, 0.0, 0.0),
		"boundary-exit",
		24.0,
		0.75
	)
	_check(first.stable_id == reproduced.stable_id, "city-anchor IDs reproduce from deterministic semantic context")
	var expected_categories: Array[StringName] = [
		FoundationCityAnchor.CATEGORY_CITY_CENTER,
		FoundationCityAnchor.CATEGORY_CIVIC_CENTER,
		FoundationCityAnchor.CATEGORY_HIGHWAY_ENTRANCE,
		FoundationCityAnchor.CATEGORY_MAP_EXIT,
		FoundationCityAnchor.CATEGORY_INDUSTRIAL_CENTER,
		FoundationCityAnchor.CATEGORY_COMMERCIAL_CENTER,
		FoundationCityAnchor.CATEGORY_WATERFRONT_CROSSING,
		FoundationCityAnchor.CATEGORY_BRIDGE_CANDIDATE,
		FoundationCityAnchor.CATEGORY_TRANSIT_NODE,
		FoundationCityAnchor.CATEGORY_LANDMARK,
		FoundationCityAnchor.CATEGORY_PUBLIC_SQUARE,
		FoundationCityAnchor.CATEGORY_DISTRICT_SEED,
		FoundationCityAnchor.CATEGORY_EXTERNAL_DESTINATION,
	]
	_check(
		FoundationCityAnchor.get_builtin_categories() == expected_categories,
		"city-anchor contract exposes every minimum extensible category constant"
	)
	var custom := FoundationCityAnchor.create(
		world.metadata,
		&"content_pack_custom_anchor",
		Vector3(-128.0, 0.0, -1.0),
		"custom-point"
	)
	_check(custom.anchor_category == &"content_pack_custom_anchor", "content packs can use open StringName anchor categories")
	var explicit_bounds := Rect2(-20.0, 132.0, 52.0, 18.0)
	var explicit := FoundationCityAnchor.create(
		world.metadata,
		FoundationCityAnchor.CATEGORY_WATERFRONT_CROSSING,
		Vector3(4.0, 2.0, 140.0),
		"explicit-influence",
		12.0,
		0.6,
		explicit_bounds
	)
	var restored_explicit := FoundationCityAnchor.from_dict(explicit.to_dict())
	_check(
		restored_explicit.has_explicit_influence_bounds
		and restored_explicit.influence_bounds == explicit_bounds
		and restored_explicit.world_bounds == explicit_bounds,
		"explicit anchor influence bounds take precedence and serialize independently"
	)
	_check(world.register_record(custom), "point anchors register through the shared spatial layer")
	_check(
		custom.owning_chunks == [Vector2i(-1, -1)],
		"point anchors use floor-based negative chunk ownership"
	)

	first.tags = PackedStringArray(["external", "review_fixture"])
	first.metadata = {"display_name": "Boundary Exit", "content_weight": 3}
	first.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	first.source_pass = &"phase_1_anchor_fixture"
	_check(world.register_record(first), "influence anchors register as renderer-independent records")
	var expected_chunks: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 0), Vector2i(1, 0),
	]
	_check(first.owning_chunks == expected_chunks, "boundary influence radius registers in every intersected chunk")
	_check(
		first.owning_regions == [Vector2i(0, -1), Vector2i(0, 0)],
		"anchor chunk ownership resolves deterministic region ownership"
	)
	var every_chunk_has_anchor := true
	for chunk_coordinate in expected_chunks:
		every_chunk_has_anchor = every_chunk_has_anchor and first.stable_id in world.get_chunk(chunk_coordinate).get_record_ids(FoundationWorldData.CITY_ANCHOR_LAYER)
	_check(every_chunk_has_anchor, "multi-chunk anchor ownership is mirrored by abstract chunks")
	_check(
		first in world.get_records_in_region(Vector2i(0, -1), FoundationWorldData.CITY_ANCHOR_LAYER),
		"anchors are directly queryable through region buckets"
	)
	_check(world.get_anchors().size() == 2, "world exposes typed anchors without scene nodes")
	var forbidden_methods := [&"connect_to", &"add_connection", &"generate_road", &"find_path", &"get_route"]
	var has_topology_api := false
	for method_name in forbidden_methods:
		has_topology_api = has_topology_api or first.has_method(method_name)
	_check(not has_topology_api and first.child_ids.is_empty(), "city-anchor contract adds no road topology or pathfinding API")
	return first


func _test_serialization_round_trip(
	world: FoundationWorldData,
	representative_record: FoundationSpatialRecord,
	representative_anchor: FoundationCityAnchor
) -> void:
	var representative_chunk := world.get_chunk(Vector2i.ZERO)
	representative_chunk.runtime_state = FoundationChunkData.RuntimeState.PHYSICS_LOADED
	var representative_region := world.get_region(Vector2i.ZERO)
	representative_region.tags = PackedStringArray(["test_region"])
	representative_region.generation_state = FoundationRegionData.GenerationState.GENERATED
	var manifest := world.to_dict()
	var restored := FoundationWorldData.from_dict(manifest)
	var restored_record := restored.get_record(representative_record.stable_id)
	var restored_anchor := restored.get_record(representative_anchor.stable_id) as FoundationCityAnchor
	_check(int(manifest.get("format_version", 0)) == 1, "world manifests have an explicit data-format version")
	_check(restored_record != null, "stable IDs survive serialization round-trip")
	_check(
		restored.coordinate_system.to_dict() == world.coordinate_system.to_dict(),
		"coordinate settings survive serialization round-trip"
	)
	_check(
		restored.layer_registry.get_layer_types() == world.layer_registry.get_layer_types(),
		"layer registrations survive serialization round-trip"
	)
	_check(restored.get_sorted_chunks().size() == world.get_sorted_chunks().size(), "chunk metadata survives serialization")
	_check(restored.get_sorted_regions().size() == world.get_sorted_regions().size(), "region metadata survives serialization")
	_check(
		restored.get_chunk(Vector2i.ZERO).runtime_state == FoundationChunkData.RuntimeState.PHYSICS_LOADED,
		"chunk runtime-state seams survive serialization"
	)
	_check(
		restored.get_region(Vector2i.ZERO).tags == PackedStringArray(["test_region"]),
		"region tags survive serialization"
	)
	_check(
		restored_record.authorship_state == FoundationSpatialRecord.AuthorshipState.LOCKED,
		"generated/locked/overridden state survives serialization"
	)
	_check(restored_anchor != null, "city anchors restore as their typed renderer-independent contract")
	_check(
		restored_anchor.anchor_category == representative_anchor.anchor_category
		and restored_anchor.world_position == representative_anchor.world_position
		and is_equal_approx(restored_anchor.influence_radius, representative_anchor.influence_radius)
		and is_equal_approx(restored_anchor.priority_weight, representative_anchor.priority_weight),
		"anchor category, position, influence, and priority survive serialization"
	)
	_check(
		restored_anchor.tags == representative_anchor.tags
		and restored_anchor.metadata == representative_anchor.metadata
		and restored_anchor.authorship_state == FoundationSpatialRecord.AuthorshipState.OVERRIDDEN,
		"anchor tags, metadata, and authorship state survive serialization"
	)
	_check(
		restored_anchor.owning_chunks == representative_anchor.owning_chunks
		and restored_anchor.owning_regions == representative_anchor.owning_regions,
		"anchor chunk and region ownership survive index reconstruction"
	)


func _test_terrain_adapter(world: FoundationWorldData) -> void:
	var profile := FoundationTerrainProfile.new()
	profile.seed = world.metadata.seed
	profile.grid_cells = Vector2i(8, 6)
	var terrain_data := FoundationTerrainGenerator.generate(profile)
	var revision_before := terrain_data.revision
	var world_node := FoundationWorld.new()
	world_node.initialize_on_ready = false
	world_node.world_data = world
	var extent := world_node.register_terrain_extent(terrain_data, Vector2i(-8, -6))
	_check(extent.layer_type == FoundationWorldData.TERRAIN_LAYER, "terrain adapts into the spatial layer model")
	_check(extent.world_bounds == Rect2(-32.0, -24.0, 32.0, 24.0), "terrain adaptation preserves its authoritative extent")
	_check(terrain_data.revision == revision_before, "terrain adaptation does not rewrite authoritative terrain arrays")
	world_node.free()


func _test_anchor_debug_output(
	world: FoundationWorldData,
	representative_anchor: FoundationCityAnchor
) -> void:
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"anchors")
	var builder := registry.build(world)
	_check(builder.line_purposes.has(&"anchor_overridden"), "anchor debug provider emits a state-colored point marker")
	_check(builder.line_purposes.has(&"anchor_influence"), "anchor debug provider emits influence-bound geometry")
	var has_label := false
	for label: Dictionary in builder.labels:
		var label_text := String(label.get("text", ""))
		if String(representative_anchor.stable_id) in label_text and String(representative_anchor.anchor_category) in label_text:
			has_label = true
			break
	_check(has_label, "anchor debug provider emits stable-ID and category labels")


func _test_debug_contract(world: FoundationWorldData) -> void:
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	var before := JSON.stringify(world.to_dict())
	var builder := registry.build(world, {"selected_record_id": world.spatial_index.get_all_records()[0].stable_id})
	var after := JSON.stringify(world.to_dict())
	_check(builder.get_primitive_count() > 0, "enabled debug providers emit lightweight primitives")
	_check(before == after, "debug providers do not mutate authoritative world data")

	var invocation_counts: Dictionary = {}
	for provider_id in registry.get_provider_ids():
		invocation_counts[provider_id] = registry.get_provider(provider_id).invocation_count
	registry.enabled = false
	var disabled_builder := registry.build(world)
	var no_provider_work := registry.last_provider_invocations == 0
	for provider_id in registry.get_provider_ids():
		no_provider_work = no_provider_work and registry.get_provider(provider_id).invocation_count == invocation_counts[provider_id]
	_check(disabled_builder.get_primitive_count() == 0, "disabled debug rendering creates no geometry")
	_check(no_provider_work, "global debug disablement invokes no providers")
	registry.enabled = true
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, false)
	var layers_disabled_builder := registry.build(world)
	_check(layers_disabled_builder.get_primitive_count() == 0, "disabled debug layers emit no geometry")
	_check(registry.last_provider_invocations == 0, "disabled debug layers invoke no provider work")


func _test_runtime_debug_view(world: FoundationWorldData) -> void:
	var world_node := FoundationWorld.new()
	world_node.initialize_on_ready = false
	world_node.world_data = world
	root.add_child(world_node)
	var debug_view := FoundationDebugView.new()
	debug_view.show_terrain_grid = true
	world_node.add_child(debug_view)
	var primitive_count := debug_view.rebuild()
	_check(primitive_count > 0, "runtime debug view builds world, region, chunk, grid, and record geometry")
	_check(debug_view.get_node_or_null("BatchedLines") != null, "debug lines are batched into one mesh node")
	_check(debug_view.get_node_or_null("BatchedFills") != null, "debug fills are batched into one mesh node")
	debug_view.set_debug_enabled(false)
	_check(debug_view.last_primitive_count == 0, "disabling the runtime view disposes its geometry")
	world_node.free()


func _test_editor_dock_layout() -> void:
	var debug_dock := DEBUG_EDITOR_DOCK_SCRIPT.new() as ScrollContainer
	root.add_child(debug_dock)
	var debug_content := debug_dock.get_child(0) as VBoxContainer
	_check(
		debug_dock.get_combined_minimum_size().y < debug_content.get_combined_minimum_size().y,
		"debug controls scroll without imposing their stacked height on the editor"
	)
	debug_dock.free()

	var terrain_dock := TERRAIN_EDITOR_DOCK_SCRIPT.new() as ScrollContainer
	root.add_child(terrain_dock)
	var terrain_content := terrain_dock.get_child(0) as VBoxContainer
	_check(
		terrain_dock.get_combined_minimum_size().y < terrain_content.get_combined_minimum_size().y,
		"terrain controls scroll without imposing their stacked height on the editor"
	)
	terrain_dock.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
