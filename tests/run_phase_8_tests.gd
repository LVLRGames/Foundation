extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline := _test_deterministic_allocation()
	_test_road_barrier_weighting()
	_test_exact_chunk_boundary_adjacency()
	_test_authorship_serialization_and_lineage()
	_test_validation_and_debug(baseline)
	_test_large_bounded_fixture()
	_test_operation_cap()
	_test_demo_contract()
	_test_scope_exclusions(baseline)
	if _failures.is_empty():
		print("Foundation Phase 8 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 8 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_deterministic_allocation() -> FoundationWorldData:
	var first := _make_fixture_world(8101)
	var second := _make_fixture_world(8101)
	var changed := _make_fixture_world(8102)
	var inputs_before := _upstream_snapshot(first)
	var first_result := FoundationDistrictGenerator.generate(first)
	var second_result := FoundationDistrictGenerator.generate(second)
	var changed_result := FoundationDistrictGenerator.generate(changed)
	_check(first_result.success and second_result.success and changed_result.success, "district generation succeeds")
	_check(_district_snapshot(first) == _district_snapshot(second), "same seed, profile, and upstream records reproduce district membership and policy")
	_check(_district_snapshot(first) != _district_snapshot(changed), "eligible seed change alters stable district policy identity or variation")
	_check(first.get_districts().size() == 3 and first_result.assigned_block_count == 9, "three disconnected components produce three complete districts")
	var claims: Dictionary = {}
	var assignment_contract := true
	var canonical_exteriors := true
	var characters: Dictionary = {}
	for district in first.get_districts():
		characters[district.character_key] = true
		canonical_exteriors = canonical_exteriors and district.boundary_components.size() == 1
		assignment_contract = assignment_contract and district.assignments.size() == district.member_block_ids.size()
		assignment_contract = assignment_contract and district.allowed_uses.has(district.primary_use)
		for block_id in district.member_block_ids:
			claims[block_id] = int(claims.get(block_id, 0)) + 1
			var assignment := district.get_assignment(block_id)
			assignment_contract = assignment_contract and assignment != null and assignment.allowed_uses.has(assignment.primary_use)
	var exact_coverage := claims.size() == first.get_blocks().size()
	for count in claims.values():
		exact_coverage = exact_coverage and int(count) == 1
	_check(exact_coverage, "every eligible block is assigned exactly once")
	_check(assignment_contract, "district and member land-use policies are complete, ordered, and internally allowed")
	_check(canonical_exteriors, "contiguous member blocks union into one canonical district exterior without internal seams")
	_check(characters.has(FoundationDistrictRecord.CHARACTER_DOWNTOWN) and characters.has(FoundationDistrictRecord.CHARACTER_INDUSTRIAL) and characters.has(FoundationDistrictRecord.CHARACTER_RURAL), "anchors and road-pattern intent yield distinct downtown, industrial, and rural characters")
	_check(first_result.adjacency_candidate_comparisons < first_result.unrestricted_pair_reference_count, "block adjacency uses bounded spatial candidates rather than unrestricted all-pairs work")
	_check(first_result.generation_operation_count < FoundationDistrictGenerationProfile.new().maximum_generation_operations, "district allocation remains within its explicit operation cap")
	_check(_upstream_snapshot(first) == inputs_before, "district generation does not mutate blocks, parcels, buildings, facades, roads, anchors, or patterns")
	var signed_ownership := false
	for district in first.get_districts():
		var negative := false
		var nonnegative := false
		for chunk in district.owning_chunks:
			negative = negative or chunk.x < 0 or chunk.y < 0
			nonnegative = nonnegative or chunk.x >= 0 or chunk.y >= 0
		signed_ownership = signed_ownership or (negative and nonnegative)
	_check(signed_ownership, "district coverage is indexed across signed chunk ownership")
	return first


func _test_road_barrier_weighting() -> void:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = 8151
	metadata.generator_version = 8
	metadata.content_pack_version = &"phase-8-barrier"
	metadata.world_bounds = Rect2(-64.0, -64.0, 256.0, 256.0)
	var world := FoundationWorldData.new(metadata, FoundationCoordinateSystem.new())
	world.initialize_default_layers()
	world.initialize_partitions()
	_add_barrier_block(world, &"barrier_a", Vector2.ZERO, [&"outer_a_top", &"barrier_arterial", &"barrier_local", &"outer_a_left"])
	_add_barrier_block(world, &"barrier_b", Vector2(40.0, 0.0), [&"outer_b_top", &"outer_b_right", &"outer_b_bottom", &"barrier_arterial"])
	_add_barrier_block(world, &"barrier_c", Vector2(0.0, 40.0), [&"barrier_local", &"outer_c_right", &"outer_c_bottom", &"outer_c_left"])
	var profile := FoundationDistrictGenerationProfile.new()
	profile.target_blocks_per_district = 2
	profile.maximum_blocks_per_district = 2
	var result := FoundationDistrictGenerator.generate(world, profile)
	var district := world.get_district_for_block(&"barrier_a")
	_check(result.success and district.member_block_ids.has(&"barrier_c") and not district.member_block_ids.has(&"barrier_b"), "district growth prefers a compatible local boundary over an arterial barrier")


func _test_exact_chunk_boundary_adjacency() -> void:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = 8171
	metadata.generator_version = 8
	metadata.content_pack_version = &"phase-8-chunk-boundary"
	metadata.world_bounds = Rect2(0.0, 0.0, 256.0, 128.0)
	var world := FoundationWorldData.new(metadata, FoundationCoordinateSystem.new())
	world.initialize_default_layers()
	world.initialize_partitions()
	_add_barrier_block(world, &"chunk_left", Vector2(88.0, 0.0), [&"chunk_left_top", &"chunk_shared", &"chunk_left_bottom", &"chunk_left_outer"])
	_add_barrier_block(world, &"chunk_right", Vector2(128.0, 0.0), [&"chunk_right_top", &"chunk_right_outer", &"chunk_right_bottom", &"chunk_shared"])
	var profile := FoundationDistrictGenerationProfile.new()
	profile.target_blocks_per_district = 2
	profile.maximum_blocks_per_district = 2
	var result := FoundationDistrictGenerator.generate(world, profile)
	_check(result.success and world.get_districts().size() == 1 and world.get_districts()[0].member_block_ids.size() == 2, "adjacent blocks connect across an exact half-open chunk boundary through bounded neighbor buckets")


func _test_authorship_serialization_and_lineage() -> void:
	var world := _make_fixture_world(8201)
	FoundationDistrictGenerator.generate(world)
	var district := world.get_districts()[0]
	district.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	var locked_snapshot := JSON.stringify(district.to_dict())
	FoundationDistrictGenerator.generate(world)
	_check(world.get_record(district.stable_id) == district and JSON.stringify(district.to_dict()) == locked_snapshot, "locked district survives regeneration as the same object and reserves its blocks")
	district.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	var original_chunks := district.owning_chunks.duplicate()
	var shifted: Array[PackedVector2Array] = []
	for component in district.boundary_components:
		var points := PackedVector2Array()
		for point in component:
			points.append(point + Vector2(640.0, 0.0))
		shifted.append(points)
	district.boundary_components = shifted
	district.refresh_metrics()
	FoundationDistrictGenerator.generate(world)
	_check(world.get_record(district.stable_id) == district and district.owning_chunks != original_chunks, "overridden district survives and refreshes authored spatial ownership")
	var restored := FoundationWorldData.from_dict(world.to_dict())
	_check(_district_snapshot(restored) == _district_snapshot(world), "typed districts, assignments, policies, authorship, and ownership serialize round-trip")
	var typed := true
	for restored_district in restored.get_districts():
		typed = typed and restored_district is FoundationDistrictRecord
		for assignment in restored_district.assignments:
			typed = typed and assignment is FoundationDistrictMemberAssignment
	_check(typed, "world manifest restores typed Node-free district and assignment data")
	var restored_profile := FoundationDistrictGenerationProfile.from_dict(restored.get_layer(FoundationWorldData.DISTRICT_LAYER).metadata["profile"])
	_check(restored_profile.to_dict() == FoundationDistrictGenerationProfile.new().to_dict(), "district profile has a versioned round-trip seam")
	var block := world.get_blocks()[0]
	var parcel: FoundationParcelRecord
	var building: FoundationBuildingRecord
	var facade: FoundationFacadeRecord
	for candidate in world.get_parcels():
		if candidate.parent_id == block.stable_id:
			parcel = candidate
			break
	if parcel != null:
		for candidate in world.get_buildings():
			if candidate.parent_id == parcel.stable_id:
				building = candidate
				break
	if building != null:
		for candidate in world.get_facades():
			if candidate.parent_id == building.stable_id:
				facade = candidate
				break
	var expected := world.get_district_for_block(block.stable_id)
	_check(expected != null and world.get_district_for_parcel(parcel.stable_id) == expected and world.get_district_for_building(building.stable_id) == expected and world.get_district_for_facade(facade.stable_id) == expected, "district lineage queries resolve block, parcel, building, and facade records")
	var collision_world := _make_fixture_world(8251)
	FoundationDistrictGenerator.generate(collision_world)
	var authored := collision_world.get_districts()[0]
	var expected_id := authored.stable_id
	var original_members := authored.member_block_ids.duplicate()
	authored.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	authored.member_block_ids = [&"missing_authored_block"]
	FoundationDistrictGenerator.generate(collision_world)
	var repair_id: StringName
	for candidate in collision_world.get_districts():
		if candidate.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED and candidate.member_block_ids == original_members:
			repair_id = candidate.stable_id
	FoundationDistrictGenerator.generate(collision_world)
	_check(not String(repair_id).is_empty() and repair_id != expected_id and collision_world.get_record(repair_id) is FoundationDistrictRecord, "authored stable-ID collisions receive a repeatable deterministic district repair identity")


func _test_validation_and_debug(world: FoundationWorldData) -> void:
	var before := _district_snapshot(world)
	FoundationDistrictValidator.validate(world, null, false)
	_check(_district_snapshot(world) == before, "read-only district validation does not mutate records")
	var corrupted := world.get_districts()[0]
	corrupted.total_area += 1.0
	corrupted.boundary_components[0][0] += Vector2(1.0, 0.0)
	corrupted.road_class_exposure[String(FoundationRoadEdge.CLASS_LOCAL)] = float(corrupted.road_class_exposure.get(String(FoundationRoadEdge.CLASS_LOCAL), 0.0)) + 1.0
	corrupted.assignments[0].primary_use = &"unsupported_use"
	corrupted.assignments[0].district_id = &"wrong_district"
	var issues := FoundationDistrictValidator.validate(world, null, true)
	var kinds: Dictionary = {}
	for issue in issues:
		kinds[issue.kind] = true
	_check(kinds.has(&"district_area_mismatch") and kinds.has(&"boundary_components_mismatch") and kinds.has(&"road_exposure_mismatch") and kinds.has(&"assignment_use_not_allowed") and kinds.has(&"assignment_district_mismatch"), "district validation recomputes geometry/access metrics and rejects corrupt assignment lineage/use policy")
	_check(corrupted.validation_state == FoundationDistrictRecord.INVALID, "district validation marks corrupt generated records invalid")
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"districts")
	var provider := registry.get_provider(&"districts")
	var builder := registry.build(world)
	_check(builder.line_purposes.has(&"district_boundary") and not builder.triangle_vertices.is_empty(), "district debug provider emits batched coverage fills and boundaries")
	_check(builder.line_purposes.has(&"district_seed_link") and not builder.labels.is_empty(), "district debug exposes source influence links and planning labels")
	var invocation_count := provider.invocation_count
	registry.set_layer_enabled(&"districts", false)
	var disabled := registry.build(world)
	_check(disabled.get_primitive_count() == 0 and provider.invocation_count == invocation_count, "disabled district debug performs no provider work")


func _test_operation_cap() -> void:
	var world := _make_fixture_world(8301)
	var profile := FoundationDistrictGenerationProfile.new()
	profile.maximum_generation_operations = 1
	var result := FoundationDistrictGenerator.generate(world, profile)
	var reported := false
	for diagnostic in result.diagnostics:
		reported = reported or diagnostic.get("kind", "") == "generation_operation_cap"
	_check(not result.success and reported, "district generation stops with a deterministic operation-cap diagnostic")


func _test_large_bounded_fixture() -> void:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = 8351
	metadata.generator_version = 8
	metadata.content_pack_version = &"phase-8-large"
	metadata.world_bounds = Rect2(0.0, 0.0, 1600.0, 1200.0)
	var world := FoundationWorldData.new(metadata, FoundationCoordinateSystem.new())
	world.initialize_default_layers()
	world.initialize_partitions()
	for index in range(12):
		var column := index % 4
		var row := index / 4
		_add_component(world, StringName("large_%02d" % index), Vector2(column * 320.0, row * 320.0), FoundationRoadEdge.CLASS_LOCAL)
	var profile := FoundationDistrictGenerationProfile.new()
	var result := FoundationDistrictGenerator.generate(world, profile)
	_check(result.success and result.assigned_block_count == 36 and result.generation_operation_count < profile.maximum_generation_operations, "larger district fixture covers every block within the explicit work cap")
	_check(result.adjacency_candidate_comparisons < result.unrestricted_pair_reference_count, "larger fixture proves adjacency candidate work stays below unrestricted all-pairs comparison")


func _test_demo_contract() -> void:
	var scene := load("res://demo/spatial_model_demo.tscn") as PackedScene
	var demo := scene.instantiate()
	root.add_child(demo)
	var world_node := demo.get_node("FoundationWorld") as FoundationWorld
	var debug_view := demo.get_node("FoundationWorld/FoundationDebugView") as FoundationDebugView
	_check(not world_node.world_data.get_districts().is_empty(), "Phase 8 demo generates district planning records")
	_check(debug_view.show_districts and demo.get_node("%DistrictToggle").button_pressed, "Phase 8 demo exposes the district overlay")
	var before := _district_snapshot(world_node.world_data)
	demo.get_node("%StageOptions").select(6)
	demo.call("_regenerate_selected_stage")
	_check(_district_snapshot(world_node.world_data) == before, "Phase 8 demo same-seed district regeneration is stable")
	var editor_source := FileAccess.get_file_as_string("res://addons/foundation/editor/debug_editor_dock.gd")
	_check(editor_source.contains("Generate / Regenerate Districts") and editor_source.contains("Clear Generated Districts"), "editor dock exposes explicit district generation and clearing controls")
	demo.free()


func _test_scope_exclusions(world: FoundationWorldData) -> void:
	var district := world.get_districts()[0]
	_check(ClassDB.is_parent_class(district.get_class(), "RefCounted") and not ClassDB.is_parent_class(district.get_class(), "Node"), "district contract remains renderer-independent Node-free data")
	var forbidden_methods := [
		&"grade_terrain", &"create_building_pad", &"create_address", &"place_parking",
		&"place_public_feature", &"build_mesh", &"create_collision", &"create_material",
		&"instantiate_prefab", &"create_interior", &"create_navigation_mesh",
		&"spawn_traffic", &"place_vegetation",
	]
	var forbidden := false
	for method_name in forbidden_methods:
		forbidden = forbidden or district.has_method(method_name) or world.has_method(method_name)
	_check(not forbidden, "Phase 8 introduces no grading, address, parking/public placement, production rendering, prefab/interior, navigation/traffic, or vegetation API")


func _make_fixture_world(seed: int) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 8
	metadata.content_pack_version = &"phase-8-tests"
	metadata.world_bounds = Rect2(-512.0, -256.0, 1280.0, 512.0)
	var world := FoundationWorldData.new(metadata, FoundationCoordinateSystem.new())
	world.initialize_default_layers()
	world.initialize_partitions()
	_add_component(world, &"downtown", Vector2(-150.0, -20.0), FoundationRoadEdge.CLASS_LOCAL)
	_add_component(world, &"industrial", Vector2(120.0, -20.0), FoundationRoadEdge.CLASS_ARTERIAL)
	_add_component(world, &"rural", Vector2(390.0, -20.0), FoundationRoadEdge.CLASS_DIRT)
	var downtown_anchor := FoundationCityAnchor.create(metadata, FoundationCityAnchor.CATEGORY_CITY_CENTER, Vector3(-110.0, 0.0, 0.0), "p8-downtown", 100.0, 2.0)
	var industrial_anchor := FoundationCityAnchor.create(metadata, FoundationCityAnchor.CATEGORY_INDUSTRIAL_CENTER, Vector3(160.0, 0.0, 0.0), "p8-industrial", 100.0, 2.0)
	world.register_record(downtown_anchor)
	world.register_record(industrial_anchor)
	var rural_pattern := FoundationRoadPatternArea.create(metadata, "p8-rural", Rect2(360.0, -80.0, 180.0, 160.0), FoundationRoadPatternArea.RURAL_TERRAIN_FOLLOWING)
	world.register_record(rural_pattern)
	_add_lineage_fixture(world, world.get_blocks()[0])
	return world


func _add_component(world: FoundationWorldData, key: StringName, origin: Vector2, road_class: StringName) -> void:
	var size := 40.0
	for column in range(3):
		var minimum := origin + Vector2(float(column) * size, 0.0)
		var boundary := PackedVector2Array([minimum, minimum + Vector2(size, 0.0), minimum + Vector2(size, size), minimum + Vector2(0.0, size)])
		var references: Array[FoundationBlockBoundaryReference] = []
		var road_ids: Array[StringName] = []
		for segment in range(4):
			var road_id := StringName("p8_road_%s_%d_%d" % [key, column, segment])
			if segment == 1 and column < 2:
				road_id = StringName("p8_shared_%s_%d" % [key, column])
			elif segment == 3 and column > 0:
				road_id = StringName("p8_shared_%s_%d" % [key, column - 1])
			_ensure_road(world, road_id, boundary[segment], boundary[(segment + 1) % 4], road_class)
			road_ids.append(road_id)
			references.append(FoundationBlockBoundaryReference.new(segment, road_id, 0, 0.0, 1.0, size))
		var block := FoundationBlockRecord.new(StringName("p8_block_%s_%d" % [key, column]), boundary, references)
		world.register_record(block)


func _add_barrier_block(world: FoundationWorldData, block_id: StringName, origin: Vector2, segment_road_ids: Array[StringName]) -> void:
	var size := 40.0
	var boundary := PackedVector2Array([origin, origin + Vector2(size, 0.0), origin + Vector2(size, size), origin + Vector2(0.0, size)])
	var references: Array[FoundationBlockBoundaryReference] = []
	for segment in range(4):
		var road_id := segment_road_ids[segment]
		var road_class := FoundationRoadEdge.CLASS_ARTERIAL if road_id == &"barrier_arterial" else FoundationRoadEdge.CLASS_LOCAL
		_ensure_road(world, road_id, boundary[segment], boundary[(segment + 1) % 4], road_class)
		references.append(FoundationBlockBoundaryReference.new(segment, road_id, 0, 0.0, 1.0, size))
	world.register_record(FoundationBlockRecord.new(block_id, boundary, references))


func _ensure_road(world: FoundationWorldData, road_id: StringName, a: Vector2, b: Vector2, road_class: StringName) -> void:
	if world.get_record(road_id) != null:
		return
	var edge := FoundationRoadEdge.new(road_id, &"", &"", PackedVector3Array([Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y)]), road_class)
	edge.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	world.register_record(edge)


func _add_lineage_fixture(world: FoundationWorldData, block: FoundationBlockRecord) -> void:
	var parcel_id := StringName("p8_parcel_lineage")
	var frontage: Array[FoundationParcelFrontageReference] = [FoundationParcelFrontageReference.new(0, 0, block.boundary_road_ids[0], &"", 0.0, 1.0, 40.0, FoundationParcelFrontageReference.CLASS_PRIMARY)]
	var parcel := FoundationParcelRecord.new(parcel_id, block.stable_id, block.outer_boundary, frontage)
	parcel.primary_frontage_index = 0
	world.register_record(parcel)
	var building := FoundationBuildingRecord.new(&"p8_building_lineage", parcel.stable_id, block.stable_id, block.outer_boundary)
	building.floor_count = 3
	building.floor_height = 3.2
	building.refresh_metrics(parcel.area)
	building.refresh_massing()
	world.register_record(building)
	var facade := FoundationFacadeRecord.new(&"p8_facade_lineage", building.stable_id, 0, block.outer_boundary[0], block.outer_boundary[1])
	facade.parent_parcel_id = parcel.stable_id
	facade.parent_block_id = block.stable_id
	world.register_record(facade)


func _district_snapshot(world: FoundationWorldData) -> String:
	var values: Array[Dictionary] = []
	for district in world.get_districts():
		values.append(district.to_dict())
	return JSON.stringify(values)


func _upstream_snapshot(world: FoundationWorldData) -> String:
	var values: Array[Dictionary] = []
	for layer_type in [FoundationWorldData.CITY_ANCHOR_LAYER, FoundationWorldData.ROAD_PATTERN_LAYER, FoundationWorldData.ROAD_EDGE_LAYER, FoundationWorldData.BLOCK_LAYER, FoundationWorldData.PARCEL_LAYER, FoundationWorldData.BUILDING_LAYER, FoundationWorldData.FACADE_LAYER]:
		for record in world.get_layer(layer_type).get_records():
			values.append(record.to_dict())
	return JSON.stringify(values)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
