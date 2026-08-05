class_name FoundationParcelValidator
extends RefCounted

## Deterministic coverage, overlap, access, geometry, and provenance validation.


static func validate(
	world: FoundationWorldData,
	profile: FoundationParcelGenerationProfile = null,
	apply_record_state := true
) -> Array[FoundationParcelValidationIssue]:
	var active_profile := profile if profile != null else FoundationParcelGenerationProfile.new()
	var issues: Array[FoundationParcelValidationIssue] = []
	var parcels_by_block: Dictionary = {}
	for parcel in world.get_parcels():
		if apply_record_state and parcel.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			parcel.validation_state = FoundationParcelRecord.VALID
			parcel.validation_messages.clear()
		var block := world.get_record(parcel.parent_id) as FoundationBlockRecord
		if block == null:
			_add_issue(issues, parcel, &"missing_parent_block", FoundationParcelValidationIssue.SEVERITY_ERROR, "Parcel parent block is missing.")
			continue
		if not parcels_by_block.has(block.stable_id):
			parcels_by_block[block.stable_id] = []
		parcels_by_block[block.stable_id].append(parcel)
		var geometry_valid := true
		if parcel.boundary.size() < 3 or parcel.area <= active_profile.geometric_epsilon:
			_add_issue(issues, parcel, &"degenerate_polygon", FoundationParcelValidationIssue.SEVERITY_ERROR, "Parcel polygon is degenerate.")
			geometry_valid = false
		elif not FoundationParcelSubdivider.is_simple_polygon(parcel.boundary, active_profile.geometric_epsilon):
			_add_issue(issues, parcel, &"self_intersection", FoundationParcelValidationIssue.SEVERITY_ERROR, "Parcel polygon self-intersects.")
			geometry_valid = false
		if geometry_valid:
			var inside_area := _intersection_area(parcel.boundary, block.outer_boundary)
			if absf(inside_area - parcel.area) > _area_tolerance(block, active_profile):
				_add_issue(issues, parcel, &"outside_parent", FoundationParcelValidationIssue.SEVERITY_ERROR, "Parcel extends outside its parent block.", {"inside_area": inside_area})
		if parcel.area < active_profile.minimum_parcel_area and parcel.parcel_kind != FoundationParcelRecord.KIND_REMAINDER:
			_add_issue(issues, parcel, &"below_minimum_area", FoundationParcelValidationIssue.SEVERITY_WARNING, "Non-remainder parcel is below minimum area.")
		if parcel.area > active_profile.maximum_parcel_area and parcel.parcel_kind != FoundationParcelRecord.KIND_REMAINDER:
			_add_issue(issues, parcel, &"above_maximum_area", FoundationParcelValidationIssue.SEVERITY_WARNING, "Parcel exceeds maximum configured area.")
		if parcel.approximate_frontage_width < active_profile.minimum_frontage and parcel.parcel_kind != FoundationParcelRecord.KIND_REMAINDER:
			_add_issue(issues, parcel, &"insufficient_frontage", FoundationParcelValidationIssue.SEVERITY_WARNING, "Parcel is below minimum road frontage.")
		if parcel.buildable and parcel.approximate_frontage_width < active_profile.minimum_frontage:
			_add_issue(issues, parcel, &"buildable_landlocked", FoundationParcelValidationIssue.SEVERITY_ERROR, "Buildable parcel lacks required road frontage.")
		if parcel.approximate_depth < active_profile.minimum_depth and parcel.parcel_kind != FoundationParcelRecord.KIND_REMAINDER:
			_add_issue(issues, parcel, &"insufficient_depth", FoundationParcelValidationIssue.SEVERITY_WARNING, "Parcel is below minimum approximate depth.")
		if parcel.approximate_depth > active_profile.maximum_depth and parcel.parcel_kind != FoundationParcelRecord.KIND_REMAINDER:
			_add_issue(issues, parcel, &"excessive_depth", FoundationParcelValidationIssue.SEVERITY_WARNING, "Parcel exceeds maximum approximate depth.")
		for frontage in parcel.frontage_references:
			var edge := world.get_record(frontage.road_edge_id) as FoundationRoadEdge
			if edge == null:
				_add_issue(issues, parcel, &"missing_frontage_road", FoundationParcelValidationIssue.SEVERITY_ERROR, "Frontage source road is missing.")
			elif not String(frontage.logical_road_id).is_empty() and edge.logical_road_id != frontage.logical_road_id:
				_add_issue(issues, parcel, &"logical_road_mismatch", FoundationParcelValidationIssue.SEVERITY_ERROR, "Frontage logical-road provenance is inconsistent.")

	for block in world.get_blocks():
		var block_parcels: Array = parcels_by_block.get(block.stable_id, [])
		if block_parcels.is_empty():
			continue
		var parcel_area := 0.0
		for parcel: FoundationParcelRecord in block_parcels:
			parcel_area += parcel.area
		for first_index in range(block_parcels.size()):
			for second_index in range(first_index + 1, block_parcels.size()):
				var first := block_parcels[first_index] as FoundationParcelRecord
				var second := block_parcels[second_index] as FoundationParcelRecord
				if not first.world_bounds.intersects(second.world_bounds, true):
					continue
				var overlap := _intersection_area(first.boundary, second.boundary)
				if overlap > _area_tolerance(block, active_profile):
					_add_issue(issues, first, &"parcel_overlap", FoundationParcelValidationIssue.SEVERITY_ERROR, "Parcels overlap.", {"other_parcel_id": String(second.stable_id), "overlap_area": overlap})
		if absf(parcel_area - block.area) > _area_tolerance(block, active_profile):
			issues.append(FoundationParcelValidationIssue.new(
				&"parent_coverage_gap", FoundationParcelValidationIssue.SEVERITY_ERROR,
				&"", block.stable_id, "Parcel union does not cover the parent block within tolerance.",
				{"block_area": block.area, "parcel_area": parcel_area, "error": absf(parcel_area - block.area)}
			))

	issues.sort_custom(FoundationParcelValidationIssue.less)
	if apply_record_state:
		_apply_states(world, issues)
	return issues


static func _add_issue(
	issues: Array[FoundationParcelValidationIssue],
	parcel: FoundationParcelRecord,
	kind: StringName,
	severity: StringName,
	message: String,
	details: Dictionary = {}
) -> void:
	issues.append(FoundationParcelValidationIssue.new(kind, severity, parcel.stable_id, parcel.parent_id, message, details))


static func _apply_states(world: FoundationWorldData, issues: Array[FoundationParcelValidationIssue]) -> void:
	for issue in issues:
		if String(issue.parcel_id).is_empty():
			continue
		var parcel := world.get_record(issue.parcel_id) as FoundationParcelRecord
		if parcel == null or parcel.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
			continue
		parcel.validation_messages.append(issue.message)
		if issue.severity == FoundationParcelValidationIssue.SEVERITY_ERROR:
			parcel.validation_state = FoundationParcelRecord.INVALID
		elif parcel.validation_state == FoundationParcelRecord.VALID:
			parcel.validation_state = FoundationParcelRecord.WARNING


static func _intersection_area(first: PackedVector2Array, second: PackedVector2Array) -> float:
	var area := 0.0
	for polygon in Geometry2D.intersect_polygons(first, second):
		area += absf(FoundationBlockRecord._signed_area(polygon))
	return area


static func _area_tolerance(block: FoundationBlockRecord, profile: FoundationParcelGenerationProfile) -> float:
	return maxf(profile.point_quantization * profile.point_quantization * 8.0, block.area * 0.00001)
