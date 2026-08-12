class_name FoundationOverrideDebugProvider
extends FoundationDebugProvider

## Disposable batched Phase 11 override/tombstone/conflict visualization.


func _init() -> void:
	super(&"overrides")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	for override_record in world.get_overrides():
		var elevation := 0.72
		var purpose := _purpose(override_record)
		var fill_purpose: StringName = &"override_fill"
		if override_record.stable_id == selected_id or override_record.target_record_id == selected_id:
			purpose = &"selected"
			fill_purpose = &"override_fill_selected"
		var bounds := override_record.world_bounds
		var points := PackedVector3Array([
			Vector3(bounds.position.x, elevation, bounds.position.y),
			Vector3(bounds.end.x, elevation, bounds.position.y),
			Vector3(bounds.end.x, elevation, bounds.end.y),
			Vector3(bounds.position.x, elevation, bounds.end.y),
		])
		builder.add_filled_polygon(points, fill_purpose)
		builder.add_polygon_outline(points, purpose)
		var center := bounds.get_center()
		builder.add_point(Vector3(center.x, elevation + 0.12, center.y), 0.85, purpose)
		builder.add_text(
			Vector3(center.x, elevation + 1.0, center.y),
			"%s\n%s %s | r%d | %s" % [override_record.stable_id, override_record.operation_kind, override_record.target_record_id, override_record.revision, override_record.conflict_state],
			purpose
		)


func _purpose(record: FoundationOverrideRecord) -> StringName:
	if record.conflict_state != FoundationOverrideRecord.CONFLICT_NONE or record.validation_state == FoundationOverrideRecord.INVALID:
		return &"override_conflict"
	match record.operation_kind:
		FoundationOverrideRecord.OP_CREATE:
			return &"override_create"
		FoundationOverrideRecord.OP_DELETE:
			return &"override_delete"
		_:
			return &"override_modify"
