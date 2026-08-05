class_name FoundationIntersectionRecord
extends FoundationSpatialRecord

## Abstract graph intersection. It contains no lanes, signals, turn geometry, or meshes.

const INTERSECTION_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"road_intersection"
const ENTITY_TYPE: StringName = &"road_intersection"
const LAYER_TYPE: StringName = &"road_intersections"

var node_id: StringName
var connected_edge_ids: Array[StringName] = []
var incoming_edge_ids: Array[StringName] = []
var outgoing_edge_ids: Array[StringName] = []
var intersection_degree := 0
var road_class_relationships: Array[Dictionary] = []
var provisional_intersection_type: StringName = &"junction"


func _init(
	p_stable_id: StringName = &"",
	p_node_id: StringName = &"",
	p_position := Vector3.ZERO
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, Rect2(Vector2(p_position.x, p_position.z), Vector2.ZERO), p_node_id)
	node_id = p_node_id


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["record_kind"] = String(RECORD_KIND)
	data["intersection_format_version"] = INTERSECTION_FORMAT_VERSION
	data["node_id"] = String(node_id)
	data["connected_edge_ids"] = _ids_to_strings(connected_edge_ids)
	data["incoming_edge_ids"] = _ids_to_strings(incoming_edge_ids)
	data["outgoing_edge_ids"] = _ids_to_strings(outgoing_edge_ids)
	data["intersection_degree"] = intersection_degree
	data["road_class_relationships"] = road_class_relationships.duplicate(true)
	data["provisional_intersection_type"] = String(provisional_intersection_type)
	return data


static func from_dict(data: Dictionary) -> FoundationIntersectionRecord:
	var bounds := FoundationSpatialRecord._rect_from_dict(data.get("world_bounds", {}))
	var record := FoundationIntersectionRecord.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("node_id", "")),
		Vector3(bounds.position.x, 0.0, bounds.position.y)
	)
	FoundationSpatialRecord.apply_serialized_fields(record, data)
	record.entity_type = ENTITY_TYPE
	record.layer_type = LAYER_TYPE
	record.connected_edge_ids = _strings_to_ids(data.get("connected_edge_ids", []))
	record.incoming_edge_ids = _strings_to_ids(data.get("incoming_edge_ids", []))
	record.outgoing_edge_ids = _strings_to_ids(data.get("outgoing_edge_ids", []))
	record.intersection_degree = int(data.get("intersection_degree", record.connected_edge_ids.size()))
	record.road_class_relationships = data.get("road_class_relationships", []).duplicate(true)
	record.provisional_intersection_type = StringName(data.get("provisional_intersection_type", "junction"))
	return record


static func _ids_to_strings(ids: Array[StringName]) -> Array[String]:
	var values: Array[String] = []
	for stable_id in ids:
		values.append(String(stable_id))
	return values


static func _strings_to_ids(values: Array) -> Array[StringName]:
	var ids: Array[StringName] = []
	for value in values:
		ids.append(StringName(value))
	return ids
