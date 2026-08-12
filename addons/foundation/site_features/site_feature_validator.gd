class_name FoundationSiteFeatureValidator
extends RefCounted

## Read-only deterministic validation for Phase 10 records and accounting.


static func validate(
	world: FoundationWorldData,
	profile: FoundationSiteFeatureGenerationProfile = null,
	include_accounting := true
) -> Array[FoundationSiteFeatureValidationIssue]:
	var issues: Array[FoundationSiteFeatureValidationIssue] = []
	if world == null:
		issues.append(FoundationSiteFeatureValidationIssue.new(
			&"missing_world", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, &"", &"",
			"Site-feature validation requires FoundationWorldData."
		))
		return issues
	var active_profile := profile if profile != null else FoundationSiteFeatureGenerationProfile.new()
	var occupied: Array[Dictionary] = []
	for building in world.get_buildings():
		occupied.append({"id": building.stable_id, "kind": &"building", "footprint": building.footprint})
	for feature in world.get_public_features():
		_validate_public_feature(world, feature, active_profile, occupied, issues)
		occupied.append({"id": feature.stable_id, "kind": &"public_feature", "footprint": feature.footprint})
	for parking in world.get_parking_facilities():
		_validate_parking(world, parking, active_profile, occupied, issues)
		occupied.append({"id": parking.stable_id, "kind": &"parking", "footprint": parking.footprint})
	if include_accounting:
		_validate_layer_accounting(world, active_profile, issues)
	issues.sort_custom(FoundationSiteFeatureValidationIssue.less)
	return issues


static func _validate_public_feature(
	world: FoundationWorldData,
	feature: FoundationPublicFeatureRecord,
	profile: FoundationSiteFeatureGenerationProfile,
	occupied: Array[Dictionary],
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	var parcel := world.get_record(feature.parent_id) as FoundationParcelRecord
	if parcel == null:
		_add(issues, &"missing_parent_parcel", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, feature, "Public feature parent parcel does not exist.")
	else:
		_validate_geometry(feature.stable_id, feature.parent_id, feature.footprint, feature.world_bounds, feature.area, feature.position, parcel, profile, issues)
	if feature.feature_kind not in FoundationPublicFeatureRecord.builtin_kinds():
		_add(issues, &"invalid_public_feature_kind", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, feature, "Public feature kind is not supported.")
	if not String(feature.parent_block_id).is_empty() and not (world.get_record(feature.parent_block_id) is FoundationBlockRecord):
		_add(issues, &"missing_parent_block", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, feature, "Public feature parent block does not exist.")
	else:
		_validate_block_containment(world, feature, feature.parent_block_id, feature.footprint, profile, issues)
	if not String(feature.district_id).is_empty() and not (world.get_record(feature.district_id) is FoundationDistrictRecord):
		_add(issues, &"missing_district", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, feature, "Public feature district does not exist.")
	if not String(feature.source_anchor_id).is_empty() and not (world.get_record(feature.source_anchor_id) is FoundationCityAnchor):
		_add(issues, &"missing_source_anchor", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, feature, "Public feature source anchor does not exist.")
	if not String(feature.access_road_edge_id).is_empty() and not (world.get_record(feature.access_road_edge_id) is FoundationRoadEdge):
		_add(issues, &"missing_access_road", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, feature, "Public feature access road does not exist.")
	if not String(feature.access_logical_road_id).is_empty() and not (world.get_record(feature.access_logical_road_id) is FoundationLogicalRoad):
		_add(issues, &"missing_access_logical_road", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, feature, "Public feature logical-road access does not exist.")
	if feature.capacity < 0 or feature.service_radius < 0.0 or feature.suitability_score < 0.0 or feature.suitability_score > 1.0:
		_add(issues, &"invalid_public_feature_policy", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, feature, "Public feature capacity, radius, or suitability is invalid.")
	_validate_orientation(feature, feature.orientation_degrees, issues)
	_validate_terrain_evidence(feature, feature.suitability_evidence, profile, issues)
	_validate_stable_identity(world, feature, "%s|policy:%s|%s" % [feature.feature_kind, profile.policy_id, FoundationSiteFeatureGenerator.boundary_key(feature.footprint, profile)], profile, issues)
	_validate_generation_contract(feature, profile, issues)
	_validate_district_use(world, feature.stable_id, feature.parent_id, feature.parent_block_id, feature.district_id, feature.suitability_evidence, issues)
	_validate_overlap(feature.stable_id, feature.parent_id, feature.footprint, occupied, profile, issues)
	_validate_ownership(world, feature, issues)


static func _validate_parking(
	world: FoundationWorldData,
	parking: FoundationParkingFacilityRecord,
	profile: FoundationSiteFeatureGenerationProfile,
	occupied: Array[Dictionary],
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	var parcel := world.get_record(parking.parent_id) as FoundationParcelRecord
	if parcel == null:
		_add(issues, &"missing_parent_parcel", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking parent parcel does not exist.")
	else:
		_validate_geometry(parking.stable_id, parking.parent_id, parking.footprint, parking.world_bounds, parking.area, parking.centroid, parcel, profile, issues)
	if parking.facility_kind not in FoundationParkingFacilityRecord.builtin_kinds():
		_add(issues, &"invalid_parking_kind", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking facility kind is not supported.")
	if not String(parking.parent_block_id).is_empty() and not (world.get_record(parking.parent_block_id) is FoundationBlockRecord):
		_add(issues, &"missing_parent_block", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking parent block does not exist.")
	else:
		_validate_block_containment(world, parking, parking.parent_block_id, parking.footprint, profile, issues)
	if not String(parking.parent_building_id).is_empty() and not (world.get_record(parking.parent_building_id) is FoundationBuildingRecord):
		_add(issues, &"missing_parent_building", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking parent building does not exist.")
	if not String(parking.district_id).is_empty() and not (world.get_record(parking.district_id) is FoundationDistrictRecord):
		_add(issues, &"missing_district", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking district does not exist.")
	if not String(parking.access_road_edge_id).is_empty() and not (world.get_record(parking.access_road_edge_id) is FoundationRoadEdge):
		_add(issues, &"missing_access_road", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking access road does not exist.")
	if not String(parking.access_logical_road_id).is_empty() and not (world.get_record(parking.access_logical_road_id) is FoundationLogicalRoad):
		_add(issues, &"missing_access_logical_road", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking logical-road access does not exist.")
	if parking.demand_spaces < 0 or parking.supplied_spaces != parking.spaces.size() or parking.unmet_demand != maxi(0, parking.demand_spaces - parking.supplied_spaces):
		_add(issues, &"parking_accounting_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking demand, supply, or unmet-demand accounting is inconsistent.")
	_validate_orientation(parking, parking.orientation_degrees, issues)
	_validate_terrain_evidence(parking, parking.suitability_evidence, profile, issues)
	_validate_stable_identity(world, parking, "surface|policy:%s|%s" % [profile.policy_id, FoundationSiteFeatureGenerator.boundary_key(parking.footprint, profile)], profile, issues)
	var accessible := 0
	var previous: FoundationParkingSpace
	var seen_ids: Dictionary = {}
	var space_footprints: Array[PackedVector2Array] = []
	for space in parking.spaces:
		if seen_ids.has(space.space_id) or String(space.space_id).is_empty():
			_add(issues, &"duplicate_parking_space", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking-space identities must be unique.")
		seen_ids[space.space_id] = true
		var expected_space_id := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			&"parking_space", parking.stable_id, "row:%d|column:%d" % [space.row_index, space.column_index]
		)
		if space.space_id != expected_space_id:
			_add(issues, &"parking_space_identity", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking-space identity does not match its canonical row/column key.")
		if previous != null and FoundationParkingSpace.less(space, previous):
			_add(issues, &"parking_space_order", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking spaces are not in canonical row/column order.")
		previous = space
		if space.space_kind not in [FoundationParkingSpace.KIND_STANDARD, FoundationParkingSpace.KIND_ACCESSIBLE, FoundationParkingSpace.KIND_BICYCLE, FoundationParkingSpace.KIND_LOADING] or space.accessible != (space.space_kind == FoundationParkingSpace.KIND_ACCESSIBLE):
			_add(issues, &"invalid_parking_space_kind", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking-space kind and accessibility state are inconsistent.")
		var space_footprint := _space_footprint(space)
		var space_inside := space.width > 0.0 and space.length > 0.0
		for corner in space_footprint:
			space_inside = space_inside and FoundationSiteFeatureGenerator.point_inside_or_boundary(corner, parking.footprint, profile.geometric_tolerance)
		if not space_inside:
			_add(issues, &"invalid_parking_space", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking-space dimensions or placement are invalid.")
		for other_footprint in space_footprints:
			if FoundationSiteFeatureGenerator.polygons_overlap(space_footprint, other_footprint, profile.geometric_tolerance):
				_add(issues, &"parking_space_overlap", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking spaces overlap.")
		space_footprints.append(space_footprint)
		if space.accessible:
			accessible += 1
	if accessible != parking.accessible_spaces:
		_add(issues, &"accessible_space_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Accessible-space accounting is inconsistent.")
	if parking.frontage_segment_index < 0 or String(parking.access_road_edge_id).is_empty():
		_add(issues, &"missing_parking_access", FoundationSiteFeatureValidationIssue.SEVERITY_WARNING, parking, "Parking facility has no direct road/frontage provenance.")
	var seen_path_ids: Dictionary = {}
	for path in parking.access_paths:
		if String(path.path_id).is_empty() or path.points.size() < 2 or path.width <= 0.0:
			_add(issues, &"invalid_parking_access_path", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking access/aisle path is invalid.")
		if seen_path_ids.has(path.path_id):
			_add(issues, &"duplicate_parking_access_path", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking access/aisle path identities must be unique.")
		seen_path_ids[path.path_id] = true
		if path.path_kind not in [FoundationParkingAccessPath.KIND_ACCESS, FoundationParkingAccessPath.KIND_AISLE]:
			_add(issues, &"invalid_parking_access_path_kind", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking access/aisle path kind is unsupported.")
		if parking.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED and path.path_kind == FoundationParkingAccessPath.KIND_AISLE:
			var canonical_path_id := false
			for row_index in range(parking.spaces.size() + 1):
				var expected_path_id := FoundationSpatialId.make(
					world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
					&"parking_path", parking.stable_id, "aisle:%d" % row_index
				)
				if path.path_id == expected_path_id:
					canonical_path_id = true
					break
			if not canonical_path_id:
				_add(issues, &"parking_access_path_identity", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, parking, "Parking aisle identity does not match its canonical order.")
	_validate_generation_contract(parking, profile, issues)
	_validate_district_use(world, parking.stable_id, parking.parent_id, parking.parent_block_id, parking.district_id, parking.suitability_evidence, issues)
	_validate_overlap(parking.stable_id, parking.parent_id, parking.footprint, occupied, profile, issues)
	_validate_ownership(world, parking, issues)


static func _validate_block_containment(
	world: FoundationWorldData,
	record: FoundationSpatialRecord,
	block_id: StringName,
	footprint: PackedVector2Array,
	profile: FoundationSiteFeatureGenerationProfile,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	if String(block_id).is_empty():
		return
	var block := world.get_record(block_id) as FoundationBlockRecord
	if block == null:
		return
	for point in footprint:
		if not FoundationSiteFeatureGenerator.point_inside_or_boundary(point, block.outer_boundary, profile.geometric_tolerance):
			_add(issues, &"outside_parent_block", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record, "Site footprint lies outside its parent block.")
			return


static func _validate_orientation(
	record: FoundationSpatialRecord,
	orientation_degrees: float,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	if not is_finite(orientation_degrees) or orientation_degrees < 0.0 or orientation_degrees >= 360.0:
		_add(issues, &"invalid_site_orientation", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record, "Site orientation must be finite and canonical in [0, 360).")


static func _validate_terrain_evidence(
	record: FoundationSpatialRecord,
	evidence: Dictionary,
	profile: FoundationSiteFeatureGenerationProfile,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	if not bool(evidence.get("terrain_available", false)):
		return
	var slope := float(evidence.get("terrain_maximum_slope", INF))
	var elevation_delta := float(evidence.get("terrain_elevation_delta", INF))
	if not bool(evidence.get("terrain_valid", false)) or not is_finite(slope) or not is_finite(elevation_delta) or slope > profile.maximum_site_slope_degrees + profile.geometric_tolerance or elevation_delta > profile.maximum_site_elevation_delta + profile.geometric_tolerance:
		_add(issues, &"invalid_terrain_evidence", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record, "Stored terrain suitability evidence violates the active profile.")


static func _validate_stable_identity(
	world: FoundationWorldData,
	record: FoundationSpatialRecord,
	semantic: String,
	profile: FoundationSiteFeatureGenerationProfile,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	if record.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
		return
	var expected := FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		record.entity_type, record.parent_id, semantic
	)
	if record.stable_id == expected:
		return
	if world.get_record(expected) == null:
		_add(issues, &"site_feature_identity_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record, "Generated site identity does not match its canonical or collision-repair key.")
		return
	var repair_limit := world.get_parking_facilities().size() + world.get_public_features().size() + 1
	for ordinal in range(1, repair_limit + 1):
		var candidate := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			record.entity_type, record.parent_id, "%s|repair:%d" % [semantic, ordinal]
		)
		if record.stable_id == candidate:
			return
		if world.get_record(candidate) == null:
			break
	_add(issues, &"site_feature_identity_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record, "Generated site identity does not match its canonical or collision-repair key.")


static func _validate_geometry(
	record_id: StringName,
	parent_id: StringName,
	footprint: PackedVector2Array,
	stored_bounds: Rect2,
	stored_area: float,
	stored_centroid: Vector2,
	parcel: FoundationParcelRecord,
	profile: FoundationSiteFeatureGenerationProfile,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	if footprint.size() < 3:
		issues.append(FoundationSiteFeatureValidationIssue.new(&"degenerate_footprint", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record_id, parent_id, "Site footprint is degenerate."))
		return
	var derived_bounds := FoundationBlockRecord._bounds_for_boundary(footprint)
	var derived_area := absf(FoundationBlockRecord._signed_area(footprint))
	var derived_centroid := FoundationBlockRecord._polygon_centroid(footprint)
	if not _rect_equal(derived_bounds, stored_bounds, profile.geometric_tolerance) or absf(derived_area - stored_area) > profile.geometric_tolerance or derived_centroid.distance_to(stored_centroid) > profile.geometric_tolerance:
		issues.append(FoundationSiteFeatureValidationIssue.new(&"stored_geometry_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record_id, parent_id, "Stored site metrics do not match canonical geometry."))
	for point in footprint:
		if not FoundationSiteFeatureGenerator.point_inside_or_boundary(point, parcel.boundary, profile.geometric_tolerance):
			issues.append(FoundationSiteFeatureValidationIssue.new(&"outside_parent_parcel", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record_id, parent_id, "Site footprint lies outside its parent parcel."))
			break


static func _validate_overlap(
	record_id: StringName,
	parent_id: StringName,
	footprint: PackedVector2Array,
	occupied: Array[Dictionary],
	profile: FoundationSiteFeatureGenerationProfile,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	for entry in occupied:
		if FoundationSiteFeatureGenerator.polygons_violate_clearance(footprint, entry["footprint"], profile.site_clearance, profile.geometric_tolerance):
			issues.append(FoundationSiteFeatureValidationIssue.new(
				&"site_clearance_overlap", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record_id, parent_id,
				"Site overlaps or violates clearance from an existing reserved footprint.", {"other_id": String(entry["id"]), "other_kind": String(entry["kind"])}
			))


static func _validate_ownership(
	world: FoundationWorldData,
	record: FoundationSpatialRecord,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	var expected := world.coordinate_system.world_bounds_to_chunks(record.world_bounds)
	if expected != record.owning_chunks:
		issues.append(FoundationSiteFeatureValidationIssue.new(&"chunk_ownership_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record.stable_id, record.parent_id, "Site chunk ownership does not match its bounds."))


static func _validate_layer_accounting(
	world: FoundationWorldData,
	profile: FoundationSiteFeatureGenerationProfile,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	for layer_type in [FoundationWorldData.PARKING_FACILITY_LAYER, FoundationWorldData.PUBLIC_FEATURE_LAYER]:
		var layer := world.get_layer(layer_type)
		if layer == null:
			continue
		var profile_data: Dictionary = layer.metadata.get("profile", {})
		if not profile_data.is_empty() and int(profile_data.get("generator_version", -1)) != profile.generator_version:
			issues.append(FoundationSiteFeatureValidationIssue.new(&"profile_version_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_WARNING, &"", &"", "Layer profile version differs from the validation profile."))
	var parking_count := world.get_parking_facilities().size()
	var public_count := world.get_public_features().size()
	if parking_count > profile.maximum_parking_facilities or public_count > profile.maximum_public_features:
		issues.append(FoundationSiteFeatureValidationIssue.new(&"site_feature_record_cap", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, &"", &"", "Stored Phase 10 records exceed the configured layer caps."))
	var parking_layer := world.get_layer(FoundationWorldData.PARKING_FACILITY_LAYER)
	var stored_counts: Dictionary = parking_layer.metadata.get("counts", {}) if parking_layer != null else {}
	if int(stored_counts.get("generation_operation_count", 0)) > profile.maximum_generation_operations:
		issues.append(FoundationSiteFeatureValidationIssue.new(&"generation_operation_cap", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, &"", &"", "Stored generation work exceeds the configured cap."))
	var candidate_limit := world.get_parcels().size() * profile.maximum_candidates_per_parcel * 2
	if int(stored_counts.get("candidate_evaluations", 0)) > candidate_limit:
		issues.append(FoundationSiteFeatureValidationIssue.new(&"candidate_evaluation_cap", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, &"", &"", "Stored site-placement work exceeds the per-parcel candidate cap."))
	if int(stored_counts.get("generated_parking_count", parking_count)) > profile.maximum_parking_facilities or int(stored_counts.get("generated_public_feature_count", public_count)) > profile.maximum_public_features:
		issues.append(FoundationSiteFeatureValidationIssue.new(&"stored_record_cap", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, &"", &"", "Stored generation counts exceed the configured record caps."))
	if int(stored_counts.get("unserved_public_target_count", 0)) > int(stored_counts.get("public_target_count", 0)):
		issues.append(FoundationSiteFeatureValidationIssue.new(&"public_target_accounting_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, &"", &"", "Stored public-target coverage is inconsistent."))


static func _validate_generation_contract(
	record: FoundationSpatialRecord,
	profile: FoundationSiteFeatureGenerationProfile,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	if String(record.stable_id).is_empty():
		_add(issues, &"missing_stable_id", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record, "Phase 10 records require stable identity.")
	if record.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED and (
		record.source_pass != FoundationSiteFeatureGenerator.SOURCE_PASS or record.source_version != profile.generator_version
	):
		_add(issues, &"generation_source_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record, "Generated Phase 10 source pass/version is inconsistent.")


static func _validate_district_use(
	world: FoundationWorldData,
	record_id: StringName,
	parcel_id: StringName,
	block_id: StringName,
	district_id: StringName,
	evidence: Dictionary,
	issues: Array[FoundationSiteFeatureValidationIssue]
) -> void:
	if String(district_id).is_empty():
		return
	var district := world.get_record(district_id) as FoundationDistrictRecord
	if district == null:
		return
	if block_id not in district.member_block_ids:
		issues.append(FoundationSiteFeatureValidationIssue.new(&"district_membership_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record_id, parcel_id, "Phase 10 block is not a member of its referenced district."))
		return
	var expected_use := district.primary_use
	var assignment := district.get_assignment(block_id)
	if assignment != null:
		expected_use = assignment.primary_use
		if assignment.parcel_use_overrides.has(String(parcel_id)):
			expected_use = StringName(assignment.parcel_use_overrides[String(parcel_id)])
	var stored_use := StringName(evidence.get("district_use", ""))
	if not String(stored_use).is_empty() and stored_use != expected_use:
		issues.append(FoundationSiteFeatureValidationIssue.new(&"district_use_mismatch", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, record_id, parcel_id, "Stored Phase 10 use evidence differs from district/member policy."))


static func _add(
	issues: Array[FoundationSiteFeatureValidationIssue],
	kind: StringName,
	severity: StringName,
	record: FoundationSpatialRecord,
	message: String
) -> void:
	issues.append(FoundationSiteFeatureValidationIssue.new(kind, severity, record.stable_id, record.parent_id, message))


static func _rect_equal(a: Rect2, b: Rect2, tolerance: float) -> bool:
	return a.position.distance_to(b.position) <= tolerance and a.size.distance_to(b.size) <= tolerance


static func _space_footprint(space: FoundationParkingSpace) -> PackedVector2Array:
	var angle := deg_to_rad(space.orientation_degrees)
	var run := Vector2(cos(angle), sin(angle))
	var depth := Vector2(-run.y, run.x)
	var half_run := run * space.width * 0.5
	var half_depth := depth * space.length * 0.5
	return PackedVector2Array([
		space.position - half_run - half_depth,
		space.position + half_run - half_depth,
		space.position + half_run + half_depth,
		space.position - half_run + half_depth,
	])
