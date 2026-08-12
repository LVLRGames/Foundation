class_name FoundationParkingFacilityRecord
extends FoundationSpatialRecord

## Canonical abstract parking demand, footprint, layout, and access record.

const PARKING_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"parking_facility"
const ENTITY_TYPE: StringName = &"parking_facility"
const LAYER_TYPE: StringName = &"parking_facilities"

const KIND_SURFACE_LOT: StringName = &"surface_lot"
const KIND_STRUCTURE_PLACEHOLDER: StringName = &"structure_placeholder"
const KIND_CURBSIDE_BAY: StringName = &"curbside_bay"
const KIND_LOADING_SERVICE: StringName = &"loading_service"
const KIND_BICYCLE: StringName = &"bicycle_parking"

const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var facility_kind: StringName = KIND_SURFACE_LOT
var parent_block_id: StringName
var parent_building_id: StringName
var district_id: StringName
var footprint := PackedVector2Array()
var area := 0.0
var centroid := Vector2.ZERO
var label_point := Vector2.ZERO
var orientation_degrees := 0.0
var base_elevation := 0.0
var access_road_edge_id: StringName
var access_logical_road_id: StringName
var frontage_segment_index := -1
var demand_spaces := 0
var supplied_spaces := 0
var accessible_spaces := 0
var bicycle_spaces := 0
var unmet_demand := 0
var spaces: Array[FoundationParkingSpace] = []
var access_paths: Array[FoundationParkingAccessPath] = []
var suitability_evidence: Dictionary = {}
var validation_state: StringName = VALID
var validation_messages := PackedStringArray()


func _init(
	p_stable_id: StringName = &"",
	p_parent_parcel_id: StringName = &"",
	p_parent_block_id: StringName = &"",
	p_footprint := PackedVector2Array()
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, FoundationBlockRecord._bounds_for_boundary(p_footprint), p_parent_parcel_id)
	parent_block_id = p_parent_block_id
	footprint = p_footprint.duplicate()
	refresh_metrics()


func refresh_metrics() -> void:
	world_bounds = FoundationBlockRecord._bounds_for_boundary(footprint)
	area = absf(FoundationBlockRecord._signed_area(footprint))
	centroid = FoundationBlockRecord._polygon_centroid(footprint) if footprint.size() >= 3 else world_bounds.get_center()
	label_point = FoundationBlockRecord._stable_interior_point(footprint, centroid) if footprint.size() >= 3 else centroid
	spaces.sort_custom(FoundationParkingSpace.less)
	access_paths.sort_custom(FoundationParkingAccessPath.less)
	supplied_spaces = spaces.size()
	accessible_spaces = 0
	bicycle_spaces = 0
	for space in spaces:
		if space.accessible:
			accessible_spaces += 1
		if space.space_kind == FoundationParkingSpace.KIND_BICYCLE:
			bicycle_spaces += 1
	unmet_demand = maxi(0, demand_spaces - supplied_spaces)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_footprint: Array[Dictionary] = []
	for point in footprint:
		serialized_footprint.append({"x": point.x, "y": point.y})
	var serialized_spaces: Array[Dictionary] = []
	for space in spaces:
		serialized_spaces.append(space.to_dict())
	var serialized_paths: Array[Dictionary] = []
	for path in access_paths:
		serialized_paths.append(path.to_dict())
	data["record_kind"] = String(RECORD_KIND)
	data["parking_format_version"] = PARKING_FORMAT_VERSION
	data["facility_kind"] = String(facility_kind)
	data["parent_block_id"] = String(parent_block_id)
	data["parent_building_id"] = String(parent_building_id)
	data["district_id"] = String(district_id)
	data["footprint"] = serialized_footprint
	data["area"] = area
	data["centroid"] = {"x": centroid.x, "y": centroid.y}
	data["label_point"] = {"x": label_point.x, "y": label_point.y}
	data["orientation_degrees"] = orientation_degrees
	data["base_elevation"] = base_elevation
	data["access_road_edge_id"] = String(access_road_edge_id)
	data["access_logical_road_id"] = String(access_logical_road_id)
	data["frontage_segment_index"] = frontage_segment_index
	data["demand_spaces"] = demand_spaces
	data["supplied_spaces"] = supplied_spaces
	data["accessible_spaces"] = accessible_spaces
	data["bicycle_spaces"] = bicycle_spaces
	data["unmet_demand"] = unmet_demand
	data["spaces"] = serialized_spaces
	data["access_paths"] = serialized_paths
	data["suitability_evidence"] = suitability_evidence.duplicate(true)
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationParkingFacilityRecord:
	var points := PackedVector2Array()
	for point_data: Dictionary in data.get("footprint", []):
		points.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
	var record := FoundationParkingFacilityRecord.new(
		StringName(data.get("stable_id", "")), StringName(data.get("parent_id", "")),
		StringName(data.get("parent_block_id", "")), points
	)
	FoundationSpatialRecord.apply_serialized_fields(record, data)
	record.entity_type = ENTITY_TYPE
	record.layer_type = LAYER_TYPE
	record.facility_kind = StringName(data.get("facility_kind", String(KIND_SURFACE_LOT)))
	record.parent_block_id = StringName(data.get("parent_block_id", ""))
	record.parent_building_id = StringName(data.get("parent_building_id", ""))
	record.district_id = StringName(data.get("district_id", ""))
	record.orientation_degrees = float(data.get("orientation_degrees", 0.0))
	record.base_elevation = float(data.get("base_elevation", 0.0))
	record.access_road_edge_id = StringName(data.get("access_road_edge_id", ""))
	record.access_logical_road_id = StringName(data.get("access_logical_road_id", ""))
	record.frontage_segment_index = int(data.get("frontage_segment_index", -1))
	record.demand_spaces = int(data.get("demand_spaces", 0))
	record.spaces.clear()
	for space_data: Dictionary in data.get("spaces", []):
		record.spaces.append(FoundationParkingSpace.from_dict(space_data))
	record.access_paths.clear()
	for path_data: Dictionary in data.get("access_paths", []):
		record.access_paths.append(FoundationParkingAccessPath.from_dict(path_data))
	record.suitability_evidence = data.get("suitability_evidence", {}).duplicate(true)
	record.validation_state = StringName(data.get("validation_state", String(VALID)))
	record.validation_messages = PackedStringArray(data.get("validation_messages", []))
	record.refresh_metrics()
	return record


static func builtin_kinds() -> Array[StringName]:
	return [KIND_SURFACE_LOT, KIND_STRUCTURE_PLACEHOLDER, KIND_CURBSIDE_BAY, KIND_LOADING_SERVICE, KIND_BICYCLE]
