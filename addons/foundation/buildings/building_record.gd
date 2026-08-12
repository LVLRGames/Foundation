class_name FoundationBuildingRecord
extends FoundationSpatialRecord

## Canonical parcel-backed footprint and primitive extruded massing. Owns no scene nodes.

const BUILDING_FORMAT_VERSION := 2
const RECORD_KIND: StringName = &"building"
const ENTITY_TYPE: StringName = &"building"
const LAYER_TYPE: StringName = &"buildings"

const MASSING_EXTRUSION: StringName = &"extruded_footprint"
const ROOF_FLAT: StringName = &"flat"

const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var parent_block_id: StringName
var footprint := PackedVector2Array()
var footprint_area := 0.0
var footprint_perimeter := 0.0
var centroid := Vector2.ZERO
var label_point := Vector2.ZERO
var coverage_ratio := 0.0
var target_coverage_ratio := 0.0
var frontage_span := 0.0
var footprint_depth := 0.0
var footprint_aspect_ratio := 0.0
var long_form := false
var front_setback := 0.0
var side_setback := 0.0
var rear_setback := 0.0
var corner_side_setback := 0.0
var primary_frontage_segment_index := -1
var primary_road_edge_id: StringName
var primary_logical_road_id: StringName
var frontage_direction := Vector2.ZERO
var orientation_degrees := 0.0
var base_elevation := 0.0
var floor_count := 1
var floor_height := 3.2
var height := 3.2
var gross_floor_area := 0.0
var massing_kind: StringName = MASSING_EXTRUSION
var roof_kind: StringName = ROOF_FLAT
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


func set_footprint(value: PackedVector2Array) -> void:
	footprint = value.duplicate()
	refresh_metrics()


func refresh_metrics(parent_parcel_area := 0.0) -> void:
	world_bounds = FoundationBlockRecord._bounds_for_boundary(footprint)
	footprint_area = absf(FoundationBlockRecord._signed_area(footprint))
	footprint_perimeter = 0.0
	for index in range(footprint.size()):
		footprint_perimeter += footprint[index].distance_to(footprint[(index + 1) % footprint.size()])
	centroid = FoundationBlockRecord._polygon_centroid(footprint)
	label_point = FoundationBlockRecord._stable_interior_point(footprint, centroid)
	if parent_parcel_area > 0.000001:
		coverage_ratio = footprint_area / parent_parcel_area
	gross_floor_area = footprint_area * float(floor_count)


func refresh_massing() -> void:
	height = float(floor_count) * floor_height
	gross_floor_area = footprint_area * float(floor_count)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_footprint: Array[Dictionary] = []
	for point in footprint:
		serialized_footprint.append({"x": point.x, "y": point.y})
	data["record_kind"] = String(RECORD_KIND)
	data["building_format_version"] = BUILDING_FORMAT_VERSION
	data["parent_block_id"] = String(parent_block_id)
	data["footprint"] = serialized_footprint
	data["footprint_area"] = footprint_area
	data["footprint_perimeter"] = footprint_perimeter
	data["centroid"] = {"x": centroid.x, "y": centroid.y}
	data["label_point"] = {"x": label_point.x, "y": label_point.y}
	data["coverage_ratio"] = coverage_ratio
	data["target_coverage_ratio"] = target_coverage_ratio
	data["frontage_span"] = frontage_span
	data["footprint_depth"] = footprint_depth
	data["footprint_aspect_ratio"] = footprint_aspect_ratio
	data["long_form"] = long_form
	data["front_setback"] = front_setback
	data["side_setback"] = side_setback
	data["rear_setback"] = rear_setback
	data["corner_side_setback"] = corner_side_setback
	data["primary_frontage_segment_index"] = primary_frontage_segment_index
	data["primary_road_edge_id"] = String(primary_road_edge_id)
	data["primary_logical_road_id"] = String(primary_logical_road_id)
	data["frontage_direction"] = {"x": frontage_direction.x, "y": frontage_direction.y}
	data["orientation_degrees"] = orientation_degrees
	data["base_elevation"] = base_elevation
	data["floor_count"] = floor_count
	data["floor_height"] = floor_height
	data["height"] = height
	data["gross_floor_area"] = gross_floor_area
	data["massing_kind"] = String(massing_kind)
	data["roof_kind"] = String(roof_kind)
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationBuildingRecord:
	var footprint_points := PackedVector2Array()
	for point_data: Dictionary in data.get("footprint", []):
		footprint_points.append(Vector2(
			float(point_data.get("x", 0.0)),
			float(point_data.get("y", 0.0))
		))
	var building := FoundationBuildingRecord.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("parent_id", "")),
		StringName(data.get("parent_block_id", "")),
		footprint_points
	)
	FoundationSpatialRecord.apply_serialized_fields(building, data)
	building.entity_type = ENTITY_TYPE
	building.layer_type = LAYER_TYPE
	building.parent_block_id = StringName(data.get("parent_block_id", ""))
	building.footprint_area = float(data.get("footprint_area", building.footprint_area))
	building.footprint_perimeter = float(data.get("footprint_perimeter", building.footprint_perimeter))
	var centroid_data: Dictionary = data.get("centroid", {})
	building.centroid = Vector2(
		float(centroid_data.get("x", building.centroid.x)),
		float(centroid_data.get("y", building.centroid.y))
	)
	var label_data: Dictionary = data.get("label_point", {})
	building.label_point = Vector2(
		float(label_data.get("x", building.label_point.x)),
		float(label_data.get("y", building.label_point.y))
	)
	building.coverage_ratio = float(data.get("coverage_ratio", 0.0))
	building.target_coverage_ratio = float(data.get("target_coverage_ratio", building.coverage_ratio))
	building.frontage_span = float(data.get("frontage_span", 0.0))
	building.footprint_depth = float(data.get("footprint_depth", 0.0))
	building.footprint_aspect_ratio = float(data.get("footprint_aspect_ratio", 0.0))
	building.long_form = bool(data.get("long_form", false))
	building.front_setback = float(data.get("front_setback", 0.0))
	building.side_setback = float(data.get("side_setback", 0.0))
	building.rear_setback = float(data.get("rear_setback", 0.0))
	building.corner_side_setback = float(data.get("corner_side_setback", 0.0))
	building.primary_frontage_segment_index = int(data.get("primary_frontage_segment_index", -1))
	building.primary_road_edge_id = StringName(data.get("primary_road_edge_id", ""))
	building.primary_logical_road_id = StringName(data.get("primary_logical_road_id", ""))
	var direction_data: Dictionary = data.get("frontage_direction", {})
	building.frontage_direction = Vector2(
		float(direction_data.get("x", 0.0)),
		float(direction_data.get("y", 0.0))
	)
	building.orientation_degrees = float(data.get("orientation_degrees", 0.0))
	building.base_elevation = float(data.get("base_elevation", 0.0))
	building.floor_count = int(data.get("floor_count", 1))
	building.floor_height = float(data.get("floor_height", 3.2))
	building.height = float(data.get("height", float(building.floor_count) * building.floor_height))
	building.gross_floor_area = float(data.get("gross_floor_area", building.footprint_area * float(building.floor_count)))
	building.massing_kind = StringName(data.get("massing_kind", String(MASSING_EXTRUSION)))
	building.roof_kind = StringName(data.get("roof_kind", String(ROOF_FLAT)))
	building.validation_state = StringName(data.get("validation_state", String(VALID)))
	building.validation_messages = PackedStringArray(data.get("validation_messages", []))
	return building
