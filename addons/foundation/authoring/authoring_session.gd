class_name FoundationAuthoringSession
extends RefCounted

## Atomic Node-free Phase 11 authoring, override, conflict, and history API.

const SOURCE_PASS: StringName = &"phase_11_authoring"

var policy: FoundationAuthoringPolicy
var history: FoundationAuthoringHistory


func _init(p_policy: FoundationAuthoringPolicy = null) -> void:
	policy = p_policy if p_policy != null else FoundationAuthoringPolicy.new()
	history = FoundationAuthoringHistory.new(policy.maximum_history_commands)


func lock_record(world: FoundationWorldData, target_id: StringName) -> FoundationAuthoringResult:
	return _set_lock_state(world, target_id, true)


func unlock_record(world: FoundationWorldData, target_id: StringName) -> FoundationAuthoringResult:
	return _set_lock_state(world, target_id, false)


func apply_override(
	world: FoundationWorldData,
	target_id: StringName,
	authored_data: Dictionary,
	summary := "",
	force := false
) -> FoundationAuthoringResult:
	var result := _result(&"override", target_id)
	if not _valid_world_and_policy(world, result):
		return result
	var target := world.get_record(target_id)
	if target == null or target is FoundationOverrideRecord:
		return result.fail("Override target does not exist or is not authorable.")
	if not _record_supported(target):
		return result.fail("Target layer or record kind is outside the Phase 11 authoring policy.")
	var existing := world.get_override_for_target(target_id)
	if existing != null and existing.operation_kind == FoundationOverrideRecord.OP_DELETE:
		return result.fail("Revert the active tombstone before applying a new override.")
	if existing == null and world.get_overrides().size() >= policy.maximum_active_overrides:
		return result.fail("Authoring override cap reached.")
	var before_target := target.to_dict()
	var before_override := existing.to_dict() if existing != null else {}
	if existing != null:
		var live_fingerprint := FoundationSpatialRecordCodec.fingerprint(before_target)
		if live_fingerprint not in [existing.base_fingerprint, existing.authored_fingerprint] and policy.reject_base_drift and not force:
			return result.fail("Live target differs from both retained base and authored snapshots.", FoundationOverrideRecord.CONFLICT_BASE_DRIFT)
	var prepared := _prepare_authored(world, authored_data, before_target)
	if not bool(prepared.get("success", false)):
		return result.fail(String(prepared.get("error", "Authored snapshot is invalid.")))
	var authored_record := prepared["record"] as FoundationSpatialRecord
	var normalized: Dictionary = prepared["data"]
	var operation := existing.operation_kind if existing != null else FoundationOverrideRecord.OP_MODIFY
	var base_data := existing.base_record_data.duplicate(true) if existing != null else before_target.duplicate(true)
	var revision := existing.revision + 1 if existing != null else 1
	var override_record := _build_override(world, target, operation, base_data, normalized, revision, summary, existing)
	if override_record == null:
		return result.fail("Could not construct a valid override record.")
	if not world.register_record(authored_record):
		return result.fail("Could not register the authored target.")
	if not world.register_record(override_record):
		_restore_single(world, before_target)
		return result.fail("Could not register the override instruction.")
	var command := _command(&"override", target_id, summary, before_target, normalized, before_override, override_record.to_dict(), target.layer_type)
	history.push(command)
	_update_metadata(world)
	result.success = true
	result.override_record_id = override_record.stable_id
	result.changed_fields = override_record.changed_fields.duplicate()
	result.affected_layers = command.affected_layers.duplicate()
	result.message = "Applied authored revision %d." % revision
	return result


func apply_property_patch(
	world: FoundationWorldData,
	target_id: StringName,
	patch: Dictionary,
	summary := "",
	force := false
) -> FoundationAuthoringResult:
	var target := world.get_record(target_id) if world != null else null
	if target == null:
		return _result(&"override", target_id).fail("Override target does not exist.")
	var data := target.to_dict()
	for key in patch:
		data[key] = patch[key]
	return apply_override(world, target_id, data, summary, force)


func translate_record(
	world: FoundationWorldData,
	target_id: StringName,
	delta: Vector2,
	summary := ""
) -> FoundationAuthoringResult:
	var target := world.get_record(target_id) if world != null else null
	if target == null:
		return _result(&"translate", target_id).fail("Translate target does not exist.")
	if delta == Vector2.ZERO:
		return _result(&"translate", target_id).fail("Translate delta must be non-zero.")
	return apply_override(
		world, target_id,
		FoundationSpatialRecordCodec.translate_record_data(target.to_dict(), delta),
		summary if not summary.is_empty() else "Translate by %.3f, %.3f" % [delta.x, delta.y]
	)


func create_authored_record(
	world: FoundationWorldData,
	authored_data: Dictionary,
	summary := ""
) -> FoundationAuthoringResult:
	var target_id := StringName(authored_data.get("stable_id", ""))
	var result := _result(&"create", target_id)
	if not _valid_world_and_policy(world, result):
		return result
	if String(target_id).is_empty() or world.get_record(target_id) != null:
		return result.fail("Authored creation needs a new non-empty stable ID.", FoundationOverrideRecord.CONFLICT_TARGET_COLLISION)
	if world.get_overrides().size() >= policy.maximum_active_overrides:
		return result.fail("Authoring override cap reached.")
	var prepared := _prepare_authored(world, authored_data, {})
	if not bool(prepared.get("success", false)):
		return result.fail(String(prepared.get("error", "Authored snapshot is invalid.")))
	var authored_record := prepared["record"] as FoundationSpatialRecord
	var normalized: Dictionary = prepared["data"]
	if not _record_supported(authored_record):
		return result.fail("Authored record layer or kind is outside the Phase 11 policy.")
	var override_record := _build_override(world, authored_record, FoundationOverrideRecord.OP_CREATE, {}, normalized, 1, summary, null)
	if override_record == null:
		return result.fail("Could not construct a valid creation override.")
	if not world.register_record(authored_record):
		return result.fail("Could not register authored creation.")
	if not world.register_record(override_record):
		world.unregister_record(target_id)
		return result.fail("Could not register creation override.")
	var command := _command(&"create", target_id, summary, {}, normalized, {}, override_record.to_dict(), authored_record.layer_type)
	history.push(command)
	_update_metadata(world)
	result.success = true
	result.override_record_id = override_record.stable_id
	result.changed_fields = override_record.changed_fields.duplicate()
	result.affected_layers = command.affected_layers.duplicate()
	result.message = "Created authored record."
	return result


func delete_record(
	world: FoundationWorldData,
	target_id: StringName,
	summary := "",
	force := false
) -> FoundationAuthoringResult:
	var result := _result(&"delete", target_id)
	if not _valid_world_and_policy(world, result):
		return result
	var target := world.get_record(target_id)
	if target == null or target is FoundationOverrideRecord:
		return result.fail("Delete target does not exist or is not authorable.")
	if not _record_supported(target):
		return result.fail("Delete target is outside the Phase 11 policy.")
	var existing := world.get_override_for_target(target_id)
	if existing == null and world.get_overrides().size() >= policy.maximum_active_overrides:
		return result.fail("Authoring override cap reached.")
	var before_target := target.to_dict()
	var before_override := existing.to_dict() if existing != null else {}
	if existing != null:
		var live_fingerprint := FoundationSpatialRecordCodec.fingerprint(before_target)
		if live_fingerprint not in [existing.base_fingerprint, existing.authored_fingerprint] and policy.reject_base_drift and not force:
			return result.fail("Live target drifted before deletion.", FoundationOverrideRecord.CONFLICT_BASE_DRIFT)
	if existing != null and existing.operation_kind == FoundationOverrideRecord.OP_CREATE:
		world.unregister_record(target_id)
		world.unregister_record(existing.stable_id)
		var cancel_command := _command(&"delete", target_id, summary, before_target, {}, before_override, {}, target.layer_type)
		history.push(cancel_command)
		_update_metadata(world)
		result.success = true
		result.override_record_id = existing.stable_id
		result.changed_fields = existing.changed_fields.duplicate()
		result.affected_layers = cancel_command.affected_layers.duplicate()
		result.message = "Removed authored creation; undo can restore it."
		return result
	var base_data := existing.base_record_data.duplicate(true) if existing != null else before_target.duplicate(true)
	var revision := existing.revision + 1 if existing != null else 1
	var override_record := _build_override(world, target, FoundationOverrideRecord.OP_DELETE, base_data, {}, revision, summary, existing)
	if override_record == null:
		return result.fail("Could not construct a valid deletion tombstone.")
	world.unregister_record(target_id)
	if not world.register_record(override_record):
		_restore_single(world, before_target)
		return result.fail("Could not register deletion tombstone.")
	var command := _command(&"delete", target_id, summary, before_target, {}, before_override, override_record.to_dict(), target.layer_type)
	history.push(command)
	_update_metadata(world)
	result.success = true
	result.override_record_id = override_record.stable_id
	result.changed_fields = override_record.changed_fields.duplicate()
	result.affected_layers = command.affected_layers.duplicate()
	result.message = "Applied durable deletion tombstone."
	return result


func revert_override(
	world: FoundationWorldData,
	target_id: StringName,
	force := false
) -> FoundationAuthoringResult:
	var result := _result(&"revert", target_id)
	if not _valid_world_and_policy(world, result):
		return result
	var override_record := world.get_override_for_target(target_id)
	if override_record == null:
		return result.fail("No active override exists for the target.")
	var live := world.get_record(target_id)
	var before_target := live.to_dict() if live != null else {}
	var before_override := override_record.to_dict()
	if live != null:
		var live_fingerprint := FoundationSpatialRecordCodec.fingerprint(before_target)
		var allowed := [override_record.base_fingerprint, override_record.authored_fingerprint]
		if live_fingerprint not in allowed and policy.reject_base_drift and not force:
			return result.fail("Live target drifted before override reversion.", FoundationOverrideRecord.CONFLICT_BASE_DRIFT)
	var restored: FoundationSpatialRecord
	if override_record.operation_kind != FoundationOverrideRecord.OP_CREATE:
		restored = _decode_for_world(world, override_record.base_record_data)
		if restored == null:
			return result.fail("Retained base snapshot cannot be restored.")
	if live != null:
		world.unregister_record(target_id)
	world.unregister_record(override_record.stable_id)
	var after_target: Dictionary = {}
	if restored != null:
		world.register_record(restored)
		after_target = restored.to_dict()
	var command := _command(&"revert", target_id, "Revert override", before_target, after_target, before_override, {}, override_record.target_layer_type)
	history.push(command)
	_update_metadata(world)
	result.success = true
	result.override_record_id = override_record.stable_id
	result.affected_layers = command.affected_layers.duplicate()
	result.message = "Reverted override to retained base state."
	return result


func reapply_all(world: FoundationWorldData, force := false) -> FoundationAuthoringResult:
	var result := _result(&"reapply", &"")
	if not _valid_world_and_policy(world, result):
		return result
	for override_record in world.get_overrides():
		if not override_record.active:
			continue
		var live := world.get_record(override_record.target_record_id)
		var live_fingerprint := FoundationSpatialRecordCodec.fingerprint(live.to_dict()) if live != null else ""
		match override_record.operation_kind:
			FoundationOverrideRecord.OP_MODIFY:
				if live_fingerprint == override_record.authored_fingerprint:
					_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_NONE)
					result.already_applied_count += 1
				elif live == null:
					_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_MISSING_TARGET)
					result.conflicted_count += 1
				elif live_fingerprint == override_record.base_fingerprint or force or not policy.reject_base_drift:
					var authored := _decode_for_world(world, override_record.authored_record_data)
					if authored != null:
						world.register_record(authored)
						_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_NONE)
						result.applied_count += 1
					else:
						_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_BASE_DRIFT)
						result.conflicted_count += 1
				else:
					_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_BASE_DRIFT)
					result.conflicted_count += 1
			FoundationOverrideRecord.OP_CREATE:
				if live_fingerprint == override_record.authored_fingerprint:
					_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_NONE)
					result.already_applied_count += 1
				elif live == null or force or not policy.reject_base_drift:
					var authored := _decode_for_world(world, override_record.authored_record_data)
					if authored != null:
						world.register_record(authored)
						_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_NONE)
						result.applied_count += 1
					else:
						_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_TARGET_COLLISION)
						result.conflicted_count += 1
				else:
					_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_TARGET_COLLISION)
					result.conflicted_count += 1
			FoundationOverrideRecord.OP_DELETE:
				if live == null:
					_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_NONE)
					result.already_applied_count += 1
				elif live_fingerprint == override_record.base_fingerprint or force or not policy.reject_base_drift:
					world.unregister_record(override_record.target_record_id)
					_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_NONE)
					result.applied_count += 1
				else:
					_mark_override_state(override_record, FoundationOverrideRecord.CONFLICT_BASE_DRIFT)
					result.conflicted_count += 1
	_update_metadata(world)
	result.success = result.conflicted_count == 0
	result.message = "Reapplied %d, already applied %d, conflicted %d." % [result.applied_count, result.already_applied_count, result.conflicted_count]
	return result


func undo(world: FoundationWorldData) -> FoundationAuthoringResult:
	var result := _result(&"undo", &"")
	if world == null or not history.can_undo():
		return result.fail("No authoring command is available to undo.")
	var command := history.peek_undo()
	if not _restore_command_state(world, command, false):
		return result.fail("Undo snapshots could not be restored atomically.")
	history.mark_undone()
	_update_metadata(world)
	result.success = true
	result.target_record_id = command.target_record_id
	result.affected_layers = command.affected_layers.duplicate()
	result.message = "Undid %s." % command.action
	return result


func redo(world: FoundationWorldData) -> FoundationAuthoringResult:
	var result := _result(&"redo", &"")
	if world == null or not history.can_redo():
		return result.fail("No authoring command is available to redo.")
	var command := history.peek_redo()
	if not _restore_command_state(world, command, true):
		return result.fail("Redo snapshots could not be restored atomically.")
	history.mark_redone()
	_update_metadata(world)
	result.success = true
	result.target_record_id = command.target_record_id
	result.affected_layers = command.affected_layers.duplicate()
	result.message = "Redid %s." % command.action
	return result


func _set_lock_state(world: FoundationWorldData, target_id: StringName, locked: bool) -> FoundationAuthoringResult:
	var action: StringName = &"lock" if locked else &"unlock"
	var result := _result(action, target_id)
	if not _valid_world_and_policy(world, result):
		return result
	var target := world.get_record(target_id)
	if target == null or target is FoundationOverrideRecord or not _record_supported(target):
		return result.fail("Lock target does not exist or is not authorable.")
	if target.authorship_state == FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
		return result.fail("Revert the active override before changing lock state.")
	var desired := FoundationSpatialRecord.AuthorshipState.LOCKED if locked else FoundationSpatialRecord.AuthorshipState.GENERATED
	if target.authorship_state == desired:
		result.success = true
		result.message = "Record already has the requested lock state."
		return result
	var before := target.to_dict()
	var after := before.duplicate(true)
	after["authorship_state"] = desired
	var replacement := _decode_for_world(world, after)
	if replacement == null:
		return result.fail("Lock-state replacement could not be restored.")
	world.register_record(replacement)
	var command := _command(action, target_id, String(action), before, replacement.to_dict(), {}, {}, target.layer_type)
	history.push(command)
	_update_metadata(world)
	result.success = true
	result.affected_layers = command.affected_layers.duplicate()
	result.message = "Record %s." % ("locked" if locked else "unlocked")
	return result


func _prepare_authored(world: FoundationWorldData, authored_data: Dictionary, original_data: Dictionary) -> Dictionary:
	if not FoundationSpatialRecordCodec.is_json_safe(authored_data):
		return {"success": false, "error": "Authored snapshot contains a non-JSON-safe value."}
	if not original_data.is_empty():
		for field in policy.protected_fields:
			if FoundationSpatialRecordCodec.canonical_json(authored_data.get(field)) != FoundationSpatialRecordCodec.canonical_json(original_data.get(field)):
				return {"success": false, "error": "Protected field '%s' cannot be changed." % field}
	var normalized := authored_data.duplicate(true)
	normalized["authorship_state"] = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	normalized["source_pass"] = String(SOURCE_PASS)
	normalized["source_version"] = policy.authoring_version
	var record := FoundationSpatialRecordCodec.record_from_dict(normalized)
	if record == null or record is FoundationOverrideRecord or not _record_supported(record):
		return {"success": false, "error": "Authored snapshot has an unsupported record kind or layer."}
	if not is_finite(record.world_bounds.position.x) or not is_finite(record.world_bounds.position.y) or not is_finite(record.world_bounds.size.x) or not is_finite(record.world_bounds.size.y) or record.world_bounds.size.x < 0.0 or record.world_bounds.size.y < 0.0:
		return {"success": false, "error": "Authored snapshot has invalid world bounds."}
	_refresh_ownership(world, record)
	normalized = record.to_dict()
	if not FoundationSpatialRecordCodec.is_json_safe(normalized):
		return {"success": false, "error": "Normalized authored record is not JSON-safe."}
	return {"success": true, "record": record, "data": normalized}


func _build_override(
	world: FoundationWorldData,
	target: FoundationSpatialRecord,
	operation: StringName,
	base_data: Dictionary,
	authored_data: Dictionary,
	revision: int,
	summary: String,
	existing: FoundationOverrideRecord
) -> FoundationOverrideRecord:
	var bounds := target.world_bounds
	if not authored_data.is_empty():
		bounds = FoundationSpatialRecord._rect_from_dict(authored_data.get("world_bounds", {}))
	elif not base_data.is_empty():
		bounds = FoundationSpatialRecord._rect_from_dict(base_data.get("world_bounds", {}))
	var override_id := existing.stable_id if existing != null else FoundationSpatialId.make(
		world.metadata.seed, policy.authoring_version, world.metadata.content_pack_version,
		FoundationOverrideRecord.ENTITY_TYPE, target.stable_id, String(policy.policy_id)
	)
	var record := FoundationOverrideRecord.new(override_id, target.stable_id, operation, bounds)
	record.target_layer_type = target.layer_type
	record.target_entity_type = target.entity_type
	record.target_record_kind = StringName(target.to_dict().get("record_kind", ""))
	record.target_parent_id = target.parent_id
	record.base_record_data = base_data.duplicate(true)
	record.authored_record_data = authored_data.duplicate(true)
	record.base_fingerprint = FoundationSpatialRecordCodec.fingerprint(base_data) if not base_data.is_empty() else ""
	record.authored_fingerprint = FoundationSpatialRecordCodec.fingerprint(authored_data) if not authored_data.is_empty() else ""
	record.changed_fields = FoundationSpatialRecordCodec.changed_field_paths(base_data, authored_data)
	record.revision = revision
	record.summary = summary
	record.source_pass = SOURCE_PASS
	record.source_version = policy.authoring_version
	record.tags = PackedStringArray(["phase_11", "authoring", String(operation)])
	_refresh_ownership(world, record)
	return record


func _command(
	action: StringName,
	target_id: StringName,
	summary: String,
	before_target: Dictionary,
	after_target: Dictionary,
	before_override: Dictionary,
	after_override: Dictionary,
	layer_type: StringName
) -> FoundationAuthoringCommand:
	var command := FoundationAuthoringCommand.new()
	command.action = action
	command.target_record_id = target_id
	command.summary = summary
	command.before_target_data = before_target.duplicate(true)
	command.after_target_data = after_target.duplicate(true)
	command.before_override_data = before_override.duplicate(true)
	command.after_override_data = after_override.duplicate(true)
	command.affected_layers = [layer_type]
	command.affected_layers.append_array(policy.downstream_layers(layer_type))
	return command


func _restore_command_state(world: FoundationWorldData, command: FoundationAuthoringCommand, use_after: bool) -> bool:
	var target_data := command.after_target_data if use_after else command.before_target_data
	var override_data := command.after_override_data if use_after else command.before_override_data
	var target := _decode_for_world(world, target_data) if not target_data.is_empty() else null
	var override_record := _decode_for_world(world, override_data) if not override_data.is_empty() else null
	if (not target_data.is_empty() and target == null) or (not override_data.is_empty() and not (override_record is FoundationOverrideRecord)):
		return false
	var current_override := world.get_override_for_target(command.target_record_id)
	if world.get_record(command.target_record_id) != null:
		world.unregister_record(command.target_record_id)
	if current_override != null:
		world.unregister_record(current_override.stable_id)
	if target != null:
		world.register_record(target)
	if override_record != null:
		world.register_record(override_record)
	return true


func _decode_for_world(world: FoundationWorldData, data: Dictionary) -> FoundationSpatialRecord:
	if data.is_empty() or not FoundationSpatialRecordCodec.is_json_safe(data):
		return null
	var record := FoundationSpatialRecordCodec.record_from_dict(data)
	if record == null:
		return null
	_refresh_ownership(world, record)
	return record


func _restore_single(world: FoundationWorldData, data: Dictionary) -> void:
	var record := _decode_for_world(world, data)
	if record != null:
		world.register_record(record)


func _refresh_ownership(world: FoundationWorldData, record: FoundationSpatialRecord) -> void:
	record.set_owning_chunks(world.coordinate_system.world_bounds_to_chunks(record.world_bounds))
	var region_set: Dictionary = {}
	for chunk in record.owning_chunks:
		region_set[world.coordinate_system.chunk_to_region(chunk)] = true
	var regions: Array[Vector2i] = []
	for region: Vector2i in region_set:
		regions.append(region)
	record.set_owning_regions(regions)


func _record_supported(record: FoundationSpatialRecord) -> bool:
	return record.layer_type in policy.supported_layers() and StringName(record.to_dict().get("record_kind", "")) in policy.supported_record_kinds()


func _valid_world_and_policy(world: FoundationWorldData, result: FoundationAuthoringResult) -> bool:
	if world == null:
		result.fail("Authoring requires FoundationWorldData.")
		return false
	var errors := policy.validation_errors()
	if not errors.is_empty():
		result.fail("Invalid authoring policy: %s" % "; ".join(errors))
		return false
	world.register_layer_type(FoundationWorldData.OVERRIDE_LAYER)
	return true


func _mark_override_state(record: FoundationOverrideRecord, conflict: StringName) -> void:
	record.conflict_state = conflict
	record.validation_state = FoundationOverrideRecord.VALID if conflict == FoundationOverrideRecord.CONFLICT_NONE else FoundationOverrideRecord.WARNING
	record.validation_messages = PackedStringArray() if conflict == FoundationOverrideRecord.CONFLICT_NONE else PackedStringArray(["Override reconciliation conflict: %s" % conflict])


func _update_metadata(world: FoundationWorldData) -> void:
	var layer := world.register_layer_type(FoundationWorldData.OVERRIDE_LAYER)
	var conflicts := 0
	var operations: Dictionary = {}
	for override_record in world.get_overrides():
		operations[String(override_record.operation_kind)] = int(operations.get(String(override_record.operation_kind), 0)) + 1
		if override_record.conflict_state != FoundationOverrideRecord.CONFLICT_NONE:
			conflicts += 1
	layer.metadata = {
		"format_version": 1,
		"source_pass": String(SOURCE_PASS),
		"authoring_version": policy.authoring_version,
		"policy": policy.to_dict(),
		"override_count": world.get_overrides().size(),
		"conflict_count": conflicts,
		"operation_counts": operations,
		"history_command_count": history.commands.size(),
		"history_cursor": history.cursor,
	}


func _result(action: StringName, target_id: StringName) -> FoundationAuthoringResult:
	var result := FoundationAuthoringResult.new()
	result.action = action
	result.target_record_id = target_id
	return result
