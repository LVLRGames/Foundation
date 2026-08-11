class_name FoundationBuildingValidator
extends RefCounted

## Deterministic parent, geometry, provenance, coverage, and massing validation.


static func validate(
	world: FoundationWorldData,
	profile: FoundationBuildingGenerationProfile = null,
	apply_record_state := true
) -> Array[FoundationBuildingValidationIssue]:
	var active_profile := profile if profile != null else FoundationBuildingGenerationProfile.new()
	var issues: Array[FoundationBuildingValidationIssue] = []
	for building in world.get_buildings():
		if apply_record_state and building.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			building.validation_state = FoundationBuildingRecord.VALID
			building.validation_messages.clear()
		var parcel := world.get_record(building.parent_id) as FoundationParcelRecord
		if parcel == null:
			_add_issue(issues, building, &"missing_parent_parcel", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building parent parcel is missing.")
			continue
		if building.parent_block_id != parcel.parent_id:
			_add_issue(issues, building, &"parent_block_mismatch", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building parent-block identity does not match its parcel.")
		if not parcel.buildable or parcel.access_state != FoundationParcelRecord.ACCESS_DIRECT:
			_add_issue(issues, building, &"building_on_unbuildable_parcel", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building is attached to a parcel without direct buildable access.")
		var geometry_valid := true
		if building.footprint.size() < 3 or building.footprint_area <= active_profile.geometric_epsilon:
			_add_issue(issues, building, &"degenerate_footprint", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building footprint is degenerate.")
			geometry_valid = false
		elif not FoundationParcelSubdivider.is_simple_polygon(building.footprint, active_profile.geometric_epsilon):
			_add_issue(issues, building, &"self_intersection", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building footprint self-intersects.")
			geometry_valid = false
		if geometry_valid:
			var inside_area := _intersection_area(building.footprint, parcel.boundary)
			if absf(inside_area - building.footprint_area) > _area_tolerance(parcel, active_profile):
				_add_issue(issues, building, &"outside_parent_parcel", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building footprint extends outside its parent parcel.", {"inside_area": inside_area})
		if building.footprint_area < active_profile.minimum_footprint_area:
			_add_issue(issues, building, &"below_minimum_footprint", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building footprint is below the configured minimum area.")
		if building.coverage_ratio > active_profile.maximum_coverage_ratio + active_profile.geometric_epsilon:
			_add_issue(issues, building, &"excessive_coverage", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building exceeds maximum parcel coverage.")
		if building.floor_count <= 0 or building.floor_height <= 0.0 or building.height <= 0.0:
			_add_issue(issues, building, &"invalid_massing_height", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building massing height and floors must be positive.")
		elif not is_equal_approx(building.height, float(building.floor_count) * building.floor_height):
			_add_issue(issues, building, &"inconsistent_massing_height", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building height does not match floor count and floor height.")
		if building.height > active_profile.maximum_building_height + active_profile.geometric_epsilon:
			_add_issue(issues, building, &"excessive_massing_height", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building exceeds maximum primitive massing height.")
		if building.primary_frontage_segment_index < 0 or String(building.primary_road_edge_id).is_empty():
			_add_issue(issues, building, &"missing_frontage_provenance", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building lacks primary parcel-frontage provenance.")
		elif not _frontage_matches(parcel, building):
			_add_issue(issues, building, &"frontage_provenance_mismatch", FoundationBuildingValidationIssue.SEVERITY_ERROR, "Building frontage provenance does not match its parcel.")

	issues.sort_custom(FoundationBuildingValidationIssue.less)
	if apply_record_state:
		_apply_states(world, issues)
	return issues


static func _frontage_matches(
	parcel: FoundationParcelRecord,
	building: FoundationBuildingRecord
) -> bool:
	for reference in parcel.frontage_references:
		if reference.parcel_boundary_segment_index != building.primary_frontage_segment_index:
			continue
		if reference.road_edge_id != building.primary_road_edge_id:
			continue
		if not String(building.primary_logical_road_id).is_empty() and reference.logical_road_id != building.primary_logical_road_id:
			continue
		return true
	return false


static func _add_issue(
	issues: Array[FoundationBuildingValidationIssue],
	building: FoundationBuildingRecord,
	kind: StringName,
	severity: StringName,
	message: String,
	details: Dictionary = {}
) -> void:
	issues.append(FoundationBuildingValidationIssue.new(
		kind, severity, building.stable_id, building.parent_id, message, details
	))


static func _apply_states(
	world: FoundationWorldData,
	issues: Array[FoundationBuildingValidationIssue]
) -> void:
	for issue in issues:
		if String(issue.building_id).is_empty():
			continue
		var building := world.get_record(issue.building_id) as FoundationBuildingRecord
		if building == null or building.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
			continue
		building.validation_messages.append(issue.message)
		if issue.severity == FoundationBuildingValidationIssue.SEVERITY_ERROR:
			building.validation_state = FoundationBuildingRecord.INVALID
		elif building.validation_state == FoundationBuildingRecord.VALID:
			building.validation_state = FoundationBuildingRecord.WARNING


static func _intersection_area(first: PackedVector2Array, second: PackedVector2Array) -> float:
	var area := 0.0
	for polygon in Geometry2D.intersect_polygons(first, second):
		area += absf(FoundationBlockRecord._signed_area(polygon))
	return area


static func _area_tolerance(
	parcel: FoundationParcelRecord,
	profile: FoundationBuildingGenerationProfile
) -> float:
	return maxf(
		profile.point_quantization * profile.point_quantization * 8.0,
		parcel.area * 0.00001
	)
