class_name FoundationAuthoringValidator
extends RefCounted

## Read-only deterministic validation for Phase 11 overrides and history.


static func validate(
	world: FoundationWorldData,
	policy: FoundationAuthoringPolicy = null,
	history: FoundationAuthoringHistory = null
) -> Array[FoundationAuthoringValidationIssue]:
	var issues: Array[FoundationAuthoringValidationIssue] = []
	if world == null:
		issues.append(FoundationAuthoringValidationIssue.new(
			&"missing_world", FoundationAuthoringValidationIssue.SEVERITY_ERROR, &"", &"",
			"Authoring validation requires FoundationWorldData."
		))
		return issues
	var active_policy := policy if policy != null else FoundationAuthoringPolicy.new()
	for error in active_policy.validation_errors():
		issues.append(FoundationAuthoringValidationIssue.new(
			&"invalid_authoring_policy", FoundationAuthoringValidationIssue.SEVERITY_ERROR,
			&"", &"", error
		))
	var targets: Dictionary = {}
	var overrides := world.get_overrides()
	if overrides.size() > active_policy.maximum_active_overrides:
		issues.append(FoundationAuthoringValidationIssue.new(
			&"override_cap", FoundationAuthoringValidationIssue.SEVERITY_ERROR, &"", &"",
			"Active overrides exceed the configured cap."
		))
	for override_record in overrides:
		_validate_override(world, override_record, active_policy, targets, issues)
	if history != null:
		_validate_history(history, active_policy, issues)
	issues.sort_custom(FoundationAuthoringValidationIssue.less)
	return issues


static func _validate_override(
	world: FoundationWorldData,
	record: FoundationOverrideRecord,
	policy: FoundationAuthoringPolicy,
	targets: Dictionary,
	issues: Array[FoundationAuthoringValidationIssue]
) -> void:
	if String(record.stable_id).is_empty() or String(record.target_record_id).is_empty():
		_add(issues, &"missing_override_identity", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override and target identities must be non-empty.")
	if record.stable_id == record.target_record_id:
		_add(issues, &"override_self_target", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "An override cannot target itself.")
	if targets.has(record.target_record_id):
		_add(issues, &"duplicate_override_target", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Only one active override may own a target.")
	targets[record.target_record_id] = record.stable_id
	if record.operation_kind not in FoundationOverrideRecord.builtin_operations():
		_add(issues, &"unsupported_override_operation", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override operation is unsupported.")
	if record.target_layer_type not in policy.supported_layers() or record.target_record_kind not in policy.supported_record_kinds():
		_add(issues, &"unsupported_override_target", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override target layer or record kind is unsupported.")
	if record.revision <= 0:
		_add(issues, &"invalid_override_revision", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override revision must be positive.")
	if record.authorship_state != FoundationSpatialRecord.AuthorshipState.OVERRIDDEN or record.source_pass != FoundationAuthoringSession.SOURCE_PASS or record.source_version != policy.authoring_version:
		_add(issues, &"override_source_mismatch", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override authorship/source contract is inconsistent.")
	var expected_id := FoundationSpatialId.make(
		world.metadata.seed, policy.authoring_version, world.metadata.content_pack_version,
		FoundationOverrideRecord.ENTITY_TYPE, record.target_record_id, String(policy.policy_id)
	)
	if record.stable_id != expected_id:
		_add(issues, &"override_identity_mismatch", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override stable ID does not match its target and policy.")
	_validate_snapshot_shape(world, record, issues)
	_validate_bounds_and_ownership(world, record, issues)
	_validate_live_state(world, record, issues)


static func _validate_snapshot_shape(
	world: FoundationWorldData,
	record: FoundationOverrideRecord,
	issues: Array[FoundationAuthoringValidationIssue]
) -> void:
	var expects_base := record.operation_kind in [FoundationOverrideRecord.OP_MODIFY, FoundationOverrideRecord.OP_DELETE]
	var expects_authored := record.operation_kind in [FoundationOverrideRecord.OP_MODIFY, FoundationOverrideRecord.OP_CREATE]
	if expects_base == record.base_record_data.is_empty():
		_add(issues, &"override_base_snapshot_shape", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override base snapshot does not match its operation.")
	if expects_authored == record.authored_record_data.is_empty():
		_add(issues, &"override_authored_snapshot_shape", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override authored snapshot does not match its operation.")
	for snapshot in [record.base_record_data, record.authored_record_data]:
		if snapshot.is_empty():
			continue
		if not FoundationSpatialRecordCodec.is_json_safe(snapshot):
			_add(issues, &"non_json_override_snapshot", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override snapshot contains non-JSON-safe data.")
			continue
		if StringName(snapshot.get("stable_id", "")) != record.target_record_id or StringName(snapshot.get("layer_type", "")) != record.target_layer_type or StringName(snapshot.get("entity_type", "")) != record.target_entity_type or StringName(snapshot.get("record_kind", "")) != record.target_record_kind:
			_add(issues, &"override_snapshot_identity", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override snapshot changes protected identity/layer fields.")
		var parent_id := StringName(snapshot.get("parent_id", ""))
		if parent_id != record.target_parent_id:
			_add(issues, &"override_parent_lineage_mismatch", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override snapshot parent differs from retained target lineage.")
		if parent_id in [record.stable_id, record.target_record_id]:
			_add(issues, &"override_snapshot_cycle", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override snapshots cannot use the target or override as their own parent.")
		elif not String(parent_id).is_empty() and world.get_record(parent_id) == null:
			_add(issues, &"missing_override_parent", FoundationAuthoringValidationIssue.SEVERITY_WARNING, record, "Override snapshot parent is not present in the world.")
	if record.operation_kind == FoundationOverrideRecord.OP_MODIFY and record.base_record_data.get("parent_id", "") != record.authored_record_data.get("parent_id", ""):
		_add(issues, &"override_parent_lineage_change", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Modify overrides cannot change parent lineage.")
	if expects_authored and int(record.authored_record_data.get("authorship_state", -1)) != FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
		_add(issues, &"authored_snapshot_state", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Authored snapshot must have OVERRIDDEN state.")
	var expected_base_fingerprint := FoundationSpatialRecordCodec.fingerprint(record.base_record_data) if expects_base else ""
	var expected_authored_fingerprint := FoundationSpatialRecordCodec.fingerprint(record.authored_record_data) if expects_authored else ""
	if record.base_fingerprint != expected_base_fingerprint or record.authored_fingerprint != expected_authored_fingerprint:
		_add(issues, &"override_fingerprint_mismatch", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Stored override fingerprints do not match canonical snapshots.")
	var expected_fields := FoundationSpatialRecordCodec.changed_field_paths(record.base_record_data, record.authored_record_data)
	if record.changed_fields != expected_fields:
		_add(issues, &"override_changed_fields_mismatch", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Stored changed-field paths are incomplete or unsorted.")


static func _validate_bounds_and_ownership(
	world: FoundationWorldData,
	record: FoundationOverrideRecord,
	issues: Array[FoundationAuthoringValidationIssue]
) -> void:
	if not is_finite(record.world_bounds.position.x) or not is_finite(record.world_bounds.position.y) or not is_finite(record.world_bounds.size.x) or not is_finite(record.world_bounds.size.y) or record.world_bounds.size.x < 0.0 or record.world_bounds.size.y < 0.0:
		_add(issues, &"invalid_override_bounds", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override bounds must be finite and non-negative.")
	var expected_chunks := world.coordinate_system.world_bounds_to_chunks(record.world_bounds)
	if expected_chunks != record.owning_chunks:
		_add(issues, &"override_chunk_ownership", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override chunk ownership is stale.")
	var region_set: Dictionary = {}
	for chunk in expected_chunks:
		region_set[world.coordinate_system.chunk_to_region(chunk)] = true
	var expected_regions: Array[Vector2i] = []
	for region: Vector2i in region_set:
		expected_regions.append(region)
	expected_regions.sort_custom(FoundationSpatialRecord._sort_vector2i)
	if expected_regions != record.owning_regions:
		_add(issues, &"override_region_ownership", FoundationAuthoringValidationIssue.SEVERITY_ERROR, record, "Override region ownership is stale.")


static func _validate_live_state(
	world: FoundationWorldData,
	record: FoundationOverrideRecord,
	issues: Array[FoundationAuthoringValidationIssue]
) -> void:
	var live := world.get_record(record.target_record_id)
	var live_fingerprint := FoundationSpatialRecordCodec.fingerprint(live.to_dict()) if live != null else ""
	match record.operation_kind:
		FoundationOverrideRecord.OP_MODIFY:
			if live == null:
				_add(issues, &"missing_override_target", FoundationAuthoringValidationIssue.SEVERITY_WARNING, record, "Modified target is absent; reapply cannot proceed.")
			elif live_fingerprint not in [record.base_fingerprint, record.authored_fingerprint]:
				_add(issues, &"override_base_drift", FoundationAuthoringValidationIssue.SEVERITY_WARNING, record, "Live target differs from retained base and authored snapshots.")
		FoundationOverrideRecord.OP_CREATE:
			if live != null and live_fingerprint != record.authored_fingerprint:
				_add(issues, &"authored_target_collision", FoundationAuthoringValidationIssue.SEVERITY_WARNING, record, "Authored creation collides with a different live target.")
		FoundationOverrideRecord.OP_DELETE:
			if live != null and live_fingerprint != record.base_fingerprint:
				_add(issues, &"delete_target_drift", FoundationAuthoringValidationIssue.SEVERITY_WARNING, record, "Deletion target differs from its retained base.")


static func _validate_history(
	history: FoundationAuthoringHistory,
	policy: FoundationAuthoringPolicy,
	issues: Array[FoundationAuthoringValidationIssue]
) -> void:
	if history.maximum_commands <= 0 or history.maximum_commands > policy.maximum_history_commands or history.commands.size() > history.maximum_commands or history.cursor < 0 or history.cursor > history.commands.size():
		issues.append(FoundationAuthoringValidationIssue.new(&"invalid_authoring_history", FoundationAuthoringValidationIssue.SEVERITY_ERROR, &"", &"", "History cap or cursor is invalid."))
	var previous_sequence := 0
	var ids: Dictionary = {}
	for command in history.commands:
		if command.sequence <= previous_sequence or String(command.command_id).is_empty() or ids.has(command.command_id):
			issues.append(FoundationAuthoringValidationIssue.new(&"invalid_authoring_command_order", FoundationAuthoringValidationIssue.SEVERITY_ERROR, &"", command.target_record_id, "History commands require unique increasing identities."))
		previous_sequence = command.sequence
		ids[command.command_id] = true
		if not FoundationSpatialRecordCodec.is_json_safe(command.to_dict()):
			issues.append(FoundationAuthoringValidationIssue.new(&"non_json_authoring_command", FoundationAuthoringValidationIssue.SEVERITY_ERROR, &"", command.target_record_id, "History command contains non-JSON-safe data."))


static func _add(
	issues: Array[FoundationAuthoringValidationIssue],
	kind: StringName,
	severity: StringName,
	record: FoundationOverrideRecord,
	message: String
) -> void:
	issues.append(FoundationAuthoringValidationIssue.new(
		kind, severity, record.stable_id, record.target_record_id, message,
		{"point": {"x": record.world_bounds.get_center().x, "y": record.world_bounds.get_center().y}}
	))
