class_name FoundationInteriorRecord
extends FoundationSpatialRecord

## Selectively generated Node-free floor, room, portal, and vertical-circulation data.

const INTERIOR_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"interior"
const ENTITY_TYPE: StringName = &"interior"
const LAYER_TYPE: StringName = &"interiors"

const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var parent_parcel_id: StringName
var parent_block_id: StringName
var district_id: StringName
var primary_use: StringName
var source_building_fingerprint := ""
var source_floor_count := 0
var source_floor_height := 0.0
var source_base_elevation := 0.0
var source_footprint := PackedVector2Array()
var floors: Array[FoundationInteriorFloor] = []
var vertical_connectors: Array[FoundationInteriorVerticalConnector] = []
var room_count := 0
var portal_count := 0
var validation_state: StringName = VALID
var validation_messages := PackedStringArray()


func _init(
	p_stable_id: StringName = &"",
	p_parent_building_id: StringName = &"",
	p_source_footprint := PackedVector2Array()
) -> void:
	super(
		p_stable_id, ENTITY_TYPE, LAYER_TYPE,
		FoundationBlockRecord._bounds_for_boundary(p_source_footprint), p_parent_building_id
	)
	source_footprint = p_source_footprint.duplicate()


func refresh_metrics() -> void:
	world_bounds = FoundationBlockRecord._bounds_for_boundary(source_footprint)
	floors.sort_custom(FoundationInteriorFloor.less)
	vertical_connectors.sort_custom(FoundationInteriorVerticalConnector.less)
	room_count = 0
	portal_count = 0
	for floor in floors:
		floor.refresh_metrics()
		room_count += floor.rooms.size()
		portal_count += floor.portals.size()


func get_floor(floor_index: int) -> FoundationInteriorFloor:
	for floor in floors:
		if floor.floor_index == floor_index:
			return floor
	return null


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var footprint_points: Array[Dictionary] = []
	for point in source_footprint:
		footprint_points.append({"x": point.x, "y": point.y})
	var serialized_floors: Array[Dictionary] = []
	for floor in floors:
		serialized_floors.append(floor.to_dict())
	var serialized_connectors: Array[Dictionary] = []
	for connector in vertical_connectors:
		serialized_connectors.append(connector.to_dict())
	data["record_kind"] = String(RECORD_KIND)
	data["interior_format_version"] = INTERIOR_FORMAT_VERSION
	data["parent_parcel_id"] = String(parent_parcel_id)
	data["parent_block_id"] = String(parent_block_id)
	data["district_id"] = String(district_id)
	data["primary_use"] = String(primary_use)
	data["source_building_fingerprint"] = source_building_fingerprint
	data["source_floor_count"] = source_floor_count
	data["source_floor_height"] = source_floor_height
	data["source_base_elevation"] = source_base_elevation
	data["source_footprint"] = footprint_points
	data["floors"] = serialized_floors
	data["vertical_connectors"] = serialized_connectors
	data["room_count"] = room_count
	data["portal_count"] = portal_count
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationInteriorRecord:
	var footprint := PackedVector2Array()
	for point_data: Dictionary in data.get("source_footprint", []):
		footprint.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
	var interior := FoundationInteriorRecord.new(
		StringName(data.get("stable_id", "")), StringName(data.get("parent_id", "")), footprint
	)
	FoundationSpatialRecord.apply_serialized_fields(interior, data)
	interior.entity_type = ENTITY_TYPE
	interior.layer_type = LAYER_TYPE
	interior.parent_parcel_id = StringName(data.get("parent_parcel_id", ""))
	interior.parent_block_id = StringName(data.get("parent_block_id", ""))
	interior.district_id = StringName(data.get("district_id", ""))
	interior.primary_use = StringName(data.get("primary_use", ""))
	interior.source_building_fingerprint = String(data.get("source_building_fingerprint", ""))
	interior.source_floor_count = int(data.get("source_floor_count", 0))
	interior.source_floor_height = float(data.get("source_floor_height", 0.0))
	interior.source_base_elevation = float(data.get("source_base_elevation", 0.0))
	for floor_data: Dictionary in data.get("floors", []):
		interior.floors.append(FoundationInteriorFloor.from_dict(floor_data))
	for connector_data: Dictionary in data.get("vertical_connectors", []):
		interior.vertical_connectors.append(FoundationInteriorVerticalConnector.from_dict(connector_data))
	interior.refresh_metrics()
	interior.room_count = int(data.get("room_count", interior.room_count))
	interior.portal_count = int(data.get("portal_count", interior.portal_count))
	interior.validation_state = StringName(data.get("validation_state", String(VALID)))
	interior.validation_messages = PackedStringArray(data.get("validation_messages", []))
	return interior
