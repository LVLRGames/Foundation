class_name FoundationRoadEdge
extends FoundationSpatialRecord

## Abstract terrain-aware road connection represented by a planning polyline only.

const ROAD_EDGE_FORMAT_VERSION := 2
const RECORD_KIND: StringName = &"road_edge"
const ENTITY_TYPE: StringName = &"road_edge"
const LAYER_TYPE: StringName = &"road_edges"
const CLASS_HIGHWAY: StringName = &"highway"
const CLASS_ARTERIAL: StringName = &"arterial"
const CLASS_COLLECTOR: StringName = &"collector"
const CLASS_LOCAL: StringName = &"local"
const CLASS_ALLEY: StringName = &"alley_service"
const CLASS_DIRT: StringName = &"dirt_road"
const CLASS_CONNECTOR: StringName = CLASS_COLLECTOR
const CLASS_ARTERIAL_CONNECTOR: StringName = CLASS_ARTERIAL

const DIRECTION_TWO_WAY: StringName = &"two_way"
const DIRECTION_ONE_WAY_FORWARD: StringName = &"one_way_forward"
const DIRECTION_ONE_WAY_REVERSE: StringName = &"one_way_reverse"
const DIRECTION_DIVIDED_CONCEPT: StringName = &"divided_concept"

const ACCESS_CONTROLLED: StringName = &"controlled"
const ACCESS_LIMITED: StringName = &"limited"
const ACCESS_FRONTAGE: StringName = &"frontage"
const ACCESS_SERVICE: StringName = &"service"

var from_node_id: StringName
var to_node_id: StringName
var road_class: StringName = CLASS_CONNECTOR
var route_points := PackedVector3Array()
var planar_length := 0.0
var terrain_cost := 0.0
var maximum_slope_degrees := 0.0
var average_slope_degrees := 0.0
var used_fallback_route := false
var physical_profile_key: StringName = &"default_two_way"
var logical_road_id: StringName
var directionality: StringName = DIRECTION_TWO_WAY
var access_control_policy: StringName = ACCESS_FRONTAGE
var allowed_movement_modes := PackedStringArray(["motor_vehicle", "pedestrian", "bicycle"])
var desired_elevation_samples: Array[FoundationRoadElevationSample] = []
var grading_requirements: Dictionary = {}
var generation_source: StringName = &"anchor_connection"
var generation_priority := 0.0
var ownership_jurisdiction: StringName = &"municipal"
var abstract_capacity := 1.0
var continuity_priority := 0.0
var age_era_key: StringName = &"unspecified"
var maintenance_level_key: StringName = &"standard"
var surface_style_key: StringName = &"paved"


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
	data["physical_profile_key"] = String(physical_profile_key)
	data["logical_road_id"] = String(logical_road_id)
	data["directionality"] = String(directionality)
	data["access_control_policy"] = String(access_control_policy)
	data["allowed_movement_modes"] = Array(allowed_movement_modes)
	var serialized_elevation_samples: Array[Dictionary] = []
	for sample in desired_elevation_samples:
		serialized_elevation_samples.append(sample.to_dict())
	data["desired_elevation_samples"] = serialized_elevation_samples
	data["grading_requirements"] = grading_requirements.duplicate(true)
	data["generation_source"] = String(generation_source)
	data["generation_priority"] = generation_priority
	data["ownership_jurisdiction"] = String(ownership_jurisdiction)
	data["abstract_capacity"] = abstract_capacity
	data["continuity_priority"] = continuity_priority
	data["age_era_key"] = String(age_era_key)
	data["maintenance_level_key"] = String(maintenance_level_key)
	data["surface_style_key"] = String(surface_style_key)
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
	if edge.road_class == &"connector":
		edge.road_class = CLASS_COLLECTOR
	elif edge.road_class == &"arterial_connector":
		edge.road_class = CLASS_ARTERIAL
	edge.planar_length = float(data.get("planar_length", edge.planar_length))
	edge.terrain_cost = float(data.get("terrain_cost", 0.0))
	edge.maximum_slope_degrees = float(data.get("maximum_slope_degrees", edge.maximum_slope_degrees))
	edge.average_slope_degrees = float(data.get("average_slope_degrees", edge.average_slope_degrees))
	edge.used_fallback_route = bool(data.get("used_fallback_route", false))
	edge.physical_profile_key = StringName(data.get("physical_profile_key", "default_two_way"))
	edge.logical_road_id = StringName(data.get("logical_road_id", ""))
	edge.directionality = StringName(data.get("directionality", String(DIRECTION_TWO_WAY)))
	edge.access_control_policy = StringName(data.get("access_control_policy", String(ACCESS_FRONTAGE)))
	edge.allowed_movement_modes = PackedStringArray(data.get("allowed_movement_modes", ["motor_vehicle", "pedestrian", "bicycle"]))
	edge.desired_elevation_samples.clear()
	for sample_data: Dictionary in data.get("desired_elevation_samples", []):
		edge.desired_elevation_samples.append(FoundationRoadElevationSample.from_dict(sample_data))
	edge.grading_requirements = data.get("grading_requirements", {}).duplicate(true)
	edge.generation_source = StringName(data.get("generation_source", "anchor_connection"))
	edge.generation_priority = float(data.get("generation_priority", 0.0))
	edge.ownership_jurisdiction = StringName(data.get("ownership_jurisdiction", "municipal"))
	edge.abstract_capacity = float(data.get("abstract_capacity", 1.0))
	edge.continuity_priority = float(data.get("continuity_priority", 0.0))
	edge.age_era_key = StringName(data.get("age_era_key", "unspecified"))
	edge.maintenance_level_key = StringName(data.get("maintenance_level_key", "standard"))
	edge.surface_style_key = StringName(data.get("surface_style_key", "paved"))
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
