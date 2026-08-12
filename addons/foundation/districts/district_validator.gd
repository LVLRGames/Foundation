class_name FoundationDistrictValidator
extends RefCounted

## Deterministic district coverage, lineage, policy, and metric validation.


static func validate(
	world: FoundationWorldData,
	profile: FoundationDistrictGenerationProfile = null,
	apply_record_state := true
) -> Array[FoundationDistrictValidationIssue]:
	var active_profile := profile if profile != null else FoundationDistrictGenerationProfile.new()
	var issues: Array[FoundationDistrictValidationIssue] = []
	var claims: Dictionary = {}
	var eligible: Dictionary = {}
	for block in world.get_blocks():
		if block.validation_state != FoundationBlockRecord.INVALID and block.outer_boundary.size() >= 3 and block.area > active_profile.geometric_tolerance:
			eligible[block.stable_id] = block
	for district in world.get_districts():
		if apply_record_state and district.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			district.validation_state = FoundationDistrictRecord.VALID
			district.validation_messages.clear()
		_validate_record(world, district, eligible, claims, active_profile, issues)
	for block_id in eligible:
		if not claims.has(block_id):
			_add_issue(issues, null, &"unassigned_eligible_block", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Eligible block is not assigned to any district.", block_id)
	issues.sort_custom(FoundationDistrictValidationIssue.less)
	if apply_record_state:
		_apply_states(world, issues)
	return issues


static func _validate_record(
	world: FoundationWorldData,
	district: FoundationDistrictRecord,
	eligible: Dictionary,
	claims: Dictionary,
	profile: FoundationDistrictGenerationProfile,
	issues: Array[FoundationDistrictValidationIssue]
) -> void:
	if district.member_block_ids.is_empty():
		_add_issue(issues, district, &"empty_district", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District has no member blocks.")
		return
	var local_claims: Dictionary = {}
	var member_blocks: Array[FoundationBlockRecord] = []
	for block_id in district.member_block_ids:
		if local_claims.has(block_id):
			_add_issue(issues, district, &"duplicate_member_block", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District repeats a member block.", block_id)
			continue
		local_claims[block_id] = true
		var block := world.get_record(block_id) as FoundationBlockRecord
		if block == null:
			_add_issue(issues, district, &"missing_member_block", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District member block is missing.", block_id)
			continue
		member_blocks.append(block)
		if claims.has(block_id):
			_add_issue(issues, district, &"overlapping_block_membership", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Block is claimed by more than one district.", block_id, {"other_district_id": String(claims[block_id])})
		else:
			claims[block_id] = district.stable_id
		if not eligible.has(block_id):
			_add_issue(issues, district, &"ineligible_member_block", FoundationDistrictValidationIssue.SEVERITY_WARNING, "District claims a block that is not currently eligible.", block_id)
	if district.member_block_ids != _sorted_unique_names(district.member_block_ids):
		_add_issue(issues, district, &"member_order_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District member IDs must be sorted and unique.")
	if district.member_block_ids.size() > profile.maximum_blocks_per_district:
		_add_issue(issues, district, &"block_count_cap", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District exceeds the configured block-count cap.")
	if district.total_area > profile.maximum_district_area + profile.geometric_tolerance:
		_add_issue(issues, district, &"district_area_cap", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District exceeds the configured area cap.")
	_validate_geometry(district, member_blocks, profile, issues)
	_validate_policy(world, district, profile, issues)
	_validate_assignments(world, district, local_claims, issues)
	_validate_access_metrics(world, district, member_blocks, profile, issues)
	if member_blocks.size() > 1 and not district.allows_disconnected_components and not _is_contiguous(member_blocks, profile.geometric_tolerance):
		_add_issue(issues, district, &"non_contiguous_membership", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District member blocks are not boundary-contiguous.")


static func _validate_geometry(
	district: FoundationDistrictRecord,
	blocks: Array[FoundationBlockRecord],
	profile: FoundationDistrictGenerationProfile,
	issues: Array[FoundationDistrictValidationIssue]
) -> void:
	var expected_area := 0.0
	var expected_bounds := Rect2()
	var initialized := false
	var weighted_centroid := Vector2.ZERO
	for block in blocks:
		expected_area += block.area
		weighted_centroid += block.centroid * block.area
		expected_bounds = block.world_bounds if not initialized else expected_bounds.merge(block.world_bounds)
		initialized = true
	var expected_components: Array[String] = []
	for component in FoundationDistrictGenerator.boundary_components_for_blocks(blocks, profile.geometric_tolerance):
		expected_components.append(_boundary_key(component, profile.geometric_tolerance))
	expected_components.sort()
	var actual_components: Array[String] = []
	for component in district.boundary_components:
		actual_components.append(_boundary_key(component, profile.geometric_tolerance))
	actual_components.sort()
	if actual_components != expected_components:
		_add_issue(issues, district, &"boundary_components_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District boundary components do not match complete member-block coverage.")
	var tolerance := maxf(profile.geometric_tolerance * profile.geometric_tolerance * 8.0, expected_area * 0.00001)
	if absf(district.total_area - expected_area) > tolerance:
		_add_issue(issues, district, &"district_area_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Stored district area does not match member blocks.", &"", {"expected": expected_area, "actual": district.total_area})
	if initialized and not _rect_equal(district.world_bounds, expected_bounds, profile.geometric_tolerance):
		_add_issue(issues, district, &"district_bounds_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Stored district bounds do not match member blocks.")
	if expected_area > 0.000001:
		var expected_centroid := weighted_centroid / expected_area
		if district.centroid.distance_to(expected_centroid) > profile.geometric_tolerance:
			_add_issue(issues, district, &"district_centroid_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Stored district centroid does not match member blocks.")


static func _validate_policy(
	world: FoundationWorldData,
	district: FoundationDistrictRecord,
	profile: FoundationDistrictGenerationProfile,
	issues: Array[FoundationDistrictValidationIssue]
) -> void:
	if not FoundationDistrictRecord.builtin_characters().has(district.character_key):
		_add_issue(issues, district, &"unsupported_character", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District character is unsupported by the active policy.")
	if not FoundationDistrictRecord.builtin_uses().has(district.primary_use):
		_add_issue(issues, district, &"unsupported_primary_use", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District primary use is unsupported by the active policy.")
	if not district.allowed_uses.has(district.primary_use):
		_add_issue(issues, district, &"primary_use_not_allowed", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District primary use is absent from its allowed-use policy.")
	if district.allowed_uses != _sorted_unique_names(district.allowed_uses):
		_add_issue(issues, district, &"allowed_use_order_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District allowed uses must be sorted and unique.")
	for use_key in district.allowed_uses:
		if not FoundationDistrictRecord.builtin_uses().has(use_key):
			_add_issue(issues, district, &"unsupported_allowed_use", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District allowed-use policy contains an unsupported value.")
	for value in [district.target_density, district.target_intensity, district.open_space_target, district.mixed_use_ratio, district.access_score]:
		if value < 0.0 or value > 1.0:
			_add_issue(issues, district, &"invalid_policy_range", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District normalized policy values must remain in [0, 1].")
			break
	if district.minimum_height < 0.0 or district.maximum_height < district.minimum_height:
		_add_issue(issues, district, &"invalid_height_policy", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District height policy is invalid.")
	if not String(district.source_anchor_id).is_empty() and not (world.get_record(district.source_anchor_id) is FoundationCityAnchor):
		_add_issue(issues, district, &"missing_source_anchor", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District source anchor does not exist.")
	for pattern_id in district.source_pattern_ids:
		if not (world.get_record(pattern_id) is FoundationRoadPatternArea):
			_add_issue(issues, district, &"missing_source_pattern", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District source road-pattern area does not exist.")
	if district.source_pattern_ids != _sorted_unique_names(district.source_pattern_ids):
		_add_issue(issues, district, &"source_pattern_order_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District source-pattern identities must be sorted and unique.")
	if String(profile.policy_id).is_empty():
		_add_issue(issues, district, &"missing_policy_identity", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District generation policy identity is empty.")


static func _validate_assignments(
	world: FoundationWorldData,
	district: FoundationDistrictRecord,
	member_ids: Dictionary,
	issues: Array[FoundationDistrictValidationIssue]
) -> void:
	if district.assignments.size() != member_ids.size():
		_add_issue(issues, district, &"incomplete_member_assignments", FoundationDistrictValidationIssue.SEVERITY_ERROR, "District must contain exactly one assignment per member block.")
	var seen: Dictionary = {}
	var previous_block := ""
	for assignment in district.assignments:
		if assignment.district_id != district.stable_id:
			_add_issue(issues, district, &"assignment_district_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Member assignment references the wrong district.", assignment.block_id)
		if not member_ids.has(assignment.block_id):
			_add_issue(issues, district, &"assignment_block_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Member assignment references a non-member block.", assignment.block_id)
		if seen.has(assignment.block_id):
			_add_issue(issues, district, &"duplicate_member_assignment", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Member block has duplicate assignments.", assignment.block_id)
		seen[assignment.block_id] = true
		if not previous_block.is_empty() and previous_block >= String(assignment.block_id):
			_add_issue(issues, district, &"assignment_order_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Member assignments must use stable block order.")
		previous_block = String(assignment.block_id)
		if String(assignment.assignment_id).is_empty():
			_add_issue(issues, district, &"missing_assignment_identity", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Member assignment identity is empty.", assignment.block_id)
		if not district.allowed_uses.has(assignment.primary_use) or not assignment.allowed_uses.has(assignment.primary_use):
			_add_issue(issues, district, &"assignment_use_not_allowed", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Member primary use is outside district/member allowed-use policy.", assignment.block_id)
		if assignment.allowed_uses != _sorted_unique_names(assignment.allowed_uses):
			_add_issue(issues, district, &"assignment_allowed_use_order_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Member allowed uses must be sorted and unique.", assignment.block_id)
		for use_key in assignment.allowed_uses:
			if not FoundationDistrictRecord.builtin_uses().has(use_key) or not district.allowed_uses.has(use_key):
				_add_issue(issues, district, &"unsupported_assignment_use", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Member allowed-use policy is outside the district policy.", assignment.block_id)
				break
		if assignment.suitability_score < 0.0 or assignment.suitability_score > 1.0 or assignment.target_density < 0.0 or assignment.target_density > 1.0 or assignment.target_intensity < 0.0 or assignment.target_intensity > 1.0:
			_add_issue(issues, district, &"invalid_assignment_range", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Member assignment score and targets must remain in [0, 1].", assignment.block_id)
		var expected_id := FoundationSpatialId.make(
			world.metadata.seed, district.source_version, world.metadata.content_pack_version,
			&"district_assignment", district.stable_id, String(assignment.block_id)
		)
		if district.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED and assignment.assignment_id != expected_id:
			_add_issue(issues, district, &"assignment_identity_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Generated assignment identity does not match district and block lineage.", assignment.block_id)


static func _validate_access_metrics(
	world: FoundationWorldData,
	district: FoundationDistrictRecord,
	blocks: Array[FoundationBlockRecord],
	profile: FoundationDistrictGenerationProfile,
	issues: Array[FoundationDistrictValidationIssue]
) -> void:
	var expected_exposure := FoundationDistrictGenerator._road_exposure(world, blocks)
	if not _number_dictionary_equal(district.road_class_exposure, expected_exposure, profile.geometric_tolerance):
		_add_issue(issues, district, &"road_exposure_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Stored road-class exposure does not match member-block provenance.")
	var expected_access := FoundationDistrictGenerator._access_score(expected_exposure)
	if absf(district.access_score - expected_access) > profile.geometric_tolerance:
		_add_issue(issues, district, &"access_score_mismatch", FoundationDistrictValidationIssue.SEVERITY_ERROR, "Stored district access score does not match road exposure.")


static func _is_contiguous(blocks: Array[FoundationBlockRecord], tolerance: float) -> bool:
	var visited: Dictionary = {blocks[0].stable_id: true}
	var queue: Array[FoundationBlockRecord] = [blocks[0]]
	while not queue.is_empty():
		var current := queue.pop_front() as FoundationBlockRecord
		for candidate in blocks:
			if visited.has(candidate.stable_id):
				continue
			if FoundationDistrictGenerator._shared_boundary_length(current.outer_boundary, candidate.outer_boundary, tolerance) > tolerance:
				visited[candidate.stable_id] = true
				queue.append(candidate)
	return visited.size() == blocks.size()


static func _add_issue(
	issues: Array[FoundationDistrictValidationIssue],
	district: FoundationDistrictRecord,
	kind: StringName,
	severity: StringName,
	message: String,
	block_id: StringName = &"",
	details: Dictionary = {}
) -> void:
	issues.append(FoundationDistrictValidationIssue.new(
		kind, severity, district.stable_id if district != null else &"", block_id, message, details
	))


static func _apply_states(world: FoundationWorldData, issues: Array[FoundationDistrictValidationIssue]) -> void:
	for issue in issues:
		if String(issue.district_id).is_empty():
			continue
		var district := world.get_record(issue.district_id) as FoundationDistrictRecord
		if district == null or district.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
			continue
		district.validation_messages.append(issue.message)
		if issue.severity == FoundationDistrictValidationIssue.SEVERITY_ERROR:
			district.validation_state = FoundationDistrictRecord.INVALID
		elif district.validation_state == FoundationDistrictRecord.VALID:
			district.validation_state = FoundationDistrictRecord.WARNING


static func _sorted_unique_names(values: Array[StringName]) -> Array[StringName]:
	var unique: Dictionary = {}
	for value in values:
		unique[value] = true
	var result: Array[StringName] = []
	for value: StringName in unique:
		result.append(value)
	result.sort_custom(FoundationDistrictRecord._string_name_less)
	return result


static func _boundary_key(boundary: PackedVector2Array, quantization: float) -> String:
	var values := PackedStringArray()
	for point in boundary:
		values.append("%d,%d" % [roundi(point.x / quantization), roundi(point.y / quantization)])
	return ";".join(values)


static func _rect_equal(first: Rect2, second: Rect2, tolerance: float) -> bool:
	return first.position.distance_to(second.position) <= tolerance and first.size.distance_to(second.size) <= tolerance


static func _number_dictionary_equal(first: Dictionary, second: Dictionary, tolerance: float) -> bool:
	if first.size() != second.size():
		return false
	for key in second:
		if not first.has(key) or absf(float(first[key]) - float(second[key])) > tolerance:
			return false
	return true
