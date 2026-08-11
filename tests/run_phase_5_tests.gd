extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline := _test_determinism_frontage_and_massing()
	var world := baseline as FoundationWorldData
	_test_concave_corner_and_skips()
	_test_negative_spatial_ownership()
	_test_authored_regeneration_and_serialization()
	_test_non_mutation()
	_test_debug_contract(world)
	_test_bounded_work()
	_test_demo_contract()
	_test_scope_exclusions(world)

	if _failures.is_empty():
		print("Foundation Phase 5 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 5 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_determinism_frontage_and_massing() -> FoundationWorldData:
	var boundary := PackedVector2Array([
		Vector2(-60.0, -40.0), Vector2(60.0, -40.0),
		Vector2(60.0, 40.0), Vector2(-60.0, 40.0),
	])
	var first := _make_world(5101)
	var second := _make_world(5101)
	var changed := _make_world(5102)
	_add_parcel_fixture(first, &"rectangle", boundary)
	_add_parcel_fixture(second, &"rectangle", boundary)
	_add_parcel_fixture(changed, &"rectangle", boundary)
	var inputs_before := _input_snapshot(first)
	var first_result := FoundationBuildingGenerator.generate(first)
	var second_result := FoundationBuildingGenerator.generate(second)
	var changed_result := FoundationBuildingGenerator.generate(changed)
	_check(first_result.success and second_result.success and changed_result.success, "parcel-aware building generation succeeds")
	_check(first.get_buildings().size() == 1, "eligible parcel produces one compact building record")
	_check(_building_snapshot(first) == _building_snapshot(second), "same seed, profile, and parcel reproduce building IDs, footprints, and massing")
	_check(_massing_shape_snapshot(first) != _massing_shape_snapshot(changed), "eligible seed change alters target coverage or floor massing through named streams")
	var building := first.get_buildings()[0]
	var parcel := first.get_parcels()[0]
	_check(_footprint_inside(building, parcel), "generated footprint remains inside its parent parcel")
	_check(building.footprint_area >= 24.0 and building.coverage_ratio <= 0.681, "footprint satisfies minimum area and maximum coverage")
	_check(building.footprint[0].y >= -36.01 and building.world_bounds.end.y <= 36.01, "primary-front and rear setbacks shape the footprint")
	_check(building.primary_road_edge_id == &"p5_edge_rectangle_00" and building.primary_logical_road_id == &"p5_logical_rectangle_00", "building retains primary road and logical-road frontage identity")
	_check(building.height == float(building.floor_count) * building.floor_height and building.gross_floor_area == building.footprint_area * float(building.floor_count), "primitive massing metrics are internally consistent")
	_check(_input_snapshot(first) == inputs_before, "Phase 5 does not mutate parcels, blocks, roads, or logical roads")
	_check(first_result.generation_operation_count <= FoundationBuildingGenerationProfile.new().maximum_generation_operations, "building generation reports bounded deterministic geometry work")
	return first


func _test_concave_corner_and_skips() -> void:
	var world := _make_world(5201)
	_add_parcel_fixture(world, &"concave", PackedVector2Array([
		Vector2(-90.0, -70.0), Vector2(70.0, -70.0), Vector2(70.0, -20.0),
		Vector2(10.0, -20.0), Vector2(10.0, 70.0), Vector2(-90.0, 70.0),
	]), true)
	var remainder := _add_parcel_fixture(world, &"remainder", PackedVector2Array([
		Vector2(100.0, -40.0), Vector2(132.0, -40.0), Vector2(132.0, -16.0), Vector2(100.0, -16.0),
	]))
	remainder.buildable = false
	remainder.access_state = FoundationParcelRecord.ACCESS_NONE
	remainder.parcel_kind = FoundationParcelRecord.KIND_REMAINDER
	var result := FoundationBuildingGenerator.generate(world)
	var concave_building: FoundationBuildingRecord
	for building in world.get_buildings():
		if building.parent_id == &"p5_parcel_concave":
			concave_building = building
	var has_skip := false
	for diagnostic in result.diagnostics:
		has_skip = has_skip or diagnostic.get("kind", "") == "parcel_not_buildable"
	_check(concave_building != null and _footprint_inside(concave_building, world.get_record(concave_building.parent_id)), "concave parcel produces a deterministic contained footprint without rectangular assumptions")
	_check(concave_building != null and concave_building.corner_side_setback > concave_building.side_setback, "corner frontage applies its explicit secondary-road setback contract")
	_check(world.get_buildings().size() == 1 and has_skip and result.skipped_parcel_count == 1, "non-buildable remainder parcel is skipped with an explicit deterministic diagnostic")

	var constrained := _make_world(5202)
	_add_parcel_fixture(constrained, &"narrow", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(18.0, 0.0), Vector2(18.0, 9.0), Vector2(0.0, 9.0),
	]))
	var constrained_profile := FoundationBuildingGenerationProfile.new()
	constrained_profile.front_setback = 5.0
	constrained_profile.rear_setback = 5.0
	var constrained_result := FoundationBuildingGenerator.generate(constrained, constrained_profile)
	var exhausted := false
	for diagnostic in constrained_result.diagnostics:
		exhausted = exhausted or diagnostic.get("kind", "") == "setbacks_exhaust_parcel"
	_check(constrained.get_buildings().is_empty() and exhausted, "setbacks that exhaust a parcel produce no false footprint and a located diagnostic")


func _test_negative_spatial_ownership() -> void:
	var world := _make_world(5301, Rect2(-512.0, -512.0, 1024.0, 1024.0))
	_add_parcel_fixture(world, &"signed", PackedVector2Array([
		Vector2(-150.0, -70.0), Vector2(150.0, -70.0),
		Vector2(150.0, 70.0), Vector2(-150.0, 70.0),
	]))
	FoundationBuildingGenerator.generate(world)
	var building := world.get_buildings()[0]
	var has_negative := false
	var has_positive := false
	var indexed := true
	for chunk in building.owning_chunks:
		has_negative = has_negative or chunk.x < 0 or chunk.y < 0
		has_positive = has_positive or chunk.x >= 0 and chunk.y >= 0
		indexed = indexed and building in world.get_records_in_chunk(chunk, FoundationWorldData.BUILDING_LAYER)
	_check(has_negative and has_positive and indexed, "signed building footprints are indexed in every owning chunk and region")


func _test_authored_regeneration_and_serialization() -> void:
	var world := _make_world(5401, Rect2(-256.0, -256.0, 1024.0, 512.0))
	_add_parcel_fixture(world, &"authored", PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(160.0, 0.0), Vector2(160.0, 96.0), Vector2(0.0, 96.0),
	]))
	FoundationBuildingGenerator.generate(world)
	var building := world.get_buildings()[0]
	building.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	var locked_snapshot := JSON.stringify(building.to_dict())
	FoundationBuildingGenerator.generate(world)
	_check(world.get_record(building.stable_id) == building and JSON.stringify(building.to_dict()) == locked_snapshot, "locked building survives regeneration as the same object")
	building.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	var moved := PackedVector2Array()
	for point in building.footprint:
		moved.append(point + Vector2(420.0, 0.0))
	building.set_footprint(moved)
	FoundationBuildingGenerator.generate(world)
	_check(world.get_record(building.stable_id) == building and building.owning_chunks.has(Vector2i(3, 0)), "overridden building survives and refreshes authored spatial ownership")
	var repaired_id: StringName
	for candidate in world.get_buildings():
		if candidate != building and candidate.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			repaired_id = candidate.stable_id
	FoundationBuildingGenerator.generate(world)
	_check(not String(repaired_id).is_empty() and world.get_record(repaired_id) is FoundationBuildingRecord, "authored building collision receives the same deterministic repair identity on regeneration")
	var restored := FoundationWorldData.from_dict(world.to_dict())
	_check(_building_snapshot(restored) == _building_snapshot(world), "typed building footprint, massing, provenance, state, and ownership serialize round-trip")
	var typed := true
	for restored_building in restored.get_buildings():
		typed = typed and restored_building is FoundationBuildingRecord
	_check(typed, "world manifest restores typed Node-free building records")
	var restored_profile := FoundationBuildingGenerationProfile.from_dict(restored.get_layer(FoundationWorldData.BUILDING_LAYER).metadata["profile"])
	_check(restored_profile.to_dict() == FoundationBuildingGenerationProfile.new().to_dict(), "building generation profile has a versioned round-trip seam")


func _test_non_mutation() -> void:
	var world := _make_world(5501)
	_add_parcel_fixture(world, &"immutable", PackedVector2Array([
		Vector2(-96.0, -72.0), Vector2(96.0, -72.0), Vector2(96.0, 72.0), Vector2(-96.0, 72.0),
	]))
	var anchor := FoundationCityAnchor.create(world.metadata, FoundationCityAnchor.CATEGORY_CITY_CENTER, Vector3.ZERO, "phase-5-anchor")
	world.register_record(anchor)
	var terrain := FoundationTerrainData.new(5501, Vector2i(16, 16), 4.0, 1.0, Vector2i(32, 32), 5, &"phase-5-tests")
	var before := _input_snapshot(world)
	var terrain_before := _terrain_snapshot(terrain)
	FoundationBuildingGenerator.generate(world)
	_check(_input_snapshot(world) == before, "Phase 5 leaves authoritative parcel, block, road, logical-road, and anchor inputs unchanged")
	_check(_terrain_snapshot(terrain) == terrain_before, "Phase 5 leaves authoritative terrain arrays unchanged")
	var building_snapshot := _building_snapshot(world)
	FoundationBuildingValidator.validate(world, null, false)
	_check(_building_snapshot(world) == building_snapshot, "read-only building validation does not mutate records")


func _test_debug_contract(world: FoundationWorldData) -> void:
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"buildings")
	var provider := registry.get_provider(&"buildings")
	var before := _building_snapshot(world)
	var builder := registry.build(world)
	_check(builder.triangle_purposes.has(&"building_roof_generated"), "building debug provider emits a batched primitive roof fill")
	_check(builder.line_purposes.has(&"building_generated"), "building debug provider emits batched footprint and extrusion lines")
	_check(not builder.labels.is_empty(), "building debug labels expose stable identity, coverage, floors, and height")
	_check(_building_snapshot(world) == before, "building debug provider does not mutate authoritative data")
	var invocation_count := provider.invocation_count
	registry.set_layer_enabled(&"buildings", false)
	var disabled := registry.build(world)
	_check(disabled.get_primitive_count() == 0 and provider.invocation_count == invocation_count, "disabled building debug performs no provider work")


func _test_bounded_work() -> void:
	var world := _make_world(5601, Rect2(0.0, 0.0, 3000.0, 3000.0))
	for index in range(36):
		var column := index % 6
		var row := index / 6
		var origin := Vector2(column * 180.0, row * 180.0)
		_add_simple_parcel(world, StringName("large_%02d" % index), PackedVector2Array([
			origin, origin + Vector2(120.0, 0.0), origin + Vector2(120.0, 96.0), origin + Vector2(0.0, 96.0),
		]))
	var profile := FoundationBuildingGenerationProfile.new()
	profile.maximum_generation_operations = 200000
	var result := FoundationBuildingGenerator.generate(world, profile)
	_check(result.success and result.generation_operation_count < profile.maximum_generation_operations, "larger parcel fixture stays within the explicit building operation cap")
	_check(result.generated_building_count == 36, "larger fixture generates one compact massing record per eligible parcel")


func _test_demo_contract() -> void:
	var scene := load("res://demo/spatial_model_demo.tscn") as PackedScene
	var demo := scene.instantiate()
	root.add_child(demo)
	var world_node := demo.get_node("FoundationWorld") as FoundationWorld
	var debug_view := demo.get_node("FoundationWorld/FoundationDebugView") as FoundationDebugView
	var has_concave_parent := false
	for building in world_node.world_data.get_buildings():
		var parcel := world_node.world_data.get_record(building.parent_id) as FoundationParcelRecord
		var block := world_node.world_data.get_record(parcel.parent_id) as FoundationBlockRecord if parcel != null else null
		has_concave_parent = has_concave_parent or (block != null and _is_concave(block.outer_boundary))
	var has_skip_diagnostic := false
	for diagnostic: Dictionary in world_node.world_data.get_layer(FoundationWorldData.BUILDING_LAYER).metadata.get("diagnostics", []):
		has_skip_diagnostic = has_skip_diagnostic or diagnostic.get("kind", "") == "parcel_not_buildable"
	_check(not world_node.world_data.get_buildings().is_empty(), "Phase 5 demo generates building footprint and massing records")
	_check(has_concave_parent, "Phase 5 demo includes parcel-aware massing within the concave-block fixture")
	_check(has_skip_diagnostic, "Phase 5 demo exposes skipped access-required or remainder parcels")
	_check(debug_view.show_buildings, "Phase 5 demo exposes the building footprint/massing overlay")
	var before := _building_snapshot(world_node.world_data)
	demo.get_node("UI/Margin/Panel/Content/StageControls/StageOptions").select(4)
	demo.call("_regenerate_selected_stage")
	_check(_building_snapshot(world_node.world_data) == before, "Phase 5 demo same-seed building regeneration is stable")
	demo.free()


func _test_scope_exclusions(world: FoundationWorldData) -> void:
	var building := world.get_buildings()[0]
	_check(ClassDB.is_parent_class(building.get_class(), "RefCounted") and not ClassDB.is_parent_class(building.get_class(), "Node"), "building contract remains renderer-independent Node-free data")
	var forbidden_methods := [
		&"assign_district", &"assign_zoning", &"assign_use", &"create_facade",
		&"create_interior", &"instantiate_prefab", &"place_parking", &"create_address",
		&"build_mesh", &"create_collision", &"create_navigation_mesh", &"grade_terrain",
		&"create_building_pad", &"place_vegetation",
	]
	var forbidden := false
	for method_name in forbidden_methods:
		forbidden = forbidden or building.has_method(method_name) or world.has_method(method_name)
	_check(not forbidden, "Phase 5 introduces no uses, facades, interiors, prefabs, parking, address, production mesh, collision, navigation, grading, or vegetation API")


func _make_world(seed: int, bounds := Rect2(-256.0, -256.0, 512.0, 512.0)) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 5
	metadata.content_pack_version = &"phase-5-tests"
	metadata.world_bounds = bounds
	var coordinates := FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(32, 32), Vector2i(2, 2))
	var world := FoundationWorldData.new(metadata, coordinates)
	world.initialize_default_layers()
	world.initialize_partitions()
	return world


func _add_parcel_fixture(
	world: FoundationWorldData,
	semantic_key: StringName,
	boundary: PackedVector2Array,
	all_frontages := false
) -> FoundationParcelRecord:
	var block_references: Array[FoundationBlockBoundaryReference] = []
	var parcel_references: Array[FoundationParcelFrontageReference] = []
	for index in range(boundary.size()):
		var edge_id := StringName("p5_edge_%s_%02d" % [semantic_key, index])
		var logical_id := StringName("p5_logical_%s_%02d" % [semantic_key, index])
		var first := boundary[index]
		var second := boundary[(index + 1) % boundary.size()]
		var edge := FoundationRoadEdge.new(edge_id, &"", &"", PackedVector3Array([
			Vector3(first.x, 0.0, first.y), Vector3(second.x, 0.0, second.y),
		]), FoundationRoadEdge.CLASS_LOCAL)
		edge.logical_road_id = logical_id
		edge.source_pass = &"phase_5_test_fixture"
		world.register_record(edge)
		var logical := FoundationLogicalRoad.new(logical_id, [edge_id], FoundationRoadEdge.CLASS_LOCAL, edge.world_bounds)
		logical.source_pass = &"phase_5_test_fixture"
		world.register_record(logical)
		block_references.append(FoundationBlockBoundaryReference.new(index, edge_id, 0, 0.0, 1.0, first.distance_to(second)))
		if index == 0 or all_frontages:
			parcel_references.append(FoundationParcelFrontageReference.new(
				index, index, edge_id, logical_id, 0.0, 1.0, first.distance_to(second),
				FoundationParcelFrontageReference.CLASS_PRIMARY if index == 0 else FoundationParcelFrontageReference.CLASS_SECONDARY
			))
	var block := FoundationBlockRecord.new(StringName("p5_block_%s" % semantic_key), boundary, block_references)
	block.source_pass = &"phase_5_test_fixture"
	world.register_record(block)
	var parcel := FoundationParcelRecord.new(StringName("p5_parcel_%s" % semantic_key), block.stable_id, boundary, parcel_references)
	parcel.primary_frontage_index = 0
	parcel.parcel_kind = FoundationParcelRecord.KIND_CORNER if all_frontages else FoundationParcelRecord.KIND_STANDARD
	parcel.buildable = true
	parcel.access_state = FoundationParcelRecord.ACCESS_DIRECT
	parcel.source_pass = &"phase_5_test_fixture"
	world.register_record(parcel)
	return parcel


func _add_simple_parcel(world: FoundationWorldData, semantic_key: StringName, boundary: PackedVector2Array) -> FoundationParcelRecord:
	var edge_id := StringName("simple_edge_%s" % semantic_key)
	var logical_id := StringName("simple_logical_%s" % semantic_key)
	var reference := FoundationParcelFrontageReference.new(0, 0, edge_id, logical_id, 0.0, 1.0, boundary[0].distance_to(boundary[1]), FoundationParcelFrontageReference.CLASS_PRIMARY)
	var references: Array[FoundationParcelFrontageReference] = [reference]
	var parcel := FoundationParcelRecord.new(StringName("p5_parcel_%s" % semantic_key), StringName("p5_block_%s" % semantic_key), boundary, references)
	parcel.primary_frontage_index = 0
	parcel.buildable = true
	parcel.access_state = FoundationParcelRecord.ACCESS_DIRECT
	world.register_record(parcel)
	return parcel


func _footprint_inside(building: FoundationBuildingRecord, parcel: FoundationParcelRecord) -> bool:
	var inside_area := 0.0
	for polygon in Geometry2D.intersect_polygons(building.footprint, parcel.boundary):
		inside_area += absf(FoundationBlockRecord._signed_area(polygon))
	return absf(inside_area - building.footprint_area) <= maxf(0.01, parcel.area * 0.00001)


func _building_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for building in world.get_buildings():
		records.append(building.to_dict())
	return JSON.stringify(records)


func _massing_shape_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for building in world.get_buildings():
		records.append({
			"footprint": Array(building.footprint),
			"target_coverage_ratio": building.target_coverage_ratio,
			"floor_count": building.floor_count,
		})
	return JSON.stringify(records)


func _input_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for parcel in world.get_parcels():
		records.append(parcel.to_dict())
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
