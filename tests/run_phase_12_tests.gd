extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profile_and_request_round_trip()
	_test_explicit_selection_and_topology()
	_test_empty_unselected_and_caps()
	_test_concave_signed_geometry()
	_test_determinism_round_trip_and_authoring()
	_test_debug_and_scope()
	if _failures.is_empty():
		print("Foundation Phase 12 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 12 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_profile_and_request_round_trip() -> void:
	var profile := FoundationInteriorGenerationProfile.new()
	profile.preferred_room_span = 7.25
	profile.maximum_selected_buildings = 3
	profile.debug_floor_separation = 0.25
	var restored_profile := FoundationInteriorGenerationProfile.from_dict(profile.to_dict())
	_check(restored_profile.to_dict() == profile.to_dict(), "interior generation profile has a versioned deterministic round trip")
	_check(restored_profile.validation_errors().is_empty(), "restored interior generation profile remains valid")
	var request := FoundationInteriorGenerationRequest.new()
	request.request_id = &"phase_12_round_trip"
	request.building_ids = [&"building_b", &"building_a", &"building_a"]
	request.floor_indices_by_building = {"building_a": [2, 0, 2], "building_b": [1]}
	var restored_request := FoundationInteriorGenerationRequest.from_dict(request.to_dict())
	_check(restored_request.to_dict() == request.to_dict(), "explicit building/floor request has a canonical versioned round trip")
	_check(restored_request.validation_errors(profile).is_empty(), "restored explicit interior request remains valid")


func _test_explicit_selection_and_topology() -> void:
	var world := _make_fixture(12001)
	var request := FoundationInteriorGenerationRequest.new()
	request.building_ids = [&"p12_building_a"]
	request.floor_indices_by_building = {"p12_building_a": [0, 1, 2]}
	var result := FoundationInteriorGenerator.generate(world, request)
	var interior := world.get_interior_for_building(&"p12_building_a")
	_check(result.success and result.generated_interior_count == 1 and interior != null, "explicit building selection creates one typed interior record")
	_check(world.get_interior_for_building(&"p12_building_b") == null, "unselected buildings remain untouched")
	_check(interior.floors.size() == 3 and interior.vertical_connectors.size() == 2, "selected consecutive floors receive vertical connectivity")
	var topology_ok := true
	for floor in interior.floors:
		topology_ok = topology_ok and not floor.rooms.is_empty() and floor.get_room(floor.circulation_room_id) != null
		var exteriors := 0
		for portal in floor.portals:
			if portal.portal_kind == FoundationInteriorPortal.KIND_EXTERIOR:
				exteriors += 1
		topology_ok = topology_ok and exteriors == (1 if floor.floor_index == 0 else 0)
	_check(topology_ok, "floors contain rooms, circulation identity, and exactly one ground exterior portal")
	var ground := interior.get_floor(0)
	var entrance: FoundationInteriorPortal
	for portal in ground.portals:
		if portal.portal_kind == FoundationInteriorPortal.KIND_EXTERIOR:
			entrance = portal
	_check(entrance != null and entrance.source_facade_id == &"p12_facade" and entrance.source_module_id == &"p12_entrance", "ground entrance retains Phase 7 facade/module provenance")
	var issues := FoundationInteriorValidator.validate(world)
	_check(issues.is_empty(), "generated selective interior passes geometry, coverage, topology, lineage, and ownership validation")
	_check(interior.primary_use == FoundationDistrictRecord.USE_COMMERCIAL, "interior consumes Phase 8 district use lineage")


func _test_empty_unselected_and_caps() -> void:
	var world := _make_fixture(12002)
	var empty := FoundationInteriorGenerator.generate(world, FoundationInteriorGenerationRequest.new())
	_check(empty.success and world.get_interiors().is_empty(), "empty explicit selection is a true no-work request")
	var request := FoundationInteriorGenerationRequest.new()
	request.building_ids = [&"p12_building_a", &"p12_building_b"]
	var profile := FoundationInteriorGenerationProfile.new()
	profile.maximum_selected_buildings = 1
	var rejected := FoundationInteriorGenerator.generate(world, request, profile)
	_check(not rejected.success and world.get_interiors().is_empty(), "selected-building cap rejects excessive requests without partial generation")
	request.building_ids = [&"missing_building"]
	var skipped := FoundationInteriorGenerator.generate(world, request)
	_check(skipped.success and skipped.skipped_building_count == 1 and world.get_interiors().is_empty(), "missing selected buildings are diagnosed and skipped deterministically")
	request.building_ids = [&"p12_building_a"]
	profile = FoundationInteriorGenerationProfile.new()
	profile.maximum_generation_operations = 1
	var operation_capped := FoundationInteriorGenerator.generate(world, request, profile)
	_check(not operation_capped.success and world.get_interiors().is_empty(), "operation-cap failure removes partial generator-owned interior data")


func _test_concave_signed_geometry() -> void:
	var world := _make_fixture(12005)
	var request := FoundationInteriorGenerationRequest.new()
	request.building_ids = [&"p12_building_b"]
	request.floor_indices_by_building = {"p12_building_b": [0, 1]}
	var result := FoundationInteriorGenerator.generate(world, request)
	var interior := world.get_interior_for_building(&"p12_building_b")
	_check(result.success and interior != null and interior.floors.size() == 2, "rotated-grid generation accepts a signed concave source footprint")
	var issues := FoundationInteriorValidator.validate(world)
	if not issues.is_empty():
		for issue in issues:
			print("Phase 12 concave diagnostic: ", issue.to_dict())
	_check(issues.is_empty(), "signed concave interior geometry retains complete coverage and connected topology")


func _test_determinism_round_trip_and_authoring() -> void:
	var world := _make_fixture(12003)
	var request := FoundationInteriorGenerationRequest.new()
	request.building_ids = [&"p12_building_a"]
	request.include_all_floors = true
	FoundationInteriorGenerator.generate(world, request)
	var first := FoundationSpatialRecordCodec.canonical_json(world.get_interior_for_building(&"p12_building_a").to_dict())
	FoundationInteriorGenerator.generate(world, request)
	var second := FoundationSpatialRecordCodec.canonical_json(world.get_interior_for_building(&"p12_building_a").to_dict())
	_check(first == second, "same seed, building, request, and profile regenerate byte-stable interior data")
	var restored := FoundationWorldData.from_dict(world.to_dict())
	var restored_interior := restored.get_interior_for_building(&"p12_building_a")
	_check(restored_interior != null and FoundationSpatialRecordCodec.canonical_json(restored.to_dict()) == FoundationSpatialRecordCodec.canonical_json(world.to_dict()), "world manifest round-trips typed nested interior data")
	var translated := FoundationSpatialRecordCodec.translate_record_data(restored_interior.to_dict(), Vector2(10.0, -4.0))
	var translated_interior := FoundationSpatialRecordCodec.record_from_dict(translated) as FoundationInteriorRecord
	_check(translated_interior.source_footprint[0] == restored_interior.source_footprint[0] + Vector2(10.0, -4.0), "authoring codec translates nested interior geometry")
	var policy := FoundationAuthoringPolicy.new()
	_check(FoundationWorldData.INTERIOR_LAYER in policy.supported_layers() and FoundationInteriorRecord.RECORD_KIND in policy.supported_record_kinds(), "Phase 11 authoring dependency policy includes Phase 12 interiors")
	restored_interior.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	var locked_snapshot := FoundationSpatialRecordCodec.canonical_json(restored_interior.to_dict())
	FoundationInteriorGenerator.generate(restored, request)
	_check(FoundationSpatialRecordCodec.canonical_json(restored.get_interior_for_building(&"p12_building_a").to_dict()) == locked_snapshot, "regeneration preserves locked interior records")
	restored_interior.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	var overridden_snapshot := FoundationSpatialRecordCodec.canonical_json(restored_interior.to_dict())
	FoundationInteriorGenerator.generate(restored, request)
	_check(FoundationSpatialRecordCodec.canonical_json(restored.get_interior_for_building(&"p12_building_a").to_dict()) == overridden_snapshot, "regeneration preserves overridden interior records")


func _test_debug_and_scope() -> void:
	var world := _make_fixture(12004)
	var request := FoundationInteriorGenerationRequest.new()
	request.building_ids = [&"p12_building_a"]
	FoundationInteriorGenerator.generate(world, request)
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"interiors")
	var geometry := registry.build(world, {"interior_floor_index": 0})
	_check(geometry.get_primitive_count() > 0 and registry.last_provider_invocations == 1, "interior debug provider emits disposable batched room and portal geometry")
	registry.enabled = false
	_check(registry.build(world).get_primitive_count() == 0 and registry.last_provider_invocations == 0, "disabled debug registry retains the zero-work path")
	var forbidden := [&"build_navmesh", &"spawn_door", &"place_furniture", &"instantiate_room", &"create_collision"]
	var found := false
	for method_name in forbidden:
		found = found or FoundationInteriorGenerator.new().has_method(method_name)
	_check(not found, "Phase 12 adds abstract interior data without navigation, runtime doors, furniture, collision, or production meshes")


func _make_fixture(seed: int) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 12
	metadata.content_pack_version = &"phase-12-tests"
	metadata.world_bounds = Rect2(-128.0, -128.0, 512.0, 512.0)
	var world := FoundationWorldData.new(metadata, FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(16, 16), Vector2i(2, 2)))
	world.initialize_default_layers()
	world.initialize_partitions()
	var block_boundary := PackedVector2Array([Vector2(-32, -32), Vector2(128, -32), Vector2(128, 96), Vector2(-32, 96)])
	var block := FoundationBlockRecord.new(&"p12_block", block_boundary)
	_register(world, block)
	var parcel_a := FoundationParcelRecord.new(&"p12_parcel_a", block.stable_id, PackedVector2Array([Vector2(0, 0), Vector2(48, 0), Vector2(48, 40), Vector2(0, 40)]))
	var parcel_b := FoundationParcelRecord.new(&"p12_parcel_b", block.stable_id, PackedVector2Array([Vector2(64, 0), Vector2(112, 0), Vector2(112, 40), Vector2(64, 40)]))
	_register(world, parcel_a)
	_register(world, parcel_b)
	var building_a := FoundationBuildingRecord.new(&"p12_building_a", parcel_a.stable_id, block.stable_id, PackedVector2Array([Vector2(2, 2), Vector2(46, 2), Vector2(46, 36), Vector2(2, 36)]))
	building_a.floor_count = 3
	building_a.floor_height = 3.4
	building_a.orientation_degrees = 27.0
	building_a.refresh_metrics(parcel_a.area)
	building_a.refresh_massing()
	_register(world, building_a)
	var building_b := FoundationBuildingRecord.new(&"p12_building_b", parcel_b.stable_id, block.stable_id, PackedVector2Array([Vector2(66, 36), Vector2(90, 36), Vector2(90, 18), Vector2(110, 18), Vector2(110, 2), Vector2(66, 2)]))
	building_b.floor_count = 2
	building_b.orientation_degrees = 0.0
	building_b.refresh_metrics(parcel_b.area)
	building_b.refresh_massing()
	_register(world, building_b)
	var facade := FoundationFacadeRecord.new(&"p12_facade", building_a.stable_id, 0, Vector2(2, 2), Vector2(46, 2))
	facade.facade_role = FoundationFacadeRecord.ROLE_PRIMARY
	facade.parent_parcel_id = parcel_a.stable_id
	facade.parent_block_id = block.stable_id
	var entrance := FoundationFacadeModule.new(&"p12_entrance", FoundationFacadeModule.KIND_ENTRANCE, 0, 0)
	entrance.horizontal_start = 20.0
	entrance.horizontal_end = 22.0
	facade.modules.append(entrance)
	facade.entrance_module_id = entrance.module_id
	facade.refresh_metrics()
	_register(world, facade)
	var district := FoundationDistrictRecord.new(&"p12_district", [&"p12_block"], [block_boundary])
	district.primary_use = FoundationDistrictRecord.USE_COMMERCIAL
	_register(world, district)
	return world


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
