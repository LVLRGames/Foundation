class_name FoundationIntersectionTrafficRecord
extends FoundationSpatialRecord

## Canonical approaches, permitted movements, and abstract control policy at one intersection.

const TRAFFIC_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"intersection_traffic"
const ENTITY_TYPE: StringName = &"intersection_traffic"
const LAYER_TYPE: StringName = &"intersection_traffic"

const CONTROL_UNCONTROLLED: StringName = &"uncontrolled"
const CONTROL_PRIORITY: StringName = &"priority"
const CONTROL_ALL_WAY_STOP: StringName = &"all_way_stop"
const CONTROL_SIGNAL_PLAN: StringName = &"signal_plan"
const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var intersection_id: StringName
var node_id: StringName
var control_type: StringName = CONTROL_UNCONTROLLED
var approaches: Array[FoundationTrafficApproach] = []
var movements: Array[FoundationTurnMovement] = []
var phase_groups: Array[PackedStringArray] = []
var source_topology_fingerprint := ""
var validation_state: StringName = VALID
var validation_messages := PackedStringArray()


func _init(
	p_stable_id: StringName = &"",
	p_intersection_id: StringName = &"",
	p_node_id: StringName = &"",
	p_position := Vector3.ZERO
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, Rect2(Vector2(p_position.x, p_position.z), Vector2.ZERO), p_intersection_id)
	intersection_id = p_intersection_id
	node_id = p_node_id


func refresh_order() -> void:
	approaches.sort_custom(FoundationTrafficApproach.less)
	movements.sort_custom(FoundationTurnMovement.less)
	phase_groups.sort_custom(func(a: PackedStringArray, b: PackedStringArray) -> bool:
		return "|".join(a) < "|".join(b)
	)


func get_approach(approach_id: StringName) -> FoundationTrafficApproach:
	for approach in approaches:
		if approach.approach_id == approach_id:
			return approach
	return null


func get_movement(movement_id: StringName) -> FoundationTurnMovement:
	for movement in movements:
		if movement.movement_id == movement_id:
			return movement
	return null


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_approaches: Array[Dictionary] = []
	for approach in approaches:
		serialized_approaches.append(approach.to_dict())
	var serialized_movements: Array[Dictionary] = []
	for movement in movements:
		serialized_movements.append(movement.to_dict())
	var serialized_groups: Array[Array] = []
	for group in phase_groups:
		serialized_groups.append(Array(group))
	data["record_kind"] = String(RECORD_KIND)
	data["traffic_format_version"] = TRAFFIC_FORMAT_VERSION
	data["intersection_id"] = String(intersection_id)
	data["node_id"] = String(node_id)
	data["control_type"] = String(control_type)
	data["approaches"] = serialized_approaches
	data["movements"] = serialized_movements
	data["phase_groups"] = serialized_groups
	data["source_topology_fingerprint"] = source_topology_fingerprint
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationIntersectionTrafficRecord:
	var bounds := FoundationSpatialRecord._rect_from_dict(data.get("world_bounds", {}))
	var record := FoundationIntersectionTrafficRecord.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("intersection_id", data.get("parent_id", ""))),
		StringName(data.get("node_id", "")),
		Vector3(bounds.position.x, 0.0, bounds.position.y)
	)
	FoundationSpatialRecord.apply_serialized_fields(record, data)
	record.entity_type = ENTITY_TYPE
	record.layer_type = LAYER_TYPE
	record.intersection_id = StringName(data.get("intersection_id", data.get("parent_id", "")))
	record.node_id = StringName(data.get("node_id", ""))
	record.control_type = StringName(data.get("control_type", String(CONTROL_UNCONTROLLED)))
	for approach_data: Dictionary in data.get("approaches", []):
		record.approaches.append(FoundationTrafficApproach.from_dict(approach_data))
	for movement_data: Dictionary in data.get("movements", []):
		record.movements.append(FoundationTurnMovement.from_dict(movement_data))
	for group_data: Array in data.get("phase_groups", []):
		record.phase_groups.append(PackedStringArray(group_data))
	record.source_topology_fingerprint = String(data.get("source_topology_fingerprint", ""))
	record.validation_state = StringName(data.get("validation_state", String(VALID)))
	record.validation_messages = PackedStringArray(data.get("validation_messages", []))
	record.refresh_order()
	return record
