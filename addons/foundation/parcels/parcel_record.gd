class_name FoundationParcelRecord
extends FoundationSpatialRecord

## Canonical abstract parcel with road-frontage provenance. Owns no use or building data.

const PARCEL_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"parcel"
const ENTITY_TYPE: StringName = &"parcel"
const LAYER_TYPE: StringName = &"parcels"

const KIND_STANDARD: StringName = &"standard"
const KIND_CORNER: StringName = &"corner"
const KIND_FLAG_ACCESS: StringName = &"flag_access"
const KIND_REMAINDER: StringName = &"remainder"

const ACCESS_DIRECT: StringName = &"direct"
const ACCESS_REQUIRED: StringName = &"access_required"
const ACCESS_NONE: StringName = &"none"

const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var boundary := PackedVector2Array()
var parcel_kind: StringName = KIND_STANDARD
var buildable := true
var access_state: StringName = ACCESS_DIRECT
var frontage_references: Array[FoundationParcelFrontageReference] = []
var frontage_road_edge_ids: Array[StringName] = []
var frontage_logical_road_ids: Array[StringName] = []
var primary_frontage_index := -1
var frontage_length := 0.0
var area := 0.0
var perimeter := 0.0
var centroid := Vector2.ZERO
var label_point := Vector2.ZERO
var approximate_frontage_width := 0.0
var approximate_depth := 0.0
var validation_state: StringName = VALID
var validation_messages := PackedStringArray()


func _init(
	p_stable_id: StringName = &"",
	p_parent_block_id: StringName = &"",
	p_boundary := PackedVector2Array(),
	p_frontage_references: Array[FoundationParcelFrontageReference] = []
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, FoundationBlockRecord._bounds_for_boundary(p_boundary), p_parent_block_id)
	boundary = p_boundary.duplicate()
	frontage_references = p_frontage_references.duplicate()
	refresh_metrics()
	refresh_frontage()


func set_boundary(value: PackedVector2Array) -> void:
	boundary = value.duplicate()
	refresh_metrics()


func set_frontage_references(value: Array[FoundationParcelFrontageReference]) -> void:
	frontage_references = value.duplicate()
	refresh_frontage()


func refresh_metrics() -> void:
	world_bounds = FoundationBlockRecord._bounds_for_boundary(boundary)
	area = absf(FoundationBlockRecord._signed_area(boundary))
	perimeter = 0.0
	for index in range(boundary.size()):
		perimeter += boundary[index].distance_to(boundary[(index + 1) % boundary.size()])
	centroid = FoundationBlockRecord._polygon_centroid(boundary)
	label_point = FoundationBlockRecord._stable_interior_point(boundary, centroid)


func refresh_frontage() -> void:
	frontage_references.sort_custom(FoundationParcelFrontageReference.less)
	frontage_length = 0.0
	var road_ids: Dictionary = {}
	var logical_ids: Dictionary = {}
	for reference in frontage_references:
		frontage_length += reference.frontage_length
		if not String(reference.road_edge_id).is_empty():
			road_ids[reference.road_edge_id] = true
		if not String(reference.logical_road_id).is_empty():
			logical_ids[reference.logical_road_id] = true
	frontage_road_edge_ids.clear()
	for road_id: StringName in road_ids:
		frontage_road_edge_ids.append(road_id)
	frontage_road_edge_ids.sort_custom(_string_name_less)
	frontage_logical_road_ids.clear()
	for logical_id: StringName in logical_ids:
		frontage_logical_road_ids.append(logical_id)
	frontage_logical_road_ids.sort_custom(_string_name_less)
	approximate_frontage_width = frontage_length
	approximate_depth = area / frontage_length if frontage_length > 0.000001 else 0.0


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_boundary: Array[Dictionary] = []
	for point in boundary:
		serialized_boundary.append({"x": point.x, "y": point.y})
	var serialized_frontage: Array[Dictionary] = []
	for reference in frontage_references:
		serialized_frontage.append(reference.to_dict())
	var serialized_road_ids: Array[String] = []
	for road_id in frontage_road_edge_ids:
		serialized_road_ids.append(String(road_id))
	var serialized_logical_ids: Array[String] = []
	for logical_id in frontage_logical_road_ids:
		serialized_logical_ids.append(String(logical_id))
	data["record_kind"] = String(RECORD_KIND)
	data["parcel_format_version"] = PARCEL_FORMAT_VERSION
	data["boundary"] = serialized_boundary
	data["parcel_kind"] = String(parcel_kind)
	data["buildable"] = buildable
	data["access_state"] = String(access_state)
	data["frontage_references"] = serialized_frontage
	data["frontage_road_edge_ids"] = serialized_road_ids
	data["frontage_logical_road_ids"] = serialized_logical_ids
	data["primary_frontage_index"] = primary_frontage_index
	data["frontage_length"] = frontage_length
	data["area"] = area
	data["perimeter"] = perimeter
	data["centroid"] = {"x": centroid.x, "y": centroid.y}
	data["label_point"] = {"x": label_point.x, "y": label_point.y}
	data["approximate_frontage_width"] = approximate_frontage_width
	data["approximate_depth"] = approximate_depth
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationParcelRecord:
	var points := PackedVector2Array()
	for point_data: Dictionary in data.get("boundary", []):
		points.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
	var references: Array[FoundationParcelFrontageReference] = []
	for reference_data: Dictionary in data.get("frontage_references", []):
		references.append(FoundationParcelFrontageReference.from_dict(reference_data))
	var parcel := FoundationParcelRecord.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("parent_id", "")),
		points,
		references
	)
	FoundationSpatialRecord.apply_serialized_fields(parcel, data)
	parcel.entity_type = ENTITY_TYPE
	parcel.layer_type = LAYER_TYPE
	parcel.parcel_kind = StringName(data.get("parcel_kind", String(KIND_STANDARD)))
	parcel.buildable = bool(data.get("buildable", true))
	parcel.access_state = StringName(data.get("access_state", String(ACCESS_DIRECT)))
	parcel.primary_frontage_index = int(data.get("primary_frontage_index", -1))
	parcel.refresh_frontage()
	parcel.area = float(data.get("area", parcel.area))
	parcel.perimeter = float(data.get("perimeter", parcel.perimeter))
	parcel.approximate_frontage_width = float(data.get("approximate_frontage_width", parcel.frontage_length))
	parcel.approximate_depth = float(data.get("approximate_depth", parcel.approximate_depth))
	var centroid_data: Dictionary = data.get("centroid", {})
	parcel.centroid = Vector2(float(centroid_data.get("x", parcel.centroid.x)), float(centroid_data.get("y", parcel.centroid.y)))
	var label_data: Dictionary = data.get("label_point", {})
	parcel.label_point = Vector2(float(label_data.get("x", parcel.label_point.x)), float(label_data.get("y", parcel.label_point.y)))
	parcel.validation_state = StringName(data.get("validation_state", String(VALID)))
	parcel.validation_messages = PackedStringArray(data.get("validation_messages", []))
	return parcel


static func _string_name_less(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
