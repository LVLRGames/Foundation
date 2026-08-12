extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline := _test_deterministic_modular_grammar()
	_test_signed_spatial_ownership()
	_test_authored_regeneration_and_serialization()
	_test_validation_and_non_mutation()
	_test_debug_contract(baseline)
	_test_bounded_work()
	_test_demo_contract()
	_test_scope_exclusions(baseline)
	if _failures.is_empty():
		print("Foundation Phase 7 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 7 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_deterministic_modular_grammar() -> FoundationWorldData:
	var first := _make_world(7101)
	var second := _make_world(7101)
	var changed := _make_world(7102)
	_add_building_fixture(first, &"primary")
	_add_building_fixture(second, &"primary")
	_add_building_fixture(changed, &"primary")
	var inputs_before := _input_snapshot(first)
	var first_result := FoundationFacadeGenerator.generate(first)
	var second_result := FoundationFacadeGenerator.generate(second)
	var changed_result := FoundationFacadeGenerator.generate(changed)
	_check(first_result.success and second_result.success and changed_result.success, "modular facade generation succeeds")
	_check(first.get_facades().size() == 4, "one facade record is generated per eligible rectangular footprint edge")
	_check(_facade_snapshot(first) == _facade_snapshot(second), "same seed, profile, and buildings reproduce facade IDs, roles, grids, and modules")
	_check(_module_kind_snapshot(first) != _module_kind_snapshot(changed), "eligible seed change alters the modular opening pattern through named streams")
	var primary_count := 0
	var rear_count := 0
	var side_count := 0
	var entrance_count := 0
	var module_count := 0
	var valid := true
	for facade in first.get_facades():
		primary_count += 1 if facade.facade_role == FoundationFacadeRecord.ROLE_PRIMARY else 0
		rear_count += 1 if facade.facade_role == FoundationFacadeRecord.ROLE_REAR else 0
		side_count += 1 if facade.facade_role == FoundationFacadeRecord.ROLE_SIDE else 0
		module_count += facade.modules.size()
		valid = valid and facade.validation_state == FoundationFacadeRecord.VALID
		valid = valid and facade.modules.size() == facade.bay_count * facade.floor_count
		valid = valid and facade.bay_width >= 2.199 and facade.bay_width <= 4.401
		for module in facade.modules:
			entrance_count += 1 if module.kind == FoundationFacadeModule.KIND_ENTRANCE else 0
			if module.kind == FoundationFacadeModule.KIND_ENTRANCE:
				valid = valid and facade.facade_role == FoundationFacadeRecord.ROLE_PRIMARY and module.floor_index == 0
	_check(primary_count == 1 and rear_count == 1 and side_count == 2, "facade roles deterministically classify primary, rear, and side edges")
	_check(entrance_count == 1, "building grammar places exactly one ground-floor entrance on the primary facade")
	_check(valid and module_count == first_result.generated_module_count, "facade grids are complete, bounded, and valid")
	_check(first_result.window_module_count > 0 and first_result.entrance_module_count == 1, "grammar emits explicit window and entrance modules")
	_check(_input_snapshot(first) == inputs_before, "Phase 7 does not mutate buildings, parcels, blocks, roads, or terrain-backed inputs")
	return first


func _test_signed_spatial_ownership() -> void:
	var world := _make_world(7201, Rect2(-512.0, -512.0, 1024.0, 1024.0))
	_add_building_fixture(world, &"signed", Vector2(-128.0, -128.0), Vector2(300.0, 180.0))
	FoundationFacadeGenerator.generate(world)
	var has_negative := false
	var has_positive := false
	var indexed := true
	for facade in world.get_facades():
		for chunk in facade.owning_chunks:
			has_negative = has_negative or chunk.x < 0 or chunk.y < 0
			has_positive = has_positive or chunk.x >= 0 or chunk.y >= 0
			indexed = indexed and facade in world.get_records_in_chunk(chunk, FoundationWorldData.FACADE_LAYER)
	_check(has_negative and has_positive and indexed, "signed and cross-chunk facade segments are spatially indexed in every owning partition")


func _test_authored_regeneration_and_serialization() -> void:
	var world := _make_world(7301, Rect2(-256.0, -256.0, 1024.0, 512.0))
	_add_building_fixture(world, &"authored")
	FoundationFacadeGenerator.generate(world)
	var facade := world.get_facades()[0]
	facade.authorship_state = FoundationSpatialRecord.AuthorshipState.LOCKED
	var locked_snapshot := JSON.stringify(facade.to_dict())
	FoundationFacadeGenerator.generate(world)
	_check(world.get_record(facade.stable_id) == facade and JSON.stringify(facade.to_dict()) == locked_snapshot, "locked facade survives regeneration as the same object")
	facade.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	facade.set_segment(facade.start + Vector2(420.0, 0.0), facade.end + Vector2(420.0, 0.0))
	FoundationFacadeGenerator.generate(world)
	_check(world.get_record(facade.stable_id) == facade and facade.owning_chunks.has(Vector2i(3, 0)), "overridden facade survives and refreshes authored spatial ownership")
	var generated_repair: StringName
	for candidate in world.get_facades():
		if candidate.parent_id == facade.parent_id and candidate.source_segment_index == facade.source_segment_index and candidate.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			generated_repair = candidate.stable_id
	FoundationFacadeGenerator.generate(world)
	_check(not String(generated_repair).is_empty() and world.get_record(generated_repair) is FoundationFacadeRecord, "authored facade collision receives the same deterministic repair identity on regeneration")
	var restored := FoundationWorldData.from_dict(world.to_dict())
	_check(_facade_snapshot(restored) == _facade_snapshot(world), "typed facade grammar, modules, lineage, state, and ownership serialize round-trip")
	var typed := true
	for restored_facade in restored.get_facades():
		typed = typed and restored_facade is FoundationFacadeRecord
		for module in restored_facade.modules:
			typed = typed and module is FoundationFacadeModule
	_check(typed, "world manifest restores typed Node-free facade and module data")
	var restored_profile := FoundationFacadeGenerationProfile.from_dict(restored.get_layer(FoundationWorldData.FACADE_LAYER).metadata["profile"])
	_check(restored_profile.to_dict() == FoundationFacadeGenerationProfile.new().to_dict(), "facade grammar profile has a versioned round-trip seam")


func _test_validation_and_non_mutation() -> void:
	var world := _make_world(7401)
	_add_building_fixture(world, &"immutable")
	var before := _input_snapshot(world)
	FoundationFacadeGenerator.generate(world)
	_check(_input_snapshot(world) == before, "Phase 7 leaves authoritative building and parcel inputs unchanged")
	var facade_before := _facade_snapshot(world)
	FoundationFacadeValidator.validate(world, null, false)
	_check(_facade_snapshot(world) == facade_before, "read-only facade validation does not mutate records")
	var facade := world.get_facades()[0]
	facade.modules.remove_at(facade.modules.size() - 1)
	var issues := FoundationFacadeValidator.validate(world, null, true)
	var found_incomplete := false
	for issue in issues:
		found_incomplete = found_incomplete or issue.kind == &"incomplete_module_grid"
	_check(found_incomplete and facade.validation_state == FoundationFacadeRecord.INVALID, "validation reports incomplete modular grids and marks generated facade data invalid")


func _test_debug_contract(world: FoundationWorldData) -> void:
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"facades")
	var provider := registry.get_provider(&"facades")
	var before := _facade_snapshot(world)
	var builder := registry.build(world)
	_check(builder.line_purposes.has(&"facade_primary") and builder.line_purposes.has(&"facade_grid"), "facade debug provider emits batched role outlines and modular grids")
	_check(builder.line_purposes.has(&"facade_window") and builder.line_purposes.has(&"facade_entrance"), "facade debug provider exposes window and entrance modules")
	_check(not builder.labels.is_empty(), "facade debug labels expose stable identity, role, bay count, and glazing")
	_check(_facade_snapshot(world) == before, "facade debug provider does not mutate authoritative data")
	var invocation_count := provider.invocation_count
	registry.set_layer_enabled(&"facades", false)
	var disabled := registry.build(world)
	_check(disabled.get_primitive_count() == 0 and provider.invocation_count == invocation_count, "disabled facade debug performs no provider work")


func _test_bounded_work() -> void:
	var world := _make_world(7501, Rect2(0.0, 0.0, 3000.0, 3000.0))
	for index in range(36):
		var column := index % 6
		var row := index / 6
		_add_building_fixture(world, StringName("large_%02d" % index), Vector2(column * 180.0, row * 180.0))
	var profile := FoundationFacadeGenerationProfile.new()
	profile.maximum_generation_operations = 200000
	var result := FoundationFacadeGenerator.generate(world, profile)
	_check(result.success and result.generation_operation_count < profile.maximum_generation_operations, "larger building fixture stays within the explicit facade operation cap")
	_check(result.generated_facade_count == 144 and result.generated_module_count > result.generated_facade_count, "larger fixture generates compact facade records and module arrays without scene nodes")


func _test_demo_contract() -> void:
	var scene := load("res://demo/spatial_model_demo.tscn") as PackedScene
	var demo := scene.instantiate()
	root.add_child(demo)
	var world_node := demo.get_node("FoundationWorld") as FoundationWorld
	var debug_view := demo.get_node("FoundationWorld/FoundationDebugView") as FoundationDebugView
	_check(not world_node.world_data.get_facades().is_empty(), "Phase 7 demo generates modular facade records")
	var has_primary_entrance := false
	for facade in world_node.world_data.get_facades():
		if facade.facade_role == FoundationFacadeRecord.ROLE_PRIMARY and not String(facade.entrance_module_id).is_empty():
			has_primary_entrance = true
	_check(has_primary_entrance, "Phase 7 demo exposes primary facade entrance grammar")
	_check(debug_view.show_facades and demo.get_node("%FacadeToggle").button_pressed, "Phase 7 demo exposes the facade grammar overlay")
	var before := _facade_snapshot(world_node.world_data)
	demo.get_node("%StageOptions").select(5)
	demo.call("_regenerate_selected_stage")
	_check(_facade_snapshot(world_node.world_data) == before, "Phase 7 demo same-seed facade regeneration is stable")
	demo.free()


func _test_scope_exclusions(world: FoundationWorldData) -> void:
	var facade := world.get_facades()[0]
	_check(ClassDB.is_parent_class(facade.get_class(), "RefCounted") and not ClassDB.is_parent_class(facade.get_class(), "Node"), "facade contract remains renderer-independent Node-free data")
	var forbidden_methods := [
		&"assign_district", &"assign_zoning", &"assign_use", &"create_interior",
		&"instantiate_prefab", &"build_mesh", &"create_collision", &"create_material",
		&"place_parking", &"create_address", &"create_navigation_mesh", &"grade_terrain",
		&"create_building_pad", &"place_vegetation",
	]
	var forbidden := false
	for method_name in forbidden_methods:
		forbidden = forbidden or facade.has_method(method_name) or world.has_method(method_name)
	_check(not forbidden, "Phase 7 introduces no districts, uses, interiors, prefabs, production mesh/material/collision, parking, addresses, navigation, grading, or vegetation API")


func _make_world(seed: int, bounds := Rect2(-256.0, -256.0, 512.0, 512.0)) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 7
	metadata.content_pack_version = &"phase-7-tests"
	metadata.world_bounds = bounds
	var world := FoundationWorldData.new(metadata, FoundationCoordinateSystem.new())
	world.initialize_default_layers()
	world.initialize_partitions()
	return world


func _add_building_fixture(
	world: FoundationWorldData,
	key: StringName,
	origin := Vector2.ZERO,
	size := Vector2(72.0, 48.0)
) -> FoundationBuildingRecord:
	var parcel_id := StringName("p7_parcel_%s" % key)
	var block_id := StringName("p7_block_%s" % key)
	var parcel_boundary := PackedVector2Array([
		origin - size * 0.5,
		origin + Vector2(size.x * 0.5, -size.y * 0.5),
		origin + size * 0.5,
		origin + Vector2(-size.x * 0.5, size.y * 0.5),
	])
	var frontage: Array[FoundationParcelFrontageReference] = [FoundationParcelFrontageReference.new(
		0, 0, StringName("p7_edge_%s" % key), StringName("p7_logical_%s" % key),
		0.0, 1.0, size.x, FoundationParcelFrontageReference.CLASS_PRIMARY
	)]
	var parcel := FoundationParcelRecord.new(parcel_id, block_id, parcel_boundary, frontage)
	parcel.primary_frontage_index = 0
	world.register_record(parcel)
	var inset := Vector2(8.0, 8.0)
	var footprint := PackedVector2Array([
		parcel_boundary[0] + inset,
		parcel_boundary[1] + Vector2(-inset.x, inset.y),
		parcel_boundary[2] - inset,
		parcel_boundary[3] + Vector2(inset.x, -inset.y),
	])
	var building := FoundationBuildingRecord.new(StringName("p7_building_%s" % key), parcel_id, block_id, footprint)
	building.primary_frontage_segment_index = 0
	building.primary_road_edge_id = frontage[0].road_edge_id
	building.primary_logical_road_id = frontage[0].logical_road_id
	building.frontage_direction = Vector2(0.0, -1.0)
	building.base_elevation = 0.0
	building.floor_count = 3
	building.floor_height = 3.2
	building.refresh_metrics(parcel.area)
	building.refresh_massing()
	building.source_pass = &"phase_7_test_fixture"
	world.register_record(building)
	return building


func _facade_snapshot(world: FoundationWorldData) -> String:
	var data: Array[Dictionary] = []
	for facade in world.get_facades():
		data.append(facade.to_dict())
	return JSON.stringify(data)


func _module_kind_snapshot(world: FoundationWorldData) -> String:
	var values := PackedStringArray()
	for facade in world.get_facades():
		for module in facade.modules:
			values.append("%d:%d:%s" % [module.floor_index, module.bay_index, module.kind])
	return "|".join(values)


func _input_snapshot(world: FoundationWorldData) -> String:
	var values: Array[Dictionary] = []
	for parcel in world.get_parcels():
		values.append(parcel.to_dict())
	for building in world.get_buildings():
		values.append(building.to_dict())
	return JSON.stringify(values)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
