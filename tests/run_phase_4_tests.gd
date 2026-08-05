extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline := _test_rectangle_determinism_and_seed_variation()
	var world := baseline as FoundationWorldData
	_test_concave_and_coverage()
	_test_negative_spatial_ownership()
	_test_remainder_and_validation()
	_test_authored_regeneration_and_serialization()
	_test_non_mutation()
	_test_debug_contract(world)
	_test_bounded_work()
	_test_demo_contract()
	_test_scope_exclusions(world)

	if _failures.is_empty():
		print("Foundation Phase 4 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 4 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_rectangle_determinism_and_seed_variation() -> FoundationWorldData:
	var boundary := PackedVector2Array([
		Vector2(-80.0, -48.0), Vector2(80.0, -48.0),
		Vector2(80.0, 48.0), Vector2(-80.0, 48.0),
	])
	var first := _make_world(4101)
	var second := _make_world(4101)
	var changed := _make_world(4102)
	_add_block_fixture(first, &"rectangle", boundary)
	_add_block_fixture(second, &"rectangle", boundary)
	_add_block_fixture(changed, &"rectangle", boundary)
	var inputs_before := _input_snapshot(first)
	var first_result := FoundationParcelSubdivider.generate(first)
	var second_result := FoundationParcelSubdivider.generate(second)
	var changed_result := FoundationParcelSubdivider.generate(changed)
	_check(first_result.success and second_result.success and changed_result.success, "rectangular parcel subdivision succeeds")
	_check(not first.get_parcels().is_empty(), "rectangular block produces canonical parcel records")
	_check(_parcel_snapshot(first) == _parcel_snapshot(second), "same seed, profile, and block reproduce parcel IDs, polygons, frontage, and ordering")
	_check(_boundary_snapshot(first) != _boundary_snapshot(changed), "eligible seed change alters split positions without consuming a global RNG")
	_check(_coverage_is_valid(first), "rectangular parcels cover their parent without overlap")
	var buildable_frontage := true
	for parcel in first.get_parcels():
		buildable_frontage = buildable_frontage and (not parcel.buildable or parcel.frontage_length >= 8.0)
	_check(buildable_frontage, "every standard buildable parcel has explicit road frontage")
	var has_corner := false
	for parcel in first.get_parcels():
		has_corner = has_corner or parcel.parcel_kind == FoundationParcelRecord.KIND_CORNER
	_check(has_corner, "corner frontage classification is represented deterministically")
	_check(_input_snapshot(first) == inputs_before, "parcel subdivision does not mutate blocks, roads, logical roads, or anchors")
	_check(first_result.subdivision_operation_count <= FoundationParcelGenerationProfile.new().maximum_subdivision_operations, "subdivision reports bounded deterministic operation work")
	return first


func _test_concave_and_coverage() -> void:
	var world := _make_world(4201)
	_add_block_fixture(world, &"concave", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(140.0, 0.0), Vector2(140.0, 44.0),
		Vector2(52.0, 44.0), Vector2(52.0, 132.0), Vector2(0.0, 132.0),
	]))
	var result := FoundationParcelSubdivider.generate(world)
	_check(result.success and world.get_parcels().size() > 1, "concave L-shaped block subdivides without rectangular assumptions")
	_check(_coverage_is_valid(world), "concave parcel union covers the L-shaped parent without overlap")
	var all_inside := true
	for parcel in world.get_parcels():
		all_inside = all_inside and Geometry2D.is_point_in_polygon(parcel.label_point, world.get_blocks()[0].outer_boundary)
	_check(all_inside, "concave parcel labels remain inside the parent geometry")


func _test_negative_spatial_ownership() -> void:
	var world := _make_world(4301, Rect2(-512.0, -512.0, 1024.0, 1024.0))
	_add_block_fixture(world, &"signed", PackedVector2Array([
		Vector2(-150.0, -90.0), Vector2(150.0, -90.0),
		Vector2(150.0, 90.0), Vector2(-150.0, 90.0),
	]))
	FoundationParcelSubdivider.generate(world)
	var has_negative := false
	var has_positive := false
	var indexed := true
	for parcel in world.get_parcels():
		for chunk in parcel.owning_chunks:
			has_negative = has_negative or chunk.x < 0 or chunk.y < 0
			has_positive = has_positive or chunk.x >= 0 and chunk.y >= 0
			indexed = indexed and parcel in world.get_records_in_chunk(chunk, FoundationWorldData.PARCEL_LAYER)
	_check(has_negative and has_positive and indexed, "signed parcels are indexed in every owning chunk and region")


func _test_remainder_and_validation() -> void:
	var world := _make_world(4401)
	_add_block_fixture(world, &"remainder", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(38.0, 0.0), Vector2(38.0, 18.0), Vector2(0.0, 18.0),
	]))
	var profile := FoundationParcelGenerationProfile.new()
	profile.minimum_parcel_area = 900.0
	profile.maximum_parcel_area = 1800.0
	profile.non_buildable_remainder_threshold = 1000.0
	var result := FoundationParcelSubdivider.generate(world, profile)
	var explicit_remainders := true
	for parcel in world.get_parcels():
		explicit_remainders = explicit_remainders and not parcel.buildable and parcel.parcel_kind == FoundationParcelRecord.KIND_REMAINDER
	_check(result.success and explicit_remainders and result.remainder_parcel_count > 0, "unavoidable undersized land is retained as explicit non-buildable remainder records")
	_check(_coverage_is_valid(world, profile), "remainder records preserve auditable parent coverage")

	var constrained := _make_world(4402)
	_add_block_fixture(constrained, &"constrained", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(72.0, 0.0), Vector2(72.0, 24.0), Vector2(0.0, 24.0),
	]))
	var constrained_profile := FoundationParcelGenerationProfile.new()
	constrained_profile.minimum_frontage = 100.0
	constrained_profile.preferred_frontage = 100.0
	constrained_profile.maximum_frontage = 120.0
	FoundationParcelSubdivider.generate(constrained, constrained_profile)
	var has_frontage_diagnostic := false
	for issue in FoundationParcelValidator.validate(constrained, constrained_profile, false):
		has_frontage_diagnostic = has_frontage_diagnostic or issue.kind == &"insufficient_frontage"
	_check(has_frontage_diagnostic, "minimum frontage/depth rules emit deterministic validation diagnostics")


func _test_authored_regeneration_and_serialization() -> void:
	var world := _make_world(4501, Rect2(-256.0, -256.0, 1024.0, 512.0))
	_add_block_fixture(world, &"authored", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(160.0, 0.0), Vector2(160.0, 96.0), Vector2(0.0, 96.0),
	]))
	FoundationParcelSubdivider.generate(world)
	var parcel := world.get_parcels()[0]
	parcel.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	var locked_snapshot := JSON.stringify(parcel.to_dict())
	FoundationParcelSubdivider.generate(world)
	_check(world.get_record(parcel.stable_id) == parcel and JSON.stringify(parcel.to_dict()) == locked_snapshot, "locked parcel survives regeneration as the same object")
	parcel.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	var moved := PackedVector2Array()
	for point in parcel.boundary:
		moved.append(point + Vector2(420.0, 0.0))
	parcel.set_boundary(moved)
	FoundationParcelSubdivider.generate(world)
	_check(world.get_record(parcel.stable_id) == parcel and parcel.owning_chunks.has(Vector2i(3, 0)), "overridden parcel survives and refreshes authored spatial ownership")
	var restored := FoundationWorldData.from_dict(world.to_dict())
	_check(_parcel_snapshot(restored) == _parcel_snapshot(world), "typed parcel geometry, frontage provenance, states, metrics, and ownership serialize round-trip")
	var provenance_round_tripped := false
	for restored_parcel in restored.get_parcels():
		for frontage in restored_parcel.frontage_references:
			provenance_round_tripped = provenance_round_tripped or (not String(frontage.road_edge_id).is_empty() and not String(frontage.logical_road_id).is_empty())
	_check(provenance_round_tripped, "source road-edge and logical-road frontage identity survive serialization")
	var typed := true
	for restored_parcel in restored.get_parcels():
		typed = typed and restored_parcel is FoundationParcelRecord
	_check(typed, "world manifest restores typed Node-free parcel records")
	var restored_profile := FoundationParcelGenerationProfile.from_dict(restored.get_layer(FoundationWorldData.PARCEL_LAYER).metadata["profile"])
	_check(restored_profile.to_dict() == FoundationParcelGenerationProfile.new().to_dict(), "parcel generation profile has a versioned round-trip seam")


func _test_non_mutation() -> void:
	var world := _make_world(4601)
	_add_block_fixture(world, &"immutable", PackedVector2Array([
		Vector2(-96.0, -72.0), Vector2(96.0, -72.0), Vector2(96.0, 72.0), Vector2(-96.0, 72.0),
	]))
	var anchor := FoundationCityAnchor.create(world.metadata, FoundationCityAnchor.CATEGORY_CITY_CENTER, Vector3.ZERO, "phase-4-anchor")
	world.register_record(anchor)
	var terrain := FoundationTerrainData.new(4601, Vector2i(16, 16), 4.0, 1.0, Vector2i(32, 32), 4, &"phase-4-tests")
	var before := _input_snapshot(world)
	var terrain_before := _terrain_snapshot(terrain)
	FoundationParcelSubdivider.generate(world)
	_check(_input_snapshot(world) == before, "Phase 4 leaves authoritative block, road, logical-road, and anchor inputs unchanged")
	_check(_terrain_snapshot(terrain) == terrain_before, "Phase 4 leaves authoritative terrain arrays unchanged")
	var parcel_snapshot := _parcel_snapshot(world)
	FoundationParcelValidator.validate(world, null, false)
	_check(_parcel_snapshot(world) == parcel_snapshot, "read-only validation can inspect parcels without mutating data")


func _test_debug_contract(world: FoundationWorldData) -> void:
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"parcels")
	var provider := registry.get_provider(&"parcels")
	var before := _parcel_snapshot(world)
	var builder := registry.build(world)
	_check(builder.triangle_purposes.has(&"parcel_fill_generated") or builder.triangle_purposes.has(&"parcel_fill_corner"), "parcel debug provider emits batched fills")
	_check(builder.line_purposes.has(&"parcel_frontage_primary"), "parcel debug provider highlights primary frontage")
	_check(not builder.labels.is_empty(), "parcel debug labels expose stable identity and parcel metrics")
	_check(_parcel_snapshot(world) == before, "parcel debug provider does not mutate world data")
	var invocation_count := provider.invocation_count
	registry.set_layer_enabled(&"parcels", false)
	var disabled := registry.build(world)
	_check(disabled.get_primitive_count() == 0 and provider.invocation_count == invocation_count, "disabled parcel debug performs no provider work")


func _test_bounded_work() -> void:
	var world := _make_world(4701, Rect2(0.0, 0.0, 3000.0, 3000.0))
	for index in range(36):
		var column := index % 6
		var row := index / 6
		var origin := Vector2(column * 420.0, row * 420.0)
		_add_block_fixture(world, StringName("large_%02d" % index), PackedVector2Array([
			origin, origin + Vector2(180.0, 0.0), origin + Vector2(180.0, 120.0), origin + Vector2(0.0, 120.0),
		]))
	var profile := FoundationParcelGenerationProfile.new()
	profile.maximum_subdivision_operations = 200000
	var result := FoundationParcelSubdivider.generate(world, profile)
	_check(result.success and result.subdivision_operation_count < profile.maximum_subdivision_operations, "larger fixture stays within the explicit subdivision operation cap")
	_check(result.generated_parcel_count > 36, "larger fixture subdivides block-by-block into compact records")


func _test_demo_contract() -> void:
	var scene := load("res://demo/spatial_model_demo.tscn") as PackedScene
	var demo := scene.instantiate()
	root.add_child(demo)
	var world_node := demo.get_node("FoundationWorld") as FoundationWorld
	var debug_view := demo.get_node("FoundationWorld/FoundationDebugView") as FoundationDebugView
	var has_concave_parent := false
	var has_access_example := false
	for parcel in world_node.world_data.get_parcels():
		var parent := world_node.world_data.get_record(parcel.parent_id) as FoundationBlockRecord
		has_concave_parent = has_concave_parent or (parent != null and _is_concave(parent.outer_boundary))
		has_access_example = has_access_example or parcel.access_state != FoundationParcelRecord.ACCESS_DIRECT
	_check(not world_node.world_data.get_parcels().is_empty(), "Phase 4 demo generates parcel records")
	_check(has_concave_parent, "Phase 4 demo parcelizes the existing concave block")
	_check(has_access_example, "Phase 4 demo visibly includes an explicit access-required or remainder parcel")
	_check(debug_view.show_parcels, "Phase 4 demo exposes the parcel/frontage overlay")
	var before := _parcel_snapshot(world_node.world_data)
	demo.get_node("UI/Margin/Panel/Content/StageControls/StageOptions").select(3)
	demo.call("_regenerate_selected_stage")
	_check(_parcel_snapshot(world_node.world_data) == before, "Phase 4 demo same-seed parcel regeneration is stable")
	demo.free()


func _test_scope_exclusions(world: FoundationWorldData) -> void:
	var parcel := world.get_parcels()[0]
	_check(ClassDB.is_parent_class(parcel.get_class(), "RefCounted") and not ClassDB.is_parent_class(parcel.get_class(), "Node"), "parcel contract remains abstract Node-free data")
	var forbidden_methods := [
		&"assign_district", &"assign_zoning", &"create_building", &"place_parking",
		&"create_address", &"build_road_mesh", &"create_lane", &"spawn_traffic",
		&"create_navigation_mesh", &"grade_terrain", &"place_vegetation",
	]
	var forbidden := false
	for method_name in forbidden_methods:
		forbidden = forbidden or parcel.has_method(method_name) or world.has_method(method_name)
	_check(not forbidden, "Phase 4 introduces no district, building, parking, address, road-mesh, lane, traffic, navigation, grading, or vegetation API")


func _make_world(seed: int, bounds := Rect2(-256.0, -256.0, 512.0, 512.0)) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 4
	metadata.content_pack_version = &"phase-4-tests"
	metadata.world_bounds = bounds
	var coordinates := FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(32, 32), Vector2i(2, 2))
	var world := FoundationWorldData.new(metadata, coordinates)
	world.initialize_default_layers()
	world.initialize_partitions()
	return world


func _add_block_fixture(world: FoundationWorldData, semantic_key: StringName, boundary: PackedVector2Array) -> FoundationBlockRecord:
	var references: Array[FoundationBlockBoundaryReference] = []
	for index in range(boundary.size()):
		var edge_id := StringName("p4_edge_%s_%02d" % [semantic_key, index])
		var logical_id := StringName("p4_logical_%s_%02d" % [semantic_key, index])
		var first := boundary[index]
		var second := boundary[(index + 1) % boundary.size()]
		var edge := FoundationRoadEdge.new(edge_id, &"", &"", PackedVector3Array([
			Vector3(first.x, 0.0, first.y), Vector3(second.x, 0.0, second.y),
		]), FoundationRoadEdge.CLASS_LOCAL)
		edge.logical_road_id = logical_id
		edge.source_pass = &"phase_4_test_fixture"
		world.register_record(edge)
		var logical := FoundationLogicalRoad.new(logical_id, [edge_id], FoundationRoadEdge.CLASS_LOCAL, edge.world_bounds)
		logical.source_pass = &"phase_4_test_fixture"
		world.register_record(logical)
		references.append(FoundationBlockBoundaryReference.new(index, edge_id, 0, 0.0, 1.0, first.distance_to(second)))
	var block := FoundationBlockRecord.new(StringName("p4_block_%s" % semantic_key), boundary, references)
	block.source_pass = &"phase_4_test_fixture"
	world.register_record(block)
	return block


func _coverage_is_valid(world: FoundationWorldData, profile: FoundationParcelGenerationProfile = null) -> bool:
	var issues := FoundationParcelValidator.validate(world, profile, false)
	for issue in issues:
		if issue.kind in [&"outside_parent", &"parcel_overlap", &"parent_coverage_gap", &"self_intersection", &"degenerate_polygon"]:
			return false
	return true


func _parcel_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for parcel in world.get_parcels():
		records.append(parcel.to_dict())
	return JSON.stringify(records)


func _boundary_snapshot(world: FoundationWorldData) -> String:
	var records: Array = []
	for parcel in world.get_parcels():
		records.append(Array(parcel.boundary))
	return JSON.stringify(records)


func _input_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for block in world.get_blocks():
		records.append(block.to_dict())
	for edge in world.get_road_edges():
		records.append(edge.to_dict())
	for logical in world.get_logical_roads():
		records.append(logical.to_dict())
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


func _is_concave(boundary: PackedVector2Array) -> bool:
	for index in range(boundary.size()):
		var previous := boundary[(index - 1 + boundary.size()) % boundary.size()]
		var current := boundary[index]
		var next := boundary[(index + 1) % boundary.size()]
		if (current - previous).cross(next - current) < 0.0:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
