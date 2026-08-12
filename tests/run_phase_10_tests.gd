extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline := _test_determinism_and_contract()
	_test_terrain_suitability()
	_test_serialization_authorship_and_queries()
	_test_validation_and_debug(baseline)
	_test_operation_cap()
	_test_demo_editor_and_scope_contract()
	if _failures.is_empty():
		print("Foundation Phase 10 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 10 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_determinism_and_contract() -> FoundationWorldData:
	var first := _make_fixture(10101)
	var second := _make_fixture(10101)
	var changed := _make_fixture(10102)
	var upstream_before := _upstream_snapshot(first)
	var first_result := FoundationSiteFeatureGenerator.generate(first)
	var second_result := FoundationSiteFeatureGenerator.generate(second)
	var changed_result := FoundationSiteFeatureGenerator.generate(changed)
	_check(first_result.success and second_result.success and changed_result.success, "Phase 10 parking/public-feature generation succeeds")
	_check(_site_snapshot(first) == _site_snapshot(second), "same seed, profile, and upstream records reproduce Phase 10 records and ordering")
	_check(_site_snapshot(first) != _site_snapshot(changed), "a different world seed changes eligible Phase 10 identity or placement variation")
	_check(first.get_parking_facilities().size() >= 2 and first.get_public_features().size() >= 2, "fixture produces both parking facilities and public features")
	_check(first_result.public_target_count == first_result.generated_public_feature_count + first_result.unserved_public_target_count, "public target coverage reconciles generated and unserved targets")
	_check(_upstream_snapshot(first) == upstream_before, "Phase 10 generation does not mutate Phase 1-9 records")

	var accounting_ok := first_result.demand_spaces_total == first_result.supplied_spaces_total + first_result.unmet_demand_total
	var layout_ok := true
	var avoids_overlap := true
	var has_accessible := false
	var has_signed_ownership := false
	var has_multichunk := false
	for parking in first.get_parking_facilities():
		accounting_ok = accounting_ok and parking.demand_spaces == parking.supplied_spaces + parking.unmet_demand
		layout_ok = layout_ok and parking.supplied_spaces == parking.spaces.size() and parking.frontage_segment_index >= 0
		has_accessible = has_accessible or parking.accessible_spaces > 0
		has_multichunk = has_multichunk or parking.owning_chunks.size() > 1
		for chunk in parking.owning_chunks:
			has_signed_ownership = has_signed_ownership or chunk.x < 0 or chunk.y < 0
		for building in first.get_buildings():
			avoids_overlap = avoids_overlap and not FoundationSiteFeatureGenerator.polygons_overlap(parking.footprint, building.footprint)
		for feature in first.get_public_features():
			avoids_overlap = avoids_overlap and not FoundationSiteFeatureGenerator.polygons_overlap(parking.footprint, feature.footprint)
		for index in range(1, parking.spaces.size()):
			layout_ok = layout_ok and not FoundationParkingSpace.less(parking.spaces[index], parking.spaces[index - 1])
	_check(accounting_ok, "parking demand, supply, and unmet demand reconcile deterministically")
	_check(layout_ok and has_accessible, "parking layouts expose ordered compact stalls, access provenance, and accessible-space policy")
	_check(avoids_overlap, "parking and public sites reserve residual parcel land without building overlap")
	_check(has_signed_ownership and has_multichunk, "Phase 10 records support signed coordinates and multi-chunk spatial ownership")

	var kinds: Dictionary = {}
	var linked_anchor := false
	for feature in first.get_public_features():
		kinds[feature.feature_kind] = true
		linked_anchor = linked_anchor or not String(feature.source_anchor_id).is_empty()
	_check(linked_anchor and (kinds.has(FoundationPublicFeatureRecord.KIND_PLAZA) or kinds.has(FoundationPublicFeatureRecord.KIND_CIVIC_MARKER)), "anchor and district-use evidence select public-feature kind and lineage")
	_check(first_result.candidate_evaluations <= first.get_parcels().size() * FoundationSiteFeatureGenerationProfile.new().maximum_candidates_per_parcel * 2, "site placement uses an explicit bounded candidate budget")
	return first


func _test_terrain_suitability() -> void:
	var world := _make_fixture(10151)
	var terrain := FoundationTerrainData.new(
		10151, Vector2i(128, 128), 4.0, 1.0, Vector2i(16, 16), 10, &"phase-10-tests"
	)
	var terrain_before := JSON.stringify(Array(terrain.vertex_heights))
	var result := FoundationSiteFeatureGenerator.generate(world, null, terrain, Vector2i(-32, -32))
	var evidence_ok := result.success and not world.get_parking_facilities().is_empty() and not world.get_public_features().is_empty()
	for parking in world.get_parking_facilities():
		evidence_ok = evidence_ok and bool(parking.suitability_evidence.get("terrain_available", false)) and bool(parking.suitability_evidence.get("terrain_valid", false))
	for feature in world.get_public_features():
		evidence_ok = evidence_ok and bool(feature.suitability_evidence.get("terrain_available", false)) and bool(feature.suitability_evidence.get("terrain_valid", false))
	_check(evidence_ok, "optional authoritative terrain contributes buildability, slope, elevation, and grading-state evidence")
	_check(JSON.stringify(Array(terrain.vertex_heights)) == terrain_before, "Phase 10 terrain suitability reads do not mutate authoritative heights")

	var steep_world := _make_fixture(10152)
	var steep := FoundationTerrainData.new(
		10152, Vector2i(128, 128), 4.0, 1.0, Vector2i(16, 16), 10, &"phase-10-tests"
	)
	for y in range(steep.grid_cells.y + 1):
		for x in range(steep.grid_cells.x + 1):
			steep.set_vertex_height(Vector2i(x, y), float(x * 4), FoundationTerrainData.ModificationSource.NATURAL, false)
	var profile := FoundationSiteFeatureGenerationProfile.new()
	profile.maximum_site_slope_degrees = 5.0
	var steep_result := FoundationSiteFeatureGenerator.generate(steep_world, profile, steep, Vector2i(-32, -32))
	_check(steep_result.success and steep_world.get_parking_facilities().is_empty() and steep_world.get_public_features().is_empty(), "terrain slope/buildability policy deterministically rejects unsuitable sites")


func _test_serialization_authorship_and_queries() -> void:
	var world := _make_fixture(10201)
	FoundationSiteFeatureGenerator.generate(world)
	var parking_records := world.get_parking_facilities()
	var reindexed_parking := parking_records[0]
	for candidate in parking_records:
		if candidate.owning_chunks.size() > 1:
			reindexed_parking = candidate
			break
	var parking := parking_records[1] if parking_records[0] == reindexed_parking else parking_records[0]
	var feature := world.get_public_features()[0]
	parking.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	reindexed_parking.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	feature.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	var parking_snapshot := JSON.stringify(parking.to_dict())
	var feature_snapshot := JSON.stringify(feature.to_dict())
	var old_reindexed_chunks := reindexed_parking.owning_chunks.duplicate()
	var reindex_parcel := world.get_record(reindexed_parking.parent_id) as FoundationParcelRecord
	var old_centroid := reindexed_parking.centroid
	var reindex_minimum := reindex_parcel.world_bounds.position + Vector2(4.0, reindex_parcel.world_bounds.size.y - 20.0)
	reindexed_parking.footprint = PackedVector2Array([
		reindex_minimum, reindex_minimum + Vector2(16.0, 0.0),
		reindex_minimum + Vector2(16.0, 16.0), reindex_minimum + Vector2(0.0, 16.0),
	])
	reindexed_parking.refresh_metrics()
	var reindex_shift := reindexed_parking.centroid - old_centroid
	for space in reindexed_parking.spaces:
		space.position += reindex_shift
	for path in reindexed_parking.access_paths:
		for point_index in range(path.points.size()):
			path.points[point_index] += reindex_shift
	FoundationSiteFeatureGenerator.generate(world)
	_check(
		world.get_record(parking.stable_id) == parking
		and JSON.stringify(parking.to_dict()) == parking_snapshot,
		"locked parking survives regeneration as the same reserved object"
	)
	_check(world.get_record(reindexed_parking.stable_id) == reindexed_parking and reindexed_parking.owning_chunks != old_reindexed_chunks, "overridden parking survives and refreshes authored spatial ownership")
	var stale_bucket_free := true
	for old_chunk in old_reindexed_chunks:
		if old_chunk not in reindexed_parking.owning_chunks:
			stale_bucket_free = stale_bucket_free and not world.get_records_in_chunk(old_chunk, FoundationWorldData.PARKING_FACILITY_LAYER).has(reindexed_parking)
	_check(stale_bucket_free, "authored parking reindexing removes stale chunk-bucket references")
	_check(world.get_record(feature.stable_id) == feature and JSON.stringify(feature.to_dict()) == feature_snapshot, "overridden public feature survives regeneration as the same reserved object")

	var restored := FoundationWorldData.from_dict(world.to_dict())
	_check(_site_snapshot(restored) == _site_snapshot(world), "world manifests round-trip typed Phase 10 records, compact layouts, policy, authorship, and ownership")
	var typed := true
	for restored_parking in restored.get_parking_facilities():
		typed = typed and restored_parking is FoundationParkingFacilityRecord
		for space in restored_parking.spaces:
			typed = typed and space is FoundationParkingSpace
		for path in restored_parking.access_paths:
			typed = typed and path is FoundationParkingAccessPath
	for restored_feature in restored.get_public_features():
		typed = typed and restored_feature is FoundationPublicFeatureRecord
	_check(typed, "world loading restores typed Node-free parking, space/path, and public-feature data")
	var restored_profile := FoundationSiteFeatureGenerationProfile.from_dict(
		restored.get_layer(FoundationWorldData.PARKING_FACILITY_LAYER).metadata["profile"]
	)
	_check(restored_profile.to_dict() == FoundationSiteFeatureGenerationProfile.new().to_dict(), "Phase 10 profile has a complete versioned round-trip seam")

	parking = world.get_parking_facilities()[0]
	_check(world.get_parking_for_parcel(parking.parent_id).has(parking), "parking lineage resolves by parcel")
	_check(world.get_parking_for_block(parking.parent_block_id).has(parking), "parking lineage resolves by block")
	_check(String(parking.parent_building_id).is_empty() or world.get_parking_for_building(parking.parent_building_id).has(parking), "parking lineage resolves by building")
	_check(String(parking.district_id).is_empty() or world.get_parking_for_district(parking.district_id).has(parking), "parking lineage resolves by district")
	feature = world.get_public_features()[0]
	_check(world.get_public_features_for_parcel(feature.parent_id).has(feature) and world.get_public_features_for_block(feature.parent_block_id).has(feature), "public-feature lineage resolves by parcel and block")
	_check(String(feature.district_id).is_empty() or world.get_public_features_for_district(feature.district_id).has(feature), "public-feature lineage resolves by district")
	_check(String(feature.source_anchor_id).is_empty() or world.get_public_features_for_anchor(feature.source_anchor_id).has(feature), "public-feature lineage resolves by source anchor")

	var removed := FoundationSiteFeatureGenerator.clear_generated(world)
	_check(world.get_record(parking.stable_id) == parking and world.get_record(feature.stable_id) == feature, "clearing generated Phase 10 data preserves locked and overridden records")
	_check(int(removed["parking"]) + int(removed["public_features"]) > 0, "clear-generated reports removed generated Phase 10 records")

	var collision_world := _make_fixture(10251)
	FoundationSiteFeatureGenerator.generate(collision_world)
	var collision_authored := collision_world.get_parking_facilities()[0]
	var expected_id := collision_authored.stable_id
	var original_parent := collision_authored.parent_id
	collision_authored.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	collision_authored.parent_id = &"missing_authored_parcel"
	FoundationSiteFeatureGenerator.generate(collision_world)
	var repair_id: StringName
	for candidate in collision_world.get_parking_for_parcel(original_parent):
		if candidate.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			repair_id = candidate.stable_id
	FoundationSiteFeatureGenerator.generate(collision_world)
	_check(not String(repair_id).is_empty() and repair_id != expected_id and collision_world.get_record(repair_id) is FoundationParkingFacilityRecord, "authored stable-ID collisions receive a repeatable deterministic Phase 10 repair identity")


func _test_validation_and_debug(world: FoundationWorldData) -> void:
	var before := _site_snapshot(world)
	var clean_issues := FoundationSiteFeatureValidator.validate(world)
	_check(_site_snapshot(world) == before, "Phase 10 validation is read-only")
	var clean_errors := 0
	for issue in clean_issues:
		if issue.severity == FoundationSiteFeatureValidationIssue.SEVERITY_ERROR:
			clean_errors += 1
	_check(clean_errors == 0, "generated Phase 10 records pass structural validation")

	var parking := world.get_parking_facilities()[0]
	parking.demand_spaces += 1
	parking.spaces[0].position += Vector2(10000.0, 0.0)
	var feature := world.get_public_features()[0]
	feature.source_anchor_id = &"missing_phase_10_anchor"
	var issues := FoundationSiteFeatureValidator.validate(world)
	var kinds: Dictionary = {}
	for issue in issues:
		kinds[issue.kind] = true
	_check(kinds.has(&"parking_accounting_mismatch") and kinds.has(&"invalid_parking_space") and kinds.has(&"missing_source_anchor"), "validation deterministically detects corrupted accounting, layout, and anchor lineage")

	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id in [&"parking_facilities", &"public_features"])
	var parking_provider := registry.get_provider(&"parking_facilities")
	var public_provider := registry.get_provider(&"public_features")
	var builder := registry.build(world)
	_check(builder.line_purposes.has(&"parking_stall") and builder.line_purposes.has(&"public_feature_service") and not builder.labels.is_empty(), "Phase 10 debug providers emit batched stalls, service radii, footprints, and labels")
	var parking_invocations := parking_provider.invocation_count
	var public_invocations := public_provider.invocation_count
	registry.set_layer_enabled(&"parking_facilities", false)
	registry.set_layer_enabled(&"public_features", false)
	var disabled := registry.build(world)
	_check(disabled.get_primitive_count() == 0 and parking_provider.invocation_count == parking_invocations and public_provider.invocation_count == public_invocations, "disabled Phase 10 debug layers invoke no provider work and allocate no primitives")


func _test_operation_cap() -> void:
	var world := _make_fixture(10301)
	var profile := FoundationSiteFeatureGenerationProfile.new()
	profile.maximum_generation_operations = 1
	var result := FoundationSiteFeatureGenerator.generate(world, profile)
	var reported := false
	for diagnostic in result.diagnostics:
		reported = reported or diagnostic.get("kind", "") == "generation_operation_cap"
	_check(not result.success and reported and world.get_parking_facilities().is_empty() and world.get_public_features().is_empty(), "Phase 10 stops and removes partial generated data at its explicit operation cap")


func _test_demo_editor_and_scope_contract() -> void:
	var demo_source := FileAccess.get_file_as_string("res://demo/spatial_model_demo.gd")
	var demo_scene := FileAccess.get_file_as_string("res://demo/spatial_model_demo.tscn")
	var dock_source := FileAccess.get_file_as_string("res://addons/foundation/editor/debug_editor_dock.gd")
	_check(demo_source.contains("FoundationSiteFeatureGenerator") and demo_scene.contains("ParkingToggle") and demo_scene.contains("PublicFeatureToggle") and demo_scene.contains("Phase 10"), "runtime demo exposes Phase 10 generation and visualization")
	_check(dock_source.contains("Generate / Regenerate Parking + Public Features") and dock_source.contains("Clear Generated Parking + Public Features"), "editor dock exposes explicit Phase 10 generation and clear actions")
	var scene := load("res://demo/spatial_model_demo.tscn") as PackedScene
	var demo := scene.instantiate()
	root.add_child(demo)
	var demo_world := demo.get_node("FoundationWorld") as FoundationWorld
	var demo_debug := demo.get_node("FoundationWorld/FoundationDebugView") as FoundationDebugView
	_check(not demo_world.world_data.get_parking_facilities().is_empty() and not demo_world.world_data.get_public_features().is_empty(), "Phase 10 demo produces inspectable parking and public-feature records")
	_check(demo_debug.show_parking_facilities and demo_debug.show_public_features and demo.get_node("%ParkingToggle").button_pressed and demo.get_node("%PublicFeatureToggle").button_pressed, "Phase 10 demo enables independent parking/public debug overlays")
	demo.queue_free()
	var world := _make_fixture(10401)
	FoundationSiteFeatureGenerator.generate(world)
	var forbidden_methods := [
		&"build_mesh", &"create_collision", &"create_material", &"spawn_vehicle", &"simulate_traffic",
		&"create_navigation_mesh", &"assign_address", &"place_vegetation", &"place_utility",
		&"instantiate_prefab", &"create_interior", &"author_override",
	]
	var forbidden := false
	for method_name in forbidden_methods:
		for record in world.get_parking_facilities() + world.get_public_features():
			forbidden = forbidden or record.has_method(method_name)
	_check(not forbidden, "Phase 10 adds no production rendering/collision, traffic/navigation, address, vegetation/utility, prefab/interior, or full-authoring API")


func _make_fixture(seed: int) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 10
	metadata.content_pack_version = &"phase-10-tests"
	metadata.world_bounds = Rect2(-192.0, -128.0, 640.0, 256.0)
	var coordinates := FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(16, 16), Vector2i(2, 2))
	var world := FoundationWorldData.new(metadata, coordinates)
	world.initialize_default_layers()
	world.initialize_partitions()
	_add_site(world, &"residential", Vector2(-120.0, -40.0), FoundationDistrictRecord.USE_RESIDENTIAL, true, 3)
	_add_site(world, &"commercial", Vector2(0.0, -40.0), FoundationDistrictRecord.USE_COMMERCIAL, true, 4)
	_add_site(world, &"open", Vector2(120.0, -40.0), FoundationDistrictRecord.USE_OPEN_SPACE, false, 1)
	_add_site(world, &"civic", Vector2(240.0, -40.0), FoundationDistrictRecord.USE_CIVIC, false, 1)
	var anchor := FoundationCityAnchor.create(
		metadata, FoundationCityAnchor.CATEGORY_PUBLIC_SQUARE, Vector3(280.0, 0.0, 0.0),
		"phase-10-public-square", 30.0, 2.0
	)
	_register(world, anchor)
	return world


func _add_site(
	world: FoundationWorldData,
	key: StringName,
	origin: Vector2,
	use_key: StringName,
	with_building: bool,
	floors: int
) -> void:
	var size := Vector2(80.0, 80.0)
	var boundary := PackedVector2Array([
		origin, origin + Vector2(size.x, 0.0), origin + size, origin + Vector2(0.0, size.y),
	])
	var road_id := StringName("p10_road_%s" % key)
	var road := FoundationRoadEdge.new(
		road_id, &"", &"",
		PackedVector3Array([Vector3(origin.x, 0.0, origin.y), Vector3(origin.x + size.x, 0.0, origin.y)]),
		FoundationRoadEdge.CLASS_LOCAL
	)
	road.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	_register(world, road)
	var block_id := StringName("p10_block_%s" % key)
	var block_references: Array[FoundationBlockBoundaryReference] = [
		FoundationBlockBoundaryReference.new(0, road_id, 0, 0.0, 1.0, size.x),
	]
	var block := FoundationBlockRecord.new(block_id, boundary, block_references)
	_register(world, block)
	var frontage: Array[FoundationParcelFrontageReference] = [
		FoundationParcelFrontageReference.new(0, 0, road_id, &"", 0.0, 1.0, size.x, FoundationParcelFrontageReference.CLASS_PRIMARY),
	]
	var parcel_id := StringName("p10_parcel_%s" % key)
	var parcel := FoundationParcelRecord.new(parcel_id, block_id, boundary, frontage)
	parcel.primary_frontage_index = 0
	_register(world, parcel)
	if with_building:
		var footprint := PackedVector2Array([
			origin + Vector2(4.0, 4.0), origin + Vector2(34.0, 4.0),
			origin + Vector2(34.0, 38.0), origin + Vector2(4.0, 38.0),
		])
		var building := FoundationBuildingRecord.new(StringName("p10_building_%s" % key), parcel_id, block_id, footprint)
		building.floor_count = floors
		building.base_elevation = 2.0
		building.refresh_metrics(parcel.area)
		building.refresh_massing()
		_register(world, building)
	var assignment := FoundationDistrictMemberAssignment.new(
		StringName("p10_assignment_%s" % key), StringName("p10_district_%s" % key), block_id, use_key
	)
	assignment.allowed_uses = [use_key]
	var district := FoundationDistrictRecord.new(StringName("p10_district_%s" % key), [block_id], [boundary])
	district.primary_use = use_key
	district.allowed_uses = [use_key]
	district.assignments = [assignment]
	district.character_key = FoundationDistrictRecord.CHARACTER_CIVIC if use_key in [FoundationDistrictRecord.USE_CIVIC, FoundationDistrictRecord.USE_OPEN_SPACE] else FoundationDistrictRecord.CHARACTER_MIXED_USE
	district.refresh_metrics()
	_register(world, district)


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


func _site_snapshot(world: FoundationWorldData) -> String:
	var values: Array[Dictionary] = []
	for parking in world.get_parking_facilities():
		values.append(parking.to_dict())
	for feature in world.get_public_features():
		values.append(feature.to_dict())
	return JSON.stringify(values)


func _upstream_snapshot(world: FoundationWorldData) -> String:
	var values: Array[Dictionary] = []
	for layer_type in [
		FoundationWorldData.CITY_ANCHOR_LAYER, FoundationWorldData.ROAD_NODE_LAYER,
		FoundationWorldData.ROAD_EDGE_LAYER, FoundationWorldData.ROAD_PATTERN_LAYER,
		FoundationWorldData.LOGICAL_ROAD_LAYER, FoundationWorldData.ROAD_INTERSECTION_LAYER,
		FoundationWorldData.BLOCK_LAYER, FoundationWorldData.PARCEL_LAYER,
		FoundationWorldData.BUILDING_LAYER, FoundationWorldData.FACADE_LAYER,
		FoundationWorldData.DISTRICT_LAYER,
	]:
		var layer := world.get_layer(layer_type)
		if layer == null:
			continue
		for record in layer.get_records():
			values.append(record.to_dict())
	return JSON.stringify(values)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
