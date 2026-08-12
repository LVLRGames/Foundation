class_name FoundationAuthoringPolicy
extends RefCounted

## Explicit versioned Phase 11 safety, cap, and dependency policy.

const FORMAT_VERSION := 1
const MANDATORY_PROTECTED_FIELDS := ["stable_id", "record_kind", "entity_type", "layer_type", "parent_id"]

var policy_id: StringName = &"foundation_authoring_policy_v1"
var authoring_version := 1
var maximum_history_commands := 128
var maximum_active_overrides := 8192
var reject_base_drift := true
var protected_fields := PackedStringArray(["stable_id", "record_kind", "entity_type", "layer_type", "parent_id"])


func supported_layers() -> Array[StringName]:
	return [
		FoundationWorldData.CITY_ANCHOR_LAYER,
		FoundationWorldData.ROAD_PATTERN_LAYER,
		FoundationWorldData.ROAD_NODE_LAYER,
		FoundationWorldData.ROAD_EDGE_LAYER,
		FoundationWorldData.LOGICAL_ROAD_LAYER,
		FoundationWorldData.ROAD_INTERSECTION_LAYER,
		FoundationWorldData.BLOCK_LAYER,
		FoundationWorldData.PARCEL_LAYER,
		FoundationWorldData.BUILDING_LAYER,
		FoundationWorldData.FACADE_LAYER,
		FoundationWorldData.DISTRICT_LAYER,
		FoundationWorldData.PARKING_FACILITY_LAYER,
		FoundationWorldData.PUBLIC_FEATURE_LAYER,
	]


func supported_record_kinds() -> Array[StringName]:
	return [
		FoundationCityAnchor.RECORD_KIND,
		FoundationRoadPatternArea.RECORD_KIND,
		FoundationRoadNode.RECORD_KIND,
		FoundationRoadEdge.RECORD_KIND,
		FoundationLogicalRoad.RECORD_KIND,
		FoundationIntersectionRecord.RECORD_KIND,
		FoundationBlockRecord.RECORD_KIND,
		FoundationParcelRecord.RECORD_KIND,
		FoundationBuildingRecord.RECORD_KIND,
		FoundationFacadeRecord.RECORD_KIND,
		FoundationDistrictRecord.RECORD_KIND,
		FoundationParkingFacilityRecord.RECORD_KIND,
		FoundationPublicFeatureRecord.RECORD_KIND,
	]


func downstream_layers(layer_type: StringName) -> Array[StringName]:
	var order := supported_layers()
	var index := order.find(layer_type)
	return order.slice(index + 1) if index >= 0 else []


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(policy_id).is_empty() or authoring_version <= 0:
		errors.append("Authoring policy identity/version must be defined.")
	if maximum_history_commands <= 0 or maximum_active_overrides <= 0:
		errors.append("Authoring history and override caps must be positive.")
	for field in MANDATORY_PROTECTED_FIELDS:
		if field not in protected_fields:
			errors.append("Authoring policy must protect '%s'." % field)
	return errors


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"policy_id": String(policy_id),
		"authoring_version": authoring_version,
		"maximum_history_commands": maximum_history_commands,
		"maximum_active_overrides": maximum_active_overrides,
		"reject_base_drift": reject_base_drift,
		"protected_fields": Array(protected_fields),
		"supported_layers": _strings(supported_layers()),
		"supported_record_kinds": _strings(supported_record_kinds()),
	}


static func from_dict(data: Dictionary) -> FoundationAuthoringPolicy:
	var policy := FoundationAuthoringPolicy.new()
	policy.policy_id = StringName(data.get("policy_id", "foundation_authoring_policy_v1"))
	policy.authoring_version = int(data.get("authoring_version", 1))
	policy.maximum_history_commands = int(data.get("maximum_history_commands", 128))
	policy.maximum_active_overrides = int(data.get("maximum_active_overrides", 8192))
	policy.reject_base_drift = bool(data.get("reject_base_drift", true))
	policy.protected_fields = PackedStringArray(data.get("protected_fields", ["stable_id", "record_kind", "entity_type", "layer_type", "parent_id"]))
	return policy


static func _strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result
