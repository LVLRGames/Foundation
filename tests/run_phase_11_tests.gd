extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_codec_and_policy()
	_test_lock_override_revision_and_impact()
	_test_create_delete_revert()
	_test_reapply_conflicts_and_atomicity()
	_test_history_and_round_trip()
	_test_signed_reindex_queries_validation_and_debug()
	_test_editor_demo_and_scope()
	if _failures.is_empty():
		print("Foundation Phase 11 assertions: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("Foundation Phase 11 assertions: %d failure(s)" % _failures.size())
		quit(1)


func _test_codec_and_policy() -> void:
	var first := {"z": [3, 2, 1], "a": {"beta": 2, "alpha": 1}}
	var second := {"a": {"alpha": 1, "beta": 2}, "z": [3, 2, 1]}
	_check(
		FoundationSpatialRecordCodec.canonical_json(first) == FoundationSpatialRecordCodec.canonical_json(second)
		and FoundationSpatialRecordCodec.fingerprint(first) == FoundationSpatialRecordCodec.fingerprint(second),
		"canonical JSON and SHA-256 fingerprints ignore Dictionary insertion order"
	)
	var changed := FoundationSpatialRecordCodec.changed_field_paths(
		{"a": 1, "nested": {"x": 2, "y": 3}},
		{"a": 2, "nested": {"x": 2, "y": 4}, "z": true}
	)
	_check(changed == PackedStringArray(["a", "nested.y", "z"]), "changed-field paths are complete and stable-sorted")
	var policy := FoundationAuthoringPolicy.new()
	var restored := FoundationAuthoringPolicy.from_dict(policy.to_dict())
	_check(restored.validation_errors().is_empty() and restored.to_dict() == policy.to_dict(), "authoring policy is explicit, valid, and serializable")
	_check("parent_id" in policy.protected_fields, "authoring policy protects parent lineage with record identity")
	_check(
		FoundationWorldData.TERRAIN_LAYER not in policy.supported_layers()
		and FoundationWorldData.OVERRIDE_LAYER not in policy.supported_layers(),
		"authoring policy excludes terrain and self-authoring of the override layer"
	)
	var generic := FoundationSpatialRecord.new(&"external_record", &"external", &"external_layer", Rect2(-4.0, -4.0, 8.0, 8.0)).to_dict()
	generic["record_kind"] = "content_pack_record"
	_check(FoundationSpatialRecordCodec.record_from_dict(generic).stable_id == &"external_record", "typed codec preserves the prior generic-record fallback for external content packs")


func _test_lock_override_revision_and_impact() -> void:
	var world := _make_fixture(11101)
	var session := FoundationAuthoringSession.new()
	var anchor := world.get_record(&"p11_anchor") as FoundationCityAnchor
	var locked := session.lock_record(world, anchor.stable_id)
	_check(locked.success and world.get_record(anchor.stable_id).authorship_state == FoundationSpatialRecord.AuthorshipState.LOCKED, "lock operation replaces the target with durable LOCKED state")
	var unlocked := session.unlock_record(world, anchor.stable_id)
	_check(unlocked.success and world.get_record(anchor.stable_id).authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED, "unlock operation restores generator-owned state")

	var moved := session.translate_record(world, anchor.stable_id, Vector2(18.0, -12.0), "Move city anchor")
	var override_record := world.get_override_for_target(anchor.stable_id)
	var base_fingerprint := override_record.base_fingerprint
	_check(
		moved.success and override_record != null
		and override_record.operation_kind == FoundationOverrideRecord.OP_MODIFY
		and override_record.revision == 1
		and (world.get_record(anchor.stable_id) as FoundationCityAnchor).world_position == Vector3(-82.0, 0.0, -32.0),
		"translate creates and applies a typed modify override"
	)
	var revision := session.apply_property_patch(world, anchor.stable_id, {"priority_weight": 3.5}, "Raise priority")
	override_record = world.get_override_for_target(anchor.stable_id)
	_check(
		revision.success and override_record.revision == 2 and override_record.base_fingerprint == base_fingerprint
		and is_equal_approx((world.get_record(anchor.stable_id) as FoundationCityAnchor).priority_weight, 3.5),
		"same-target edits advance one override revision while retaining the first base snapshot"
	)
	_check(
		moved.affected_layers[0] == FoundationWorldData.CITY_ANCHOR_LAYER
		and FoundationWorldData.ROAD_EDGE_LAYER in moved.affected_layers
		and FoundationWorldData.PUBLIC_FEATURE_LAYER in moved.affected_layers,
		"authoring reports affected/downstream layers without running generators"
	)
	var expected_id := FoundationSpatialId.make(
		world.metadata.seed, session.policy.authoring_version, world.metadata.content_pack_version,
		FoundationOverrideRecord.ENTITY_TYPE, anchor.stable_id, String(session.policy.policy_id)
	)
	_check(override_record.stable_id == expected_id and override_record.changed_fields.has("world_position.x"), "override identity and changed-field evidence are deterministic")


func _test_create_delete_revert() -> void:
	var world := _make_fixture(11201)
	var session := FoundationAuthoringSession.new()
	var source := world.get_record(&"p11_anchor") as FoundationCityAnchor
	var created_data := FoundationSpatialRecordCodec.translate_record_data(source.to_dict(), Vector2(220.0, 96.0))
	created_data["stable_id"] = "p11_authored_anchor"
	created_data["source_anchor_id"] = ""
	var created := session.create_authored_record(world, created_data, "Create authored anchor")
	var authored := world.get_record(&"p11_authored_anchor")
	var create_override := world.get_override_for_target(&"p11_authored_anchor")
	_check(
		created.success and authored is FoundationCityAnchor
		and authored.authorship_state == FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
		and create_override.operation_kind == FoundationOverrideRecord.OP_CREATE,
		"typed authored creation is registered with a durable create override"
	)
	var reverted_create := session.revert_override(world, &"p11_authored_anchor")
	_check(reverted_create.success and world.get_record(&"p11_authored_anchor") == null and world.get_override_for_target(&"p11_authored_anchor") == null, "reverting a create removes its authored target and override")
	created = session.create_authored_record(world, created_data, "Recreate authored anchor")
	var cancelled_create := session.delete_record(world, &"p11_authored_anchor", "Cancel authored anchor")
	_check(created.success and cancelled_create.success and world.get_record(&"p11_authored_anchor") == null and world.get_override_for_target(&"p11_authored_anchor") == null, "deleting an authored creation cancels it without leaving an invalid tombstone")
	session.undo(world)
	_check(world.get_record(&"p11_authored_anchor") is FoundationCityAnchor and world.get_override_for_target(&"p11_authored_anchor").operation_kind == FoundationOverrideRecord.OP_CREATE, "undo restores a cancelled authored creation and its create override")
	session.redo(world)

	var building := world.get_record(&"p11_building") as FoundationBuildingRecord
	var original := building.to_dict()
	var deleted := session.delete_record(world, building.stable_id, "Remove building")
	var tombstone := world.get_override_for_target(building.stable_id)
	_check(
		deleted.success and world.get_record(building.stable_id) == null
		and tombstone.operation_kind == FoundationOverrideRecord.OP_DELETE
		and tombstone.target_parent_id == &"p11_parcel"
		and tombstone.base_fingerprint == FoundationSpatialRecordCodec.fingerprint(original),
		"delete removes the live target and retains deterministic parent lineage and a base snapshot"
	)
	var reverted_delete := session.revert_override(world, building.stable_id)
	_check(
		reverted_delete.success and world.get_record(building.stable_id) is FoundationBuildingRecord
		and world.get_record(building.stable_id).to_dict() == original,
		"reverting a tombstone restores the exact typed base record"
	)


func _test_reapply_conflicts_and_atomicity() -> void:
	var world := _make_fixture(11301)
	var session := FoundationAuthoringSession.new()
	var target := world.get_record(&"p11_anchor")
	var applied := session.translate_record(world, target.stable_id, Vector2(12.0, 8.0))
	var override_record := world.get_override_for_target(target.stable_id)
	var authored_snapshot := override_record.authored_record_data.duplicate(true)
	var base := FoundationSpatialRecordCodec.record_from_dict(override_record.base_record_data)
	_register(world, base)
	var reapplied := session.reapply_all(world)
	_check(
		applied.success and reapplied.success and reapplied.applied_count == 1
		and world.get_record(target.stable_id).to_dict() == authored_snapshot,
		"stable-order reapply restores an authored snapshot after simulated regeneration"
	)

	base = FoundationSpatialRecordCodec.record_from_dict(override_record.base_record_data)
	(base as FoundationCityAnchor).priority_weight = 9.0
	_register(world, base)
	var drift_snapshot := base.to_dict()
	var conflict := session.reapply_all(world)
	_check(
		not conflict.success and conflict.conflicted_count == 1
		and world.get_record(target.stable_id).to_dict() == drift_snapshot
		and override_record.conflict_state == FoundationOverrideRecord.CONFLICT_BASE_DRIFT,
		"base drift is reported deterministically without mutating the live target"
	)
	var forced := session.reapply_all(world, true)
	_check(forced.success and forced.applied_count == 1 and world.get_record(target.stable_id).to_dict() == authored_snapshot, "explicit force policy resolves drift with the retained authored snapshot")

	var manifest_before := FoundationSpatialRecordCodec.canonical_json(world.to_dict())
	var history_before := FoundationSpatialRecordCodec.canonical_json(session.history.to_dict())
	var invalid := world.get_record(target.stable_id).to_dict()
	invalid["stable_id"] = "forbidden_identity_change"
	var rejected := session.apply_override(world, target.stable_id, invalid)
	_check(
		not rejected.success
		and FoundationSpatialRecordCodec.canonical_json(world.to_dict()) == manifest_before
		and FoundationSpatialRecordCodec.canonical_json(session.history.to_dict()) == history_before,
		"protected-field rejection is atomic across records, indexes, metadata, and history"
	)
	var building := world.get_record(&"p11_building")
	var changed_parent := building.to_dict()
	changed_parent["parent_id"] = "different_parent"
	_check(not session.apply_override(world, building.stable_id, changed_parent).success, "parent-lineage edits are rejected as protected identity changes")


func _test_history_and_round_trip() -> void:
	var world := _make_fixture(11401)
	var session := FoundationAuthoringSession.new()
	var target_id: StringName = &"p11_anchor"
	session.translate_record(world, target_id, Vector2(16.0, 0.0))
	var authored := world.get_record(target_id).to_dict()
	var undone := session.undo(world)
	_check(
		undone.success and world.get_override_for_target(target_id) == null
		and world.get_record(target_id).authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED
		and session.history.cursor == 0,
		"undo atomically restores the base target and removes the override"
	)
	var redone := session.redo(world)
	_check(redone.success and world.get_record(target_id).to_dict() == authored and session.history.cursor == 1, "redo restores the exact authored target and override")
	session.undo(world)
	session.lock_record(world, &"p11_building")
	_check(not session.history.can_redo() and session.history.commands.size() == 1, "a new edit after undo truncates the redo branch")

	var restored_history := FoundationAuthoringHistory.from_dict(session.history.to_dict())
	_check(restored_history.to_dict() == session.history.to_dict(), "authoring history round-trips independently of world data")
	var restored_world := FoundationWorldData.from_dict(world.to_dict())
	_check(
		restored_world.get_overrides().size() == world.get_overrides().size()
		and FoundationSpatialRecordCodec.canonical_json(restored_world.to_dict()) == FoundationSpatialRecordCodec.canonical_json(world.to_dict()),
		"world manifests restore typed Phase 11 overrides and canonical fingerprints"
	)

	var small_policy := FoundationAuthoringPolicy.new()
	small_policy.maximum_history_commands = 2
	var bounded_world := _make_fixture(11402)
	var bounded := FoundationAuthoringSession.new(small_policy)
	bounded.lock_record(bounded_world, &"p11_anchor")
	bounded.unlock_record(bounded_world, &"p11_anchor")
	bounded.lock_record(bounded_world, &"p11_anchor")
	_check(bounded.history.commands.size() == 2 and bounded.history.cursor == 2, "history enforces its explicit bounded command cap")
	var cap_policy := FoundationAuthoringPolicy.new()
	cap_policy.maximum_active_overrides = 1
	var capped_world := _make_fixture(11403)
	var capped := FoundationAuthoringSession.new(cap_policy)
	capped.translate_record(capped_world, &"p11_anchor", Vector2(4.0, 0.0))
	var cap_snapshot := FoundationSpatialRecordCodec.canonical_json(capped_world.to_dict())
	var cap_rejection := capped.delete_record(capped_world, &"p11_building")
	_check(not cap_rejection.success and FoundationSpatialRecordCodec.canonical_json(capped_world.to_dict()) == cap_snapshot, "new modify/delete instructions respect the active-override cap atomically")


func _test_signed_reindex_queries_validation_and_debug() -> void:
	var world := _make_fixture(11501)
	var session := FoundationAuthoringSession.new()
	var block := world.get_record(&"p11_block") as FoundationBlockRecord
	var old_chunks := block.owning_chunks.duplicate()
	var moved := session.translate_record(world, block.stable_id, Vector2(-180.0, -112.0), "Move block across signed chunks")
	var authored_block := world.get_record(block.stable_id)
	var override_record := world.get_override_for_target(block.stable_id)
	var stale_removed := true
	for chunk in old_chunks:
		if chunk not in authored_block.owning_chunks:
			stale_removed = stale_removed and block.stable_id not in _ids(world.get_records_in_chunk(chunk, FoundationWorldData.BLOCK_LAYER))
	var signed_and_multichunk := false
	for chunk in override_record.owning_chunks:
		signed_and_multichunk = signed_and_multichunk or chunk.x < 0 or chunk.y < 0
	signed_and_multichunk = signed_and_multichunk and override_record.owning_chunks.size() > 1
	_check(moved.success and stale_removed, "authored geometry removes stale chunk buckets and reindexes new bounds")
	_check(signed_and_multichunk, "override records support signed coordinates and multi-chunk ownership")
	_check(
		world.get_overrides_for_operation(FoundationOverrideRecord.OP_MODIFY).has(override_record)
		and world.get_overrides_for_layer(FoundationWorldData.BLOCK_LAYER).has(override_record)
		and world.get_override_for_target(block.stable_id) == override_record,
		"stable override queries resolve target, operation, and original layer"
	)
	var before := FoundationSpatialRecordCodec.canonical_json(world.to_dict())
	var issues := FoundationAuthoringValidator.validate(world, session.policy, session.history)
	var clean_errors := 0
	for issue in issues:
		if issue.severity == FoundationAuthoringValidationIssue.SEVERITY_ERROR:
			clean_errors += 1
	_check(clean_errors == 0 and FoundationSpatialRecordCodec.canonical_json(world.to_dict()) == before, "clean Phase 11 validation is read-only")
	override_record.base_fingerprint = "corrupt"
	issues = FoundationAuthoringValidator.validate(world, session.policy, session.history)
	var found_fingerprint := false
	for issue in issues:
		found_fingerprint = found_fingerprint or issue.kind == &"override_fingerprint_mismatch"
	_check(found_fingerprint, "validator reports deterministic override corruption")

	var registry := FoundationDebugLayerRegistry.new()
	var provider := FoundationOverrideDebugProvider.new()
	registry.register_provider(provider)
	var enabled := registry.build(world)
	var invocations := provider.invocation_count
	registry.set_layer_enabled(&"overrides", false)
	var disabled := registry.build(world)
	_check(enabled.get_primitive_count() > 0, "override debug provider batches authored bounds, labels, tombstones, and conflicts")
	_check(disabled.get_primitive_count() == 0 and provider.invocation_count == invocations, "disabled override debug performs zero provider work and allocates no primitives")


func _test_editor_demo_and_scope() -> void:
	var dock := FileAccess.get_file_as_string("res://addons/foundation/editor/authoring_editor_dock.gd")
	var plugin := FileAccess.get_file_as_string("res://addons/foundation/foundation_plugin.gd")
	var demo_source := FileAccess.get_file_as_string("res://demo/spatial_model_demo.gd")
	var demo_scene := FileAccess.get_file_as_string("res://demo/spatial_model_demo.tscn")
	_check(
		dock.contains("Apply / Update Override from JSON") and dock.contains("Delete Selected with Tombstone")
		and dock.contains("Undo Authoring Operation") and dock.contains("Reapply Active Overrides")
		and plugin.contains("AUTHORING_DOCK_SCRIPT"),
		"dedicated editor dock exposes complete explicit Phase 11 authoring operations"
	)
	_check(
		demo_source.contains("FoundationAuthoringSession") and demo_source.contains("reapply_all")
		and demo_scene.contains("Phase 11") and demo_scene.contains("NudgeOverrideButton")
		and demo_scene.contains("UndoAuthoringButton"),
		"runtime demo exposes durable overrides, reapply, revert, and undo/redo"
	)
	var world := _make_fixture(11601)
	var forbidden := [
		&"create_interior", &"create_room", &"create_portal", &"spawn_vehicle",
		&"simulate_traffic", &"create_navigation_mesh", &"sculpt_terrain",
		&"instantiate_prefab", &"place_vegetation", &"place_utility",
	]
	var found := false
	for method_name in forbidden:
		found = found or FoundationAuthoringSession.new().has_method(method_name)
		for record in world.spatial_index.get_all_records():
			found = found or record.has_method(method_name)
	_check(not found, "Phase 11 adds no interiors, traffic/navigation, terrain sculpting, prefab, vegetation, or utility API")


func _make_fixture(seed: int) -> FoundationWorldData:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = seed
	metadata.generator_version = 11
	metadata.content_pack_version = &"phase-11-tests"
	metadata.world_bounds = Rect2(-256.0, -192.0, 768.0, 512.0)
	var coordinates := FoundationCoordinateSystem.new(4.0, 1.0, Vector2i(16, 16), Vector2i(2, 2))
	var world := FoundationWorldData.new(metadata, coordinates)
	world.initialize_default_layers()
	world.initialize_partitions()
	var anchor := FoundationCityAnchor.new(
		&"p11_anchor", FoundationCityAnchor.CATEGORY_CITY_CENTER,
		Vector3(-100.0, 0.0, -20.0), 72.0, 1.0
	)
	anchor.source_pass = &"phase_11_fixture"
	_register(world, anchor)
	var boundary := PackedVector2Array([
		Vector2(-132.0, -92.0), Vector2(-12.0, -92.0),
		Vector2(-12.0, 28.0), Vector2(-132.0, 28.0),
	])
	var block := FoundationBlockRecord.new(&"p11_block", boundary)
	block.source_pass = &"phase_11_fixture"
	_register(world, block)
	var parcel := FoundationParcelRecord.new(&"p11_parcel", block.stable_id, boundary)
	parcel.source_pass = &"phase_11_fixture"
	_register(world, parcel)
	var footprint := PackedVector2Array([
		Vector2(-116.0, -76.0), Vector2(-62.0, -76.0),
		Vector2(-62.0, -30.0), Vector2(-116.0, -30.0),
	])
	var building := FoundationBuildingRecord.new(&"p11_building", parcel.stable_id, block.stable_id, footprint)
	building.floor_count = 3
	building.refresh_metrics(parcel.area)
	building.refresh_massing()
	building.source_pass = &"phase_11_fixture"
	_register(world, building)
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


func _ids(records: Array[FoundationSpatialRecord]) -> Array[StringName]:
	var result: Array[StringName] = []
	for record in records:
		result.append(record.stable_id)
	return result


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
