class_name FoundationPublicFeatureRecord
extends FoundationSpatialRecord

## Canonical abstract public-space or civic-feature placement.

const PUBLIC_FEATURE_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"public_feature"
const ENTITY_TYPE: StringName = &"public_feature"
const LAYER_TYPE: StringName = &"public_features"

const KIND_PARK: StringName = &"park"
const KIND_PLAZA: StringName = &"plaza"
const KIND_PLAYGROUND: StringName = &"playground"
const KIND_TRANSIT_STOP: StringName = &"transit_stop"
const KIND_CIVIC_MARKER: StringName = &"civic_marker"
const KIND_LANDMARK_SITE: StringName = &"landmark_site"

const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var feature_kind: StringName = KIND_PARK
var parent_block_id: StringName
var district_id: StringName
var source_anchor_id: StringName
var footprint := PackedVector2Array()
var position := Vector2.ZERO
var area := 0.0
var orientation_degrees := 0.0
var base_elevation := 0.0
var access_road_edge_id: StringName
var access_logical_road_id: StringName
var capacity := 0
var service_radius := 0.0
var suitability_score := 0.0
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
	position = FoundationBlockRecord._polygon_centroid(footprint) if footprint.size() >= 3 else world_bounds.get_center()


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_footprint: Array[Dictionary] = []
	for point in footprint:
		serialized_footprint.append({"x": point.x, "y": point.y})
	data["record_kind"] = String(RECORD_KIND)
	data["public_feature_format_version"] = PUBLIC_FEATURE_FORMAT_VERSION
	data["feature_kind"] = String(feature_kind)
	data["parent_block_id"] = String(parent_block_id)
	data["district_id"] = String(district_id)
	data["source_anchor_id"] = String(source_anchor_id)
	data["footprint"] = serialized_footprint
	data["position"] = {"x": position.x, "y": position.y}
	data["area"] = area
	data["orientation_degrees"] = orientation_degrees
	data["base_elevation"] = base_elevation
	data["access_road_edge_id"] = String(access_road_edge_id)
	data["access_logical_road_id"] = String(access_logical_road_id)
	data["capacity"] = capacity
	data["service_radius"] = service_radius
	data["suitability_score"] = suitability_score
	data["suitability_evidence"] = suitability_evidence.duplicate(true)
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationPublicFeatureRecord:
	var points := PackedVector2Array()
	for point_data: Dictionary in data.get("footprint", []):
		points.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
	var record := FoundationPublicFeatureRecord.new(
		StringName(data.get("stable_id", "")), StringName(data.get("parent_id", "")),
		StringName(data.get("parent_block_id", "")), points
	)
	FoundationSpatialRecord.apply_serialized_fields(record, data)
	record.entity_type = ENTITY_TYPE
	record.layer_type = LAYER_TYPE
	record.feature_kind = StringName(data.get("feature_kind", String(KIND_PARK)))
	record.parent_block_id = StringName(data.get("parent_block_id", ""))
	record.district_id = StringName(data.get("district_id", ""))
	record.source_anchor_id = StringName(data.get("source_anchor_id", ""))
	record.orientation_degrees = float(data.get("orientation_degrees", 0.0))
	record.base_elevation = float(data.get("base_elevation", 0.0))
	record.access_road_edge_id = StringName(data.get("access_road_edge_id", ""))
	record.access_logical_road_id = StringName(data.get("access_logical_road_id", ""))
	record.capacity = int(data.get("capacity", 0))
	record.service_radius = float(data.get("service_radius", 0.0))
	record.suitability_score = float(data.get("suitability_score", 0.0))
	record.suitability_evidence = data.get("suitability_evidence", {}).duplicate(true)
	record.validation_state = StringName(data.get("validation_state", String(VALID)))
	record.validation_messages = PackedStringArray(data.get("validation_messages", []))
	record.refresh_metrics()
	return record


static func builtin_kinds() -> Array[StringName]:
	return [KIND_PARK, KIND_PLAZA, KIND_PLAYGROUND, KIND_TRANSIT_STOP, KIND_CIVIC_MARKER, KIND_LANDMARK_SITE]
