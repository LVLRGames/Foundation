class_name FoundationDistrictMemberAssignment
extends RefCounted

## Compact deterministic policy assignment for one member block.

const FORMAT_VERSION := 1

var assignment_id: StringName
var district_id: StringName
var block_id: StringName
var primary_use: StringName
var allowed_uses: Array[StringName] = []
var suitability_score := 0.0
var target_density := 0.0
var target_intensity := 0.0
var parcel_use_overrides: Dictionary = {}
var building_use_overrides: Dictionary = {}
var evidence: Dictionary = {}


func _init(
	p_assignment_id: StringName = &"",
	p_district_id: StringName = &"",
	p_block_id: StringName = &"",
	p_primary_use: StringName = &""
) -> void:
	assignment_id = p_assignment_id
	district_id = p_district_id
	block_id = p_block_id
	primary_use = p_primary_use


func to_dict() -> Dictionary:
	var serialized_uses: Array[String] = []
	for use_key in allowed_uses:
		serialized_uses.append(String(use_key))
	return {
		"format_version": FORMAT_VERSION,
		"assignment_id": String(assignment_id),
		"district_id": String(district_id),
		"block_id": String(block_id),
		"primary_use": String(primary_use),
		"allowed_uses": serialized_uses,
		"suitability_score": suitability_score,
		"target_density": target_density,
		"target_intensity": target_intensity,
		"parcel_use_overrides": parcel_use_overrides.duplicate(true),
		"building_use_overrides": building_use_overrides.duplicate(true),
		"evidence": evidence.duplicate(true),
	}


static func from_dict(data: Dictionary) -> FoundationDistrictMemberAssignment:
	var assignment := FoundationDistrictMemberAssignment.new(
		StringName(data.get("assignment_id", "")),
		StringName(data.get("district_id", "")),
		StringName(data.get("block_id", "")),
		StringName(data.get("primary_use", ""))
	)
	for use_value: String in data.get("allowed_uses", []):
		assignment.allowed_uses.append(StringName(use_value))
	assignment.allowed_uses.sort_custom(_string_name_less)
	assignment.suitability_score = float(data.get("suitability_score", 0.0))
	assignment.target_density = float(data.get("target_density", 0.0))
	assignment.target_intensity = float(data.get("target_intensity", 0.0))
	assignment.parcel_use_overrides = data.get("parcel_use_overrides", {}).duplicate(true)
	assignment.building_use_overrides = data.get("building_use_overrides", {}).duplicate(true)
	assignment.evidence = data.get("evidence", {}).duplicate(true)
	return assignment


static func less(a: FoundationDistrictMemberAssignment, b: FoundationDistrictMemberAssignment) -> bool:
	if a.block_id != b.block_id:
		return String(a.block_id) < String(b.block_id)
	return String(a.assignment_id) < String(b.assignment_id)


static func _string_name_less(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
