class_name FoundationRoadCrossSectionRecord
extends FoundationSpatialRecord

## Canonical lane and right-of-way metadata derived from one Phase 2 road edge.

const CROSS_SECTION_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"road_cross_section"
const ENTITY_TYPE: StringName = &"road_cross_section"
const LAYER_TYPE: StringName = &"road_cross_sections"

const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var road_edge_id: StringName
var logical_road_id: StringName
var physical_profile_key: StringName
var carriageway_width := 0.0
var median_width := 0.0
var shoulder_width := 0.0
var sidewalk_width := 0.0
var speed_limit_kph := 0.0
var lanes: Array[FoundationRoadLane] = []
var source_topology_fingerprint := ""
var validation_state: StringName = VALID
var validation_messages := PackedStringArray()


func _init(
	p_stable_id: StringName = &"",
	p_road_edge_id: StringName = &"",
	p_bounds := Rect2()
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, p_bounds, p_road_edge_id)
	road_edge_id = p_road_edge_id


func refresh_metrics() -> void:
	lanes.sort_custom(FoundationRoadLane.less)
	carriageway_width = median_width
	for lane in lanes:
		carriageway_width += lane.width
	world_bounds = _bounds_for_lanes(lanes)


func get_lane(lane_id: StringName) -> FoundationRoadLane:
	for lane in lanes:
		if lane.lane_id == lane_id:
			return lane
	return null


func lanes_for_direction(direction: StringName) -> Array[FoundationRoadLane]:
	var result: Array[FoundationRoadLane] = []
	for lane in lanes:
		if lane.direction == direction:
			result.append(lane)
	return result


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_lanes: Array[Dictionary] = []
	for lane in lanes:
		serialized_lanes.append(lane.to_dict())
	data["record_kind"] = String(RECORD_KIND)
	data["cross_section_format_version"] = CROSS_SECTION_FORMAT_VERSION
	data["road_edge_id"] = String(road_edge_id)
	data["logical_road_id"] = String(logical_road_id)
	data["physical_profile_key"] = String(physical_profile_key)
	data["carriageway_width"] = carriageway_width
	data["median_width"] = median_width
	data["shoulder_width"] = shoulder_width
	data["sidewalk_width"] = sidewalk_width
	data["speed_limit_kph"] = speed_limit_kph
	data["lanes"] = serialized_lanes
	data["source_topology_fingerprint"] = source_topology_fingerprint
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationRoadCrossSectionRecord:
	var record := FoundationRoadCrossSectionRecord.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("road_edge_id", data.get("parent_id", ""))),
		FoundationSpatialRecord._rect_from_dict(data.get("world_bounds", {}))
	)
	FoundationSpatialRecord.apply_serialized_fields(record, data)
	record.entity_type = ENTITY_TYPE
	record.layer_type = LAYER_TYPE
	record.road_edge_id = StringName(data.get("road_edge_id", data.get("parent_id", "")))
	record.logical_road_id = StringName(data.get("logical_road_id", ""))
	record.physical_profile_key = StringName(data.get("physical_profile_key", ""))
	record.median_width = float(data.get("median_width", 0.0))
	record.shoulder_width = float(data.get("shoulder_width", 0.0))
	record.sidewalk_width = float(data.get("sidewalk_width", 0.0))
	record.speed_limit_kph = float(data.get("speed_limit_kph", 0.0))
	for lane_data: Dictionary in data.get("lanes", []):
		record.lanes.append(FoundationRoadLane.from_dict(lane_data))
	record.source_topology_fingerprint = String(data.get("source_topology_fingerprint", ""))
	record.validation_state = StringName(data.get("validation_state", String(VALID)))
	record.validation_messages = PackedStringArray(data.get("validation_messages", []))
	record.refresh_metrics()
	return record


static func _bounds_for_lanes(values: Array[FoundationRoadLane]) -> Rect2:
	var found := false
	var minimum := Vector2.ZERO
	var maximum := Vector2.ZERO
	for lane in values:
		for point in lane.centerline:
			var planar := Vector2(point.x, point.z)
			if not found:
				minimum = planar
				maximum = planar
				found = true
			else:
				minimum.x = minf(minimum.x, planar.x)
				minimum.y = minf(minimum.y, planar.y)
				maximum.x = maxf(maximum.x, planar.x)
				maximum.y = maxf(maximum.y, planar.y)
	return Rect2(minimum, maximum - minimum) if found else Rect2()
