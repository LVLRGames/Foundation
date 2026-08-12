class_name FoundationOverrideRecord
extends FoundationSpatialRecord

## Durable typed Phase 11 modify/create/delete instruction.

const OVERRIDE_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"override_record"
const ENTITY_TYPE: StringName = &"override"
const LAYER_TYPE: StringName = &"override"

const OP_MODIFY: StringName = &"modify"
const OP_CREATE: StringName = &"create"
const OP_DELETE: StringName = &"delete"

const CONFLICT_NONE: StringName = &"none"
const CONFLICT_BASE_DRIFT: StringName = &"base_drift"
const CONFLICT_MISSING_TARGET: StringName = &"missing_target"
const CONFLICT_TARGET_COLLISION: StringName = &"target_collision"

const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var target_record_id: StringName
var target_layer_type: StringName
var target_entity_type: StringName
var target_record_kind: StringName
var target_parent_id: StringName
var operation_kind: StringName = OP_MODIFY
var base_record_data: Dictionary = {}
var authored_record_data: Dictionary = {}
var base_fingerprint := ""
var authored_fingerprint := ""
var changed_fields := PackedStringArray()
var revision := 1
var summary := ""
var active := true
var conflict_state: StringName = CONFLICT_NONE
var validation_state: StringName = VALID
var validation_messages := PackedStringArray()


func _init(
	p_stable_id: StringName = &"",
	p_target_record_id: StringName = &"",
	p_operation_kind: StringName = OP_MODIFY,
	p_world_bounds := Rect2()
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, p_world_bounds)
	target_record_id = p_target_record_id
	operation_kind = p_operation_kind
	authorship_state = AuthorshipState.OVERRIDDEN


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["record_kind"] = String(RECORD_KIND)
	data["override_format_version"] = OVERRIDE_FORMAT_VERSION
	data["target_record_id"] = String(target_record_id)
	data["target_layer_type"] = String(target_layer_type)
	data["target_entity_type"] = String(target_entity_type)
	data["target_record_kind"] = String(target_record_kind)
	data["target_parent_id"] = String(target_parent_id)
	data["operation_kind"] = String(operation_kind)
	data["base_record_data"] = base_record_data.duplicate(true)
	data["authored_record_data"] = authored_record_data.duplicate(true)
	data["base_fingerprint"] = base_fingerprint
	data["authored_fingerprint"] = authored_fingerprint
	data["changed_fields"] = Array(changed_fields)
	data["revision"] = revision
	data["summary"] = summary
	data["active"] = active
	data["conflict_state"] = String(conflict_state)
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationOverrideRecord:
	var record := FoundationOverrideRecord.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("target_record_id", "")),
		StringName(data.get("operation_kind", String(OP_MODIFY))),
		FoundationSpatialRecord._rect_from_dict(data.get("world_bounds", {}))
	)
	FoundationSpatialRecord.apply_serialized_fields(record, data)
	record.entity_type = ENTITY_TYPE
	record.layer_type = LAYER_TYPE
	record.authorship_state = FoundationSpatialRecord.AuthorshipState.OVERRIDDEN
	record.target_record_id = StringName(data.get("target_record_id", ""))
	record.target_layer_type = StringName(data.get("target_layer_type", ""))
	record.target_entity_type = StringName(data.get("target_entity_type", ""))
	record.target_record_kind = StringName(data.get("target_record_kind", ""))
	record.target_parent_id = StringName(data.get("target_parent_id", ""))
	record.operation_kind = StringName(data.get("operation_kind", String(OP_MODIFY)))
	record.base_record_data = data.get("base_record_data", {}).duplicate(true)
	record.authored_record_data = data.get("authored_record_data", {}).duplicate(true)
	record.base_fingerprint = String(data.get("base_fingerprint", ""))
	record.authored_fingerprint = String(data.get("authored_fingerprint", ""))
	record.changed_fields = PackedStringArray(data.get("changed_fields", []))
	record.revision = int(data.get("revision", 1))
	record.summary = String(data.get("summary", ""))
	record.active = bool(data.get("active", true))
	record.conflict_state = StringName(data.get("conflict_state", String(CONFLICT_NONE)))
	record.validation_state = StringName(data.get("validation_state", String(VALID)))
	record.validation_messages = PackedStringArray(data.get("validation_messages", []))
	return record


static func builtin_operations() -> Array[StringName]:
	return [OP_MODIFY, OP_CREATE, OP_DELETE]
