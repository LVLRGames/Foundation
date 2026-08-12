class_name FoundationFacadeValidator
extends RefCounted

## Deterministic facade lineage, grid, module, entrance, and geometry validation.


static func validate(
	world: FoundationWorldData,
	profile: FoundationFacadeGenerationProfile = null,
	apply_record_state := true
) -> Array[FoundationFacadeValidationIssue]:
	var active_profile := profile if profile != null else FoundationFacadeGenerationProfile.new()
	var issues: Array[FoundationFacadeValidationIssue] = []
	var primary_counts: Dictionary = {}
	var entrance_counts: Dictionary = {}
	for facade in world.get_facades():
		if apply_record_state and facade.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			facade.validation_state = FoundationFacadeRecord.VALID
			facade.validation_messages.clear()
		var building := world.get_record(facade.parent_id) as FoundationBuildingRecord
		if building == null:
			_add_issue(issues, facade, &"missing_parent_building", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade parent building is missing.")
			continue
		if facade.parent_parcel_id != building.parent_id or facade.parent_block_id != building.parent_block_id:
			_add_issue(issues, facade, &"parent_lineage_mismatch", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade parcel or block lineage does not match its building.")
		if facade.source_segment_index < 0 or facade.source_segment_index >= building.footprint.size():
			_add_issue(issues, facade, &"invalid_source_segment", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade source segment is outside the building footprint.")
		else:
			var expected_start := building.footprint[facade.source_segment_index]
			var expected_end := building.footprint[(facade.source_segment_index + 1) % building.footprint.size()]
			if facade.start.distance_to(expected_start) > active_profile.geometric_epsilon or facade.end.distance_to(expected_end) > active_profile.geometric_epsilon:
				_add_issue(issues, facade, &"source_geometry_mismatch", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade segment does not match its source building edge.")
		if facade.facade_length < active_profile.minimum_facade_length or facade.height <= active_profile.geometric_epsilon:
			_add_issue(issues, facade, &"degenerate_facade", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade length or height is degenerate.")
		if facade.floor_count != building.floor_count or not is_equal_approx(facade.floor_height, building.floor_height) or not is_equal_approx(facade.height, building.height):
			_add_issue(issues, facade, &"massing_mismatch", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade vertical grid does not match building massing.")
		if facade.bay_count <= 0 or facade.bay_count > active_profile.maximum_bays_per_facade:
			_add_issue(issues, facade, &"invalid_bay_count", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade bay count is invalid.")
		elif facade.bay_width < active_profile.minimum_bay_width - active_profile.geometric_epsilon or facade.bay_width > active_profile.maximum_bay_width + active_profile.geometric_epsilon:
			_add_issue(issues, facade, &"invalid_bay_width", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade bay width is outside the configured range.")
		if facade.modules.size() != facade.bay_count * facade.floor_count:
			_add_issue(issues, facade, &"incomplete_module_grid", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade module grid does not contain one module per floor and bay.")
		_validate_modules(facade, active_profile, issues)
		if facade.facade_role == FoundationFacadeRecord.ROLE_PRIMARY:
			primary_counts[facade.parent_id] = int(primary_counts.get(facade.parent_id, 0)) + 1
		var entrances := 0
		for module in facade.modules:
			if module.kind == FoundationFacadeModule.KIND_ENTRANCE:
				entrances += 1
		entrance_counts[facade.parent_id] = int(entrance_counts.get(facade.parent_id, 0)) + entrances
		if facade.facade_role == FoundationFacadeRecord.ROLE_PRIMARY and entrances != 1:
			_add_issue(issues, facade, &"primary_entrance_count", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Primary facade must contain exactly one entrance module.")
		elif facade.facade_role != FoundationFacadeRecord.ROLE_PRIMARY and entrances > 0:
			_add_issue(issues, facade, &"entrance_on_non_primary", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Entrance modules are only allowed on the primary facade.")
		if facade.glazing_ratio < -active_profile.geometric_epsilon or facade.glazing_ratio > 1.0 + active_profile.geometric_epsilon:
			_add_issue(issues, facade, &"invalid_glazing_ratio", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade glazing ratio is invalid.")

	for building in world.get_buildings():
		var facades := _facades_for_building(world, building.stable_id)
		if facades.is_empty():
			continue
		if int(primary_counts.get(building.stable_id, 0)) != 1:
			_add_issue(issues, facades[0], &"building_primary_facade_count", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Building must have exactly one primary facade.")
		if int(entrance_counts.get(building.stable_id, 0)) != 1:
			_add_issue(issues, facades[0], &"building_entrance_count", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Building facade grammar must contain exactly one entrance.")

	issues.sort_custom(FoundationFacadeValidationIssue.less)
	if apply_record_state:
		_apply_states(world, issues)
	return issues


static func _validate_modules(
	facade: FoundationFacadeRecord,
	profile: FoundationFacadeGenerationProfile,
	issues: Array[FoundationFacadeValidationIssue]
) -> void:
	var occupied: Dictionary = {}
	var ids: Dictionary = {}
	for module in facade.modules:
		if ids.has(module.module_id):
			_add_issue(issues, facade, &"duplicate_module_id", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade contains duplicate module IDs.")
		ids[module.module_id] = true
		var cell_key := "%d:%d" % [module.floor_index, module.bay_index]
		if occupied.has(cell_key):
			_add_issue(issues, facade, &"duplicate_module_cell", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade contains multiple modules in one grid cell.")
		occupied[cell_key] = true
		if module.floor_index < 0 or module.floor_index >= facade.floor_count or module.bay_index < 0 or module.bay_index >= facade.bay_count:
			_add_issue(issues, facade, &"module_outside_grid", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade module index is outside the grid.")
		if module.horizontal_start < -profile.geometric_epsilon or module.horizontal_end > facade.facade_length + profile.geometric_epsilon or module.vertical_start < -profile.geometric_epsilon or module.vertical_end > facade.height + profile.geometric_epsilon or module.area() <= profile.geometric_epsilon:
			_add_issue(issues, facade, &"invalid_module_bounds", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade module bounds are empty or outside the facade plane.")
		if module.kind not in [FoundationFacadeModule.KIND_WALL, FoundationFacadeModule.KIND_WINDOW, FoundationFacadeModule.KIND_ENTRANCE]:
			_add_issue(issues, facade, &"unknown_module_kind", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Facade module kind is unsupported.")
		if module.kind == FoundationFacadeModule.KIND_ENTRANCE and module.floor_index != 0:
			_add_issue(issues, facade, &"elevated_entrance", FoundationFacadeValidationIssue.SEVERITY_ERROR, "Entrance module must be on the ground floor.")


static func _facades_for_building(world: FoundationWorldData, building_id: StringName) -> Array[FoundationFacadeRecord]:
	var result: Array[FoundationFacadeRecord] = []
	for facade in world.get_facades():
		if facade.parent_id == building_id:
			result.append(facade)
	return result


static func _add_issue(
	issues: Array[FoundationFacadeValidationIssue],
	facade: FoundationFacadeRecord,
	kind: StringName,
	severity: StringName,
	message: String,
	details: Dictionary = {}
) -> void:
	issues.append(FoundationFacadeValidationIssue.new(kind, severity, facade.stable_id, facade.parent_id, message, details))


static func _apply_states(world: FoundationWorldData, issues: Array[FoundationFacadeValidationIssue]) -> void:
	for issue in issues:
		var facade := world.get_record(issue.facade_id) as FoundationFacadeRecord
		if facade == null or facade.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
			continue
		facade.validation_messages.append(issue.message)
		if issue.severity == FoundationFacadeValidationIssue.SEVERITY_ERROR:
			facade.validation_state = FoundationFacadeRecord.INVALID
		elif facade.validation_state == FoundationFacadeRecord.VALID:
			facade.validation_state = FoundationFacadeRecord.WARNING
