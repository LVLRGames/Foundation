class_name FoundationRoadEdge
extends FoundationSpatialRecord

## Abstract terrain-aware road connection represented by a planning polyline only.

const ROAD_EDGE_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"road_edge"
const ENTITY_TYPE: StringName = &"road_edge"
const LAYER_TYPE: StringName = &"road_edges"
const CLASS_CONNECTOR: StringName = &"connector"
const CLASS_ARTERIAL_CONNECTOR: StringName = &"arterial_connector"

var from_node_id: StringName
var to_node_id: StringName
var road_class: StringName = CLASS_CONNECTOR
var route_points := PackedVector3Array()
var planar_length := 0.0
var terrain_cost := 0.0
var maximum_slope_degrees := 0.0
var average_slope_degrees := 0.0
var used_fallback_route := false


func _init(
	p_stable_id: StringName = &"",
	p_from_node_id: StringName = &"",
	p_to_node_id: StringName = &"",
	p_route_points := PackedVector3Array(),
	p_road_class: StringName = CLASS_CONNECTOR
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, _bounds_for_points(p_route_points))
	from_node_id = p_from_node_id
	to_node_id = p_to_node_id
	route_points = p_route_points.duplicate()
	road_class = p_road_class
	refresh_route_metrics()


func refresh_route_metrics() -> void:
	world_bounds = _bounds_for_points(route_points)
	planar_length = 0.0
	maximum_slope_degrees = 0.0
	var weighted_slope := 0.0
	for index in range(route_points.size() - 1):
		var delta := route_points[index + 1] - route_points[index]
		var horizontal := Vector2(delta.x, delta.z).length()
		if horizontal <= 0.000001:
			continue
		var slope := rad_to_deg(atan(absf(delta.y) / horizontal))
		planar_length += horizontal
		maximum_slope_degrees = maxf(maximum_slope_degrees, slope)
		weighted_slope += slope * horizontal
	average_slope_degrees = weighted_slope / planar_length if planar_length > 0.0 else 0.0


func other_node(node_id: StringName) -> StringName:
	if node_id == from_node_id:
		return to_node_id
	if node_id == to_node_id:
		return from_node_id
	return &""


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_points: Array[Dictionary] = []
	for point in route_points:
		serialized_points.append({"x": point.x, "y": point.y, "z": point.z})
	data["record_kind"] = String(RECORD_KIND)
	data["road_edge_format_version"] = ROAD_EDGE_FORMAT_VERSION
	data["from_node_id"] = String(from_node_id)
	data["to_node_id"] = String(to_node_id)
	data["road_class"] = String(road_class)
	data["route_points"] = serialized_points
	data["planar_length"] = planar_length
	data["terrain_cost"] = terrain_cost
	data["maximum_slope_degrees"] = maximum_slope_degrees
	data["average_slope_degrees"] = average_slope_degrees
	data["used_fallback_route"] = used_fallback_route
	return data


static func from_dict(data: Dictionary) -> FoundationRoadEdge:
	var points := PackedVector3Array()
	for point_data: Dictionary in data.get("route_points", []):
		points.append(Vector3(
			float(point_data.get("x", 0.0)),
			float(point_data.get("y", 0.0)),
			float(point_data.get("z", 0.0))
		))
	var edge := FoundationRoadEdge.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("from_node_id", "")),
		StringName(data.get("to_node_id", "")),
		points,
		StringName(data.get("road_class", String(CLASS_CONNECTOR)))
	)
	FoundationSpatialRecord.apply_serialized_fields(edge, data)
	edge.entity_type = ENTITY_TYPE
	edge.layer_type = LAYER_TYPE
	edge.planar_length = float(data.get("planar_length", edge.planar_length))
	edge.terrain_cost = float(data.get("terrain_cost", 0.0))
	edge.maximum_slope_degrees = float(data.get("maximum_slope_degrees", edge.maximum_slope_degrees))
	edge.average_slope_degrees = float(data.get("average_slope_degrees", edge.average_slope_degrees))
	edge.used_fallback_route = bool(data.get("used_fallback_route", false))
	return edge


static func _bounds_for_points(points: PackedVector3Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := Vector2(points[0].x, points[0].z)
	var maximum := minimum
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.z)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.z)
	return Rect2(minimum, maximum - minimum)
