class_name FoundationRoadNode
extends FoundationSpatialRecord

## Abstract road-topology vertex. It owns no mesh, lane, intersection, or navigation state.

const ROAD_NODE_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"road_node"
const ENTITY_TYPE: StringName = &"road_node"
const LAYER_TYPE: StringName = &"road_nodes"
const KIND_ANCHOR: StringName = &"anchor"

var world_position := Vector3.ZERO
var node_kind: StringName = KIND_ANCHOR
var source_anchor_id: StringName
var incident_edge_ids: Array[StringName] = []


func _init(
	p_stable_id: StringName = &"",
	p_world_position := Vector3.ZERO,
	p_node_kind: StringName = KIND_ANCHOR,
	p_source_anchor_id: StringName = &""
) -> void:
	super(
		p_stable_id,
		ENTITY_TYPE,
		LAYER_TYPE,
		Rect2(Vector2(p_world_position.x, p_world_position.z), Vector2.ZERO),
		p_source_anchor_id
	)
	world_position = p_world_position
	node_kind = p_node_kind
	source_anchor_id = p_source_anchor_id


func set_world_position(value: Vector3) -> void:
	world_position = value
	world_bounds = Rect2(Vector2(value.x, value.z), Vector2.ZERO)


func add_incident_edge(edge_id: StringName) -> void:
	if edge_id not in incident_edge_ids:
		incident_edge_ids.append(edge_id)
		incident_edge_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
			return String(a) < String(b)
		)


func clear_incident_edges() -> void:
	incident_edge_ids.clear()


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_edges: Array[String] = []
	for edge_id in incident_edge_ids:
		serialized_edges.append(String(edge_id))
	data["record_kind"] = String(RECORD_KIND)
	data["road_node_format_version"] = ROAD_NODE_FORMAT_VERSION
	data["world_position"] = {
		"x": world_position.x,
		"y": world_position.y,
		"z": world_position.z,
	}
	data["node_kind"] = String(node_kind)
	data["source_anchor_id"] = String(source_anchor_id)
	data["incident_edge_ids"] = serialized_edges
	return data


static func from_dict(data: Dictionary) -> FoundationRoadNode:
	var position_data: Dictionary = data.get("world_position", {})
	var node := FoundationRoadNode.new(
		StringName(data.get("stable_id", "")),
		Vector3(
			float(position_data.get("x", 0.0)),
			float(position_data.get("y", 0.0)),
			float(position_data.get("z", 0.0))
		),
		StringName(data.get("node_kind", String(KIND_ANCHOR))),
		StringName(data.get("source_anchor_id", ""))
	)
	FoundationSpatialRecord.apply_serialized_fields(node, data)
	node.entity_type = ENTITY_TYPE
	node.layer_type = LAYER_TYPE
	node.incident_edge_ids.clear()
	for edge_id: String in data.get("incident_edge_ids", []):
		node.incident_edge_ids.append(StringName(edge_id))
	node.incident_edge_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return node
