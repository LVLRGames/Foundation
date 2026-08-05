class_name FoundationRoadValidationIssue
extends RefCounted

## Deterministic validator output consumed by serialization and disposable debug views.

const FORMAT_VERSION := 1
const INFO: StringName = &"info"
const WARNING: StringName = &"warning"
const ERROR: StringName = &"error"

var code: StringName
var severity: StringName = WARNING
var message := ""
var record_ids: Array[StringName] = []
var world_position := Vector3.ZERO


func _init(
	p_code: StringName = &"unknown",
	p_severity: StringName = WARNING,
	p_message := "",
	p_record_ids: Array[StringName] = [],
	p_world_position := Vector3.ZERO
) -> void:
	code = p_code
	severity = p_severity
	message = p_message
	record_ids = p_record_ids.duplicate()
	record_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	world_position = p_world_position


func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for record_id in record_ids:
		ids.append(String(record_id))
	return {
		"format_version": FORMAT_VERSION,
		"code": String(code),
		"severity": String(severity),
		"message": message,
		"record_ids": ids,
		"world_position": {"x": world_position.x, "y": world_position.y, "z": world_position.z},
	}


static func from_dict(data: Dictionary) -> FoundationRoadValidationIssue:
	var ids: Array[StringName] = []
	for value: String in data.get("record_ids", []):
		ids.append(StringName(value))
	var point: Dictionary = data.get("world_position", {})
	return FoundationRoadValidationIssue.new(
		StringName(data.get("code", "unknown")),
		StringName(data.get("severity", String(WARNING))),
		String(data.get("message", "")),
		ids,
		Vector3(float(point.get("x", 0.0)), float(point.get("y", 0.0)), float(point.get("z", 0.0)))
	)


static func less(a: FoundationRoadValidationIssue, b: FoundationRoadValidationIssue) -> bool:
	var a_key := "%s|%s|%s|%s" % [a.severity, a.code, a.record_ids, a.message]
	var b_key := "%s|%s|%s|%s" % [b.severity, b.code, b.record_ids, b.message]
	return a_key < b_key
