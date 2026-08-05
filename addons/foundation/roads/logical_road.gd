class_name FoundationLogicalRoad
extends FoundationSpatialRecord

## Identity-bearing logical road spanning one or more abstract topology edges.

const LOGICAL_ROAD_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"logical_road"
const ENTITY_TYPE: StringName = &"logical_road"
const LAYER_TYPE: StringName = &"logical_roads"

var edge_ids: Array[StringName] = []
var functional_class: StringName = FoundationRoadEdge.CLASS_LOCAL
var continuity_priority := 0.0
var provisional_naming_key: StringName
var start_semantic_role: StringName
var end_semantic_role: StringName


func _init(
	p_stable_id: StringName = &"",
	p_edge_ids: Array[StringName] = [],
	p_functional_class: StringName = FoundationRoadEdge.CLASS_LOCAL,
	p_bounds := Rect2()
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, p_bounds)
	edge_ids = p_edge_ids.duplicate()
	functional_class = p_functional_class


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_edges: Array[String] = []
	for edge_id in edge_ids:
		serialized_edges.append(String(edge_id))
	data["record_kind"] = String(RECORD_KIND)
	data["logical_road_format_version"] = LOGICAL_ROAD_FORMAT_VERSION
	data["edge_ids"] = serialized_edges
	data["functional_class"] = String(functional_class)
	data["continuity_priority"] = continuity_priority
	data["provisional_naming_key"] = String(provisional_naming_key)
	data["start_semantic_role"] = String(start_semantic_role)
	data["end_semantic_role"] = String(end_semantic_role)
	return data


static func from_dict(data: Dictionary) -> FoundationLogicalRoad:
	var ids: Array[StringName] = []
	for edge_id: String in data.get("edge_ids", []):
		ids.append(StringName(edge_id))
	var road := FoundationLogicalRoad.new(
		StringName(data.get("stable_id", "")),
		ids,
		StringName(data.get("functional_class", String(FoundationRoadEdge.CLASS_LOCAL))),
		FoundationSpatialRecord._rect_from_dict(data.get("world_bounds", {}))
	)
	FoundationSpatialRecord.apply_serialized_fields(road, data)
	road.entity_type = ENTITY_TYPE
	road.layer_type = LAYER_TYPE
	road.continuity_priority = float(data.get("continuity_priority", 0.0))
	road.provisional_naming_key = StringName(data.get("provisional_naming_key", ""))
	road.start_semantic_role = StringName(data.get("start_semantic_role", ""))
	road.end_semantic_role = StringName(data.get("end_semantic_role", ""))
	return road
