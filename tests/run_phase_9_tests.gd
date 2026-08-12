extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline := _test_deterministic_plan_and_apply()
	_test_bridge_and_protection_contract(baseline)
	_test_bridge_approach_and_bounds_diagnostics()
	_test_serialization_validation_and_revert()
	_test_stale_and_corrupt_plan_rejection()
	_test_candidate_cap()
	_test_debug_editor_demo_contract()
	_test_scope_exclusions()
	if _failures.is_empty():
		print("Foundation Phase 9 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 9 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_deterministic_plan_and_apply() -> Dictionary:
	var first := _make_fixture(9101)
	var second := _make_fixture(9101)
	var world_before := _upstream_snapshot(first.world)
	var terrain_before := _terrain_snapshot(first.terrain)
	var first_result := FoundationTerrainGrader.create_plan(first.world, first.terrain)
	var second_result := FoundationTerrainGrader.create_plan(second.world, second.terrain)
	_check(first_result.success and second_result.success, "terrain grading plans succeed")
	_check(JSON.stringify(first_result.plan.to_dict()) == JSON.stringify(second_result.plan.to_dict()), "same inputs reproduce byte-identical grading plans")
	_check(_terrain_snapshot(first.terrain) == terrain_before, "grading planning performs zero terrain mutation")
	_check(_upstream_snapshot(first.world) == world_before, "grading planning performs zero upstream world-record mutation")
	_check(not first_result.plan.edits.is_empty() and first_result.plan.candidate_vertex_checks < first_result.plan.profile.maximum_candidate_vertices, "bounded raster planning resolves terrain edits within its explicit work cap")
	var apply_first := FoundationTerrainGrader.apply_plan(first.world, first.terrain, first_result.plan)
	var apply_second := FoundationTerrainGrader.apply_plan(second.world, second.terrain, second_result.plan)
	_check(apply_first.success and apply_first.applied and apply_first.changed_vertex_count > 0, "valid grading plan applies explicitly")
	_check(_terrain_snapshot(first.terrain) == _terrain_snapshot(second.terrain), "same plan produces byte-identical graded terrain")
	var sources: Dictionary = {}
	var provenance_only := false
	for edit in first_result.plan.edits:
		sources[edit.target_source] = true
		provenance_only = provenance_only or (is_equal_approx(edit.target_height, edit.original_height) and edit.target_source != edit.original_source)
	_check(sources.has(FoundationTerrainData.ModificationSource.BUILDING_PAD) and (sources.has(FoundationTerrainData.ModificationSource.ROAD_CUT) or sources.has(FoundationTerrainData.ModificationSource.ROAD_FILL)) and sources.has(FoundationTerrainData.ModificationSource.BRIDGE_APPROACH), "applied edits preserve road, pad, and bridge-approach provenance")
	_check(provenance_only, "already-level graded vertices still receive reversible semantic provenance")
	var boundary_dirtied: bool = first.terrain.get_dirty_chunks().has(Vector2i(0, 0)) and first.terrain.get_dirty_chunks().has(Vector2i(0, 1))
	_check(boundary_dirtied, "grading an exact terrain chunk boundary dirties both owning chunks")
	var pad := _operation_of_kind(first_result.plan, FoundationTerrainGradingOperation.KIND_BUILDING_PAD)
	var pad_heights: Dictionary = {}
	for edit in first_result.plan.edits:
		if edit.operation_id == pad.stable_id and is_equal_approx(edit.blend_weight, 1.0):
			pad_heights[edit.target_height] = true
	_check(pad != null and pad.metadata.get("target_source", "") == "primary_road" and pad_heights.size() == 1, "building pad interior is flat and aligned to its primary road elevation")
	return first


func _test_bridge_and_protection_contract(fixture: Dictionary) -> void:
	var plan: FoundationTerrainGradingPlan = fixture.world.terrain_grading_plan
	var terrain: FoundationTerrainData = fixture.terrain
	var span := _operation_of_kind(plan, FoundationTerrainGradingOperation.KIND_BRIDGE_SPAN)
	var approach := _operation_of_kind(plan, FoundationTerrainGradingOperation.KIND_BRIDGE_APPROACH)
	_check(span != null and span.edit_keys.is_empty() and bool(span.metadata.get("preserves_underlying_terrain", false)), "bridge span records a deck contract without terrain edits beneath it")
	_check(approach != null and not approach.edit_keys.is_empty(), "bridge intent produces deterministic graded approaches")
	var water_unchanged := true
	for cell_x in range(27, 33):
		for vertex_y in range(15, 18):
			var vertex := Vector2i(cell_x, vertex_y)
			if not is_equal_approx(terrain.get_vertex_height(vertex), fixture.original_heights[terrain.vertex_index(vertex)]):
				water_unchanged = false
	_check(water_unchanged and plan.skipped_water_count > 0, "water terrain beneath and beside bridge spans remains unchanged")
	var protected_unchanged := true
	for vertex_y in range(15, 18):
		var vertex := Vector2i(9, vertex_y)
		protected_unchanged = protected_unchanged and is_equal_approx(terrain.get_vertex_height(vertex), fixture.original_heights[terrain.vertex_index(vertex)])
	_check(protected_unchanged and plan.skipped_protected_count > 0, "protected terrain is skipped by default policy")
	var permissive := _make_fixture(9151)
	var permissive_profile := FoundationTerrainGradingProfile.new()
	permissive_profile.allow_water_grading = true
	var permissive_result := FoundationTerrainGrader.create_plan(permissive.world, permissive.terrain, Vector2i.ZERO, permissive_profile)
	var span_preserved := permissive_result.success
	for edit in permissive_result.plan.edits:
		span_preserved = span_preserved and not FoundationTerrainGrader.edit_is_under_bridge_span(permissive.world, permissive_result.plan, edit)
	_check(span_preserved, "bridge-span terrain remains excluded even when general water grading is explicitly allowed")


func _test_bridge_approach_and_bounds_diagnostics() -> void:
	var long_approach := _make_fixture(9171)
	var road := long_approach.world.get_record(&"p9_primary_road") as FoundationRoadEdge
	long_approach.world.unregister_record(road.stable_id)
	road.route_points[1].x = 12.0
	road.refresh_route_metrics()
	long_approach.world.register_record(road)
	var long_result := FoundationTerrainGrader.create_plan(long_approach.world, long_approach.terrain)
	var approach := _operation_of_kind(long_result.plan, FoundationTerrainGradingOperation.KIND_BRIDGE_APPROACH)
	_check(long_result.success and approach != null and approach.metadata.get("segment_indices", []).has(1), "a long segment adjacent to a bridge span is still classified as a deterministic approach")

	var outside := _make_fixture(9181)
	var outside_building := FoundationBuildingRecord.new(
		&"p9_outside_building", &"outside_parcel", &"outside_block",
		PackedVector2Array([Vector2(400.0, 400.0), Vector2(420.0, 400.0), Vector2(420.0, 420.0), Vector2(400.0, 420.0)])
	)
	outside.world.register_record(outside_building)
	var outside_result := FoundationTerrainGrader.create_plan(outside.world, outside.terrain)
	var reported := false
	for diagnostic in outside_result.plan.diagnostics:
		reported = reported or diagnostic.get("kind", "") == "building_outside_terrain"
	_check(outside_result.success and reported, "out-of-terrain building pads are skipped with a deterministic diagnostic")

	var constrained := _make_fixture(9191)
	var constrained_profile := FoundationTerrainGradingProfile.new()
	constrained_profile.maximum_cut_depth = 0.6
	constrained_profile.maximum_fill_height = 0.6
	var constrained_result := FoundationTerrainGrader.create_plan(constrained.world, constrained.terrain, Vector2i.ZERO, constrained_profile)
	_check(constrained_result.success and FoundationTerrainGradingValidator.validate_plan(constrained.world, constrained.terrain, constrained_result.plan).is_empty(), "height-step quantization never pushes resolved edits past fractional cut/fill limits")


func _test_serialization_validation_and_revert() -> void:
	var fixture := _make_fixture(9201)
	var result := FoundationTerrainGrader.create_plan(fixture.world, fixture.terrain)
	var planned_round_trip := FoundationTerrainGradingPlan.from_dict(result.plan.to_dict())
	_check(JSON.stringify(planned_round_trip.to_dict()) == JSON.stringify(result.plan.to_dict()), "profile, plan, operations, edits, and diagnostics serialize round-trip")
	var apply_result := FoundationTerrainGrader.apply_plan(fixture.world, fixture.terrain, result.plan)
	var terrain_round_trip := FoundationTerrainData.from_dict(fixture.terrain.to_dict())
	_check(_terrain_snapshot(terrain_round_trip) == _terrain_snapshot(fixture.terrain), "terrain arrays, provenance, revision, diagonals, and dirty chunks serialize round-trip")
	var world_round_trip := FoundationWorldData.from_dict(fixture.world.to_dict())
	_check(world_round_trip.terrain_grading_plan is FoundationTerrainGradingPlan and JSON.stringify(world_round_trip.terrain_grading_plan.to_dict()) == JSON.stringify(result.plan.to_dict()), "world manifest restores typed grading plan data")
	var before_validate := _terrain_snapshot(fixture.terrain)
	var issues := FoundationTerrainGradingValidator.validate_plan(fixture.world, fixture.terrain, result.plan, true)
	_check(issues.is_empty() and _terrain_snapshot(fixture.terrain) == before_validate, "applied-plan validation recomputes contracts without mutation")
	var revert_result := FoundationTerrainGrader.revert_plan(fixture.world, fixture.terrain, result.plan)
	_check(apply_result.success and revert_result.success and revert_result.reverted and fixture.terrain.vertex_heights == fixture.original_heights, "safe revert restores original terrain heights after an applied plan")


func _test_stale_and_corrupt_plan_rejection() -> void:
	var stale := _make_fixture(9301)
	var stale_result := FoundationTerrainGrader.create_plan(stale.world, stale.terrain)
	var untouched := _terrain_snapshot(stale.terrain)
	stale.terrain.set_vertex_height(Vector2i.ZERO, 99.0)
	var after_external_edit := _terrain_snapshot(stale.terrain)
	var rejected := FoundationTerrainGrader.apply_plan(stale.world, stale.terrain, stale_result.plan)
	_check(not rejected.success and _has_issue(rejected.validation_issues, &"stale_terrain_revision") and _terrain_snapshot(stale.terrain) == after_external_edit and after_external_edit != untouched, "stale plans are rejected atomically before grading writes")
	var stale_source := _make_fixture(9321)
	var stale_source_result := FoundationTerrainGrader.create_plan(stale_source.world, stale_source.terrain)
	var source_terrain_before := _terrain_snapshot(stale_source.terrain)
	var stale_road := stale_source.world.get_record(&"p9_primary_road") as FoundationRoadEdge
	stale_road.route_points[0].x += 4.0
	stale_road.refresh_route_metrics()
	var source_rejected := FoundationTerrainGrader.apply_plan(stale_source.world, stale_source.terrain, stale_source_result.plan)
	_check(not source_rejected.success and _has_issue(source_rejected.validation_issues, &"source_record_hash_mismatch") and _terrain_snapshot(stale_source.terrain) == source_terrain_before, "plans with changed upstream road/building sources are rejected atomically")

	var corrupt := _make_fixture(9351)
	var corrupt_result := FoundationTerrainGrader.create_plan(corrupt.world, corrupt.terrain)
	var duplicate := FoundationTerrainGradingEdit.from_dict(corrupt_result.plan.edits[0].to_dict())
	corrupt_result.plan.edits.append(duplicate)
	corrupt_result.plan.operations[0].source_record_id = &"missing_source"
	corrupt_result.plan.operations[0].world_bounds = Rect2(10000.0, 10000.0, 1.0, 1.0)
	corrupt_result.plan.operations[0].target_elevation_min -= 3.0
	corrupt_result.plan.edits[0].target_height += 100.0
	var validation := FoundationTerrainGradingValidator.validate_plan(corrupt.world, corrupt.terrain, corrupt_result.plan, false)
	_check(_has_issue(validation, &"duplicate_vertex_edit") and (_has_issue(validation, &"invalid_road_source") or _has_issue(validation, &"invalid_building_source")) and (_has_issue(validation, &"fill_limit_exceeded") or _has_issue(validation, &"cut_limit_exceeded")) and _has_issue(validation, &"edit_outside_operation_bounds") and _has_issue(validation, &"operation_elevation_accounting_mismatch"), "validation rejects duplicate edits, missing lineage, corrupt bounds/elevation accounting, and cut/fill violations")

	var applied := _make_fixture(9371)
	var applied_result := FoundationTerrainGrader.create_plan(applied.world, applied.terrain)
	FoundationTerrainGrader.apply_plan(applied.world, applied.terrain, applied_result.plan)
	applied.terrain.set_vertex_height(applied_result.plan.edits[0].grid_vertex, applied_result.plan.edits[0].target_height + 4.0)
	var terrain_after_tamper := _terrain_snapshot(applied.terrain)
	var revert_rejected := FoundationTerrainGrader.revert_plan(applied.world, applied.terrain, applied_result.plan)
	_check(not revert_rejected.success and _has_issue(revert_rejected.validation_issues, &"unsafe_revert_mismatch") and _terrain_snapshot(applied.terrain) == terrain_after_tamper, "unsafe revert is refused atomically when applied terrain changed")


func _test_candidate_cap() -> void:
	var fixture := _make_fixture(9401)
	var profile := FoundationTerrainGradingProfile.new()
	profile.maximum_candidate_vertices = 1
	var result := FoundationTerrainGrader.create_plan(fixture.world, fixture.terrain, Vector2i.ZERO, profile)
	var reported := false
	for diagnostic in result.plan.diagnostics:
		reported = reported or diagnostic.get("kind", "") == "candidate_vertex_cap"
	_check(not result.success and reported, "terrain grading stops with a deterministic candidate-work cap diagnostic")


func _test_debug_editor_demo_contract() -> void:
	var fixture := _make_fixture(9501)
	var result := FoundationTerrainGrader.create_plan(fixture.world, fixture.terrain)
	FoundationTerrainGrader.apply_plan(fixture.world, fixture.terrain, result.plan)
	var registry := FoundationDebugLayerRegistry.new()
	registry.register_phase_1_defaults()
	for provider_id in registry.get_provider_ids():
		registry.set_layer_enabled(provider_id, provider_id == &"terrain_grading")
	var provider := registry.get_provider(&"terrain_grading")
	var builder := registry.build(fixture.world)
	_check(builder.line_purposes.has(&"grading_road") and builder.line_purposes.has(&"grading_pad") and builder.line_purposes.has(&"grading_bridge") and not builder.labels.is_empty(), "grading debug exposes roads, pads, bridges, edits, and labels")
	var invocation_count := provider.invocation_count
	registry.set_layer_enabled(&"terrain_grading", false)
	var disabled := registry.build(fixture.world)
	_check(disabled.get_primitive_count() == 0 and provider.invocation_count == invocation_count, "disabled grading debug performs zero provider work")
	var editor_source := FileAccess.get_file_as_string("res://addons/foundation/editor/debug_editor_dock.gd")
	var demo_source := FileAccess.get_file_as_string("res://demo/spatial_model_demo.gd")
	var demo_scene := FileAccess.get_file_as_string("res://demo/spatial_model_demo.tscn")
	_check(editor_source.contains("Plan / Apply Terrain Grading") and editor_source.contains("Revert Terrain Grading") and editor_source.contains("_revert_grading_before_upstream_change"), "editor dock exposes explicit grading controls and safely reverts before source regeneration")
	_check(demo_source.contains("FoundationTerrainGrader") and demo_scene.contains("GradingToggle") and demo_scene.contains("Phase 9"), "runtime demo exposes Phase 9 grading generation and visualization")


func _test_scope_exclusions() -> void:
	var plan := FoundationTerrainGradingPlan.new()
	_check(ClassDB.is_parent_class(plan.get_class(), "RefCounted") and not ClassDB.is_parent_class(plan.get_class(), "Node"), "terrain-grading authority remains renderer-independent Node-free data")
	var forbidden := [&"build_road_mesh", &"build_bridge_mesh", &"create_collision", &"place_retaining_wall", &"spawn_traffic", &"create_navigation_mesh", &"place_parking"]
	var found := false
	for method_name in forbidden:
		found = found or plan.has_method(method_name) or FoundationTerrainGrader.new().has_method(method_name)
	_check(not found, "Phase 9 introduces no production geometry, collision, retaining-wall placement, traffic, navigation, or parking API")


func _make_fixture(seed: int) -> Dictionary:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 9
	metadata.content_pack_version = &"phase-9-tests"
	metadata.world_bounds = Rect2(0.0, 0.0, 256.0, 128.0)
	var coordinates := FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(16, 16), Vector2i(2, 2))
	var world := FoundationWorldData.new(metadata, coordinates)
	world.initialize_default_layers()
	world.initialize_partitions()
	var terrain := FoundationTerrainData.new(seed, Vector2i(64, 32), 4.0, 1.0, Vector2i(16, 16), 9, &"phase-9-tests")
	for vertex_y in range(terrain.grid_cells.y + 1):
		for vertex_x in range(terrain.grid_cells.x + 1):
			var height := float((vertex_x + vertex_y * 2) % 9)
			terrain.set_vertex_height(Vector2i(vertex_x, vertex_y), height, FoundationTerrainData.ModificationSource.NATURAL, false)
	for cell_x in range(27, 33):
		for cell_y in range(15, 17):
			terrain.set_cell_flags(Vector2i(cell_x, cell_y), FoundationTerrainData.CellFlag.WATER, false)
	for cell_y in range(15, 17):
		terrain.set_cell_flags(Vector2i(20, cell_y), FoundationTerrainData.CellFlag.WATER, false)
	for cell_y in range(15, 17):
		terrain.set_cell_flags(Vector2i(8, cell_y), FoundationTerrainData.CellFlag.PROTECTED, false)
	terrain.clear_dirty_chunks()
	var points := PackedVector3Array([
		Vector3(8.0, 4.0, 64.0), Vector3(80.0, 4.0, 64.0), Vector3(108.0, 4.0, 64.0),
		Vector3(132.0, 4.0, 64.0), Vector3(160.0, 4.0, 64.0), Vector3(240.0, 4.0, 64.0),
	])
	var road := FoundationRoadEdge.new(&"p9_primary_road", &"", &"", points, FoundationRoadEdge.CLASS_ARTERIAL)
	for index in range(points.size()):
		var sample := FoundationRoadElevationSample.new(points[index], 0.0 if index in [2, 3] else points[index].y, 4.0)
		sample.water_crossing = index in [2, 3]
		sample.bridge_candidate = sample.water_crossing
		road.desired_elevation_samples.append(sample)
	road.grading_requirements = {"bridge_candidate": true, "water_crossing": true}
	road.source_pass = &"phase_9_fixture"
	world.register_record(road)
	var footprint := PackedVector2Array([Vector2(40.0, 76.0), Vector2(72.0, 76.0), Vector2(72.0, 100.0), Vector2(40.0, 100.0)])
	var building := FoundationBuildingRecord.new(&"p9_building", &"p9_parcel", &"p9_block", footprint)
	building.primary_road_edge_id = road.stable_id
	building.source_pass = &"phase_9_fixture"
	world.register_record(building)
	return {
		"world": world,
		"terrain": terrain,
		"original_heights": terrain.vertex_heights.duplicate(),
	}


func _operation_of_kind(plan: FoundationTerrainGradingPlan, kind: StringName) -> FoundationTerrainGradingOperation:
	for operation in plan.operations:
		if operation.operation_kind == kind:
			return operation
	return null


func _terrain_snapshot(terrain: FoundationTerrainData) -> String:
	return JSON.stringify(terrain.to_dict())


func _upstream_snapshot(world: FoundationWorldData) -> String:
	var records: Array[Dictionary] = []
	for record in world.spatial_index.get_all_records():
		records.append(record.to_dict())
	return JSON.stringify(records)


func _has_issue(issues: Array[FoundationTerrainGradingValidationIssue], kind: StringName) -> bool:
	for issue in issues:
		if issue.kind == kind:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
