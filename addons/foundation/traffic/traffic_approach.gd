class_name FoundationTrafficApproach
extends RefCounted

## Stable lane membership and priority metadata for one intersection approach.

const FORMAT_VERSION := 1

var approach_id: StringName
var road_edge_id: StringName
var bearing_degrees := 0.0
var priority_rank := 0
var inbound_lane_ids: Array[StringName] = []
var outbound_lane_ids: Array[StringName] = []


func _init(p_approach_id: StringName = &"", p_road_edge_id: StringName = &"") -> void:
	approach_id = p_approach_id
	road_edge_id = p_road_edge_id


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"approach_id": String(approach_id),
		"road_edge_id": String(road_edge_id),
		"bearing_degrees": bearing_degrees,
		"priority_rank": priority_rank,
		"inbound_lane_ids": _strings(inbound_lane_ids),
		"outbound_lane_ids": _strings(outbound_lane_ids),
	}


static func from_dict(data: Dictionary) -> FoundationTrafficApproach:
	var approach := FoundationTrafficApproach.new(
		StringName(data.get("approach_id", "")),
		StringName(data.get("road_edge_id", ""))
	)
	approach.bearing_degrees = float(data.get("bearing_degrees", 0.0))
	approach.priority_rank = int(data.get("priority_rank", 0))
	approach.inbound_lane_ids = _ids(data.get("inbound_lane_ids", []))
	approach.outbound_lane_ids = _ids(data.get("outbound_lane_ids", []))
	return approach


static func less(a: FoundationTrafficApproach, b: FoundationTrafficApproach) -> bool:
	return String(a.approach_id) < String(b.approach_id)


static func _strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result


static func _ids(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value in values:
		result.append(StringName(value))
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result
