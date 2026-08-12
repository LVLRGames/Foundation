class_name FoundationSiteFeatureGenerator
extends RefCounted

## Deterministic bounded Phase 10 parking and public-feature placement.

const SOURCE_PASS: StringName = &"phase_10_site_feature_generation"


static func generate(
	world: FoundationWorldData,
	profile: FoundationSiteFeatureGenerationProfile = null,
	terrain: FoundationTerrainData = null,
	terrain_origin_cell := Vector2i.ZERO
) -> FoundationSiteFeatureGenerationResult:
	var result := FoundationSiteFeatureGenerationResult.new()
	if world == null:
		return result.fail("Site-feature generation requires FoundationWorldData.")
	var active_profile := profile if profile != null else FoundationSiteFeatureGenerationProfile.new()
	var errors := active_profile.validation_errors()
	if not errors.is_empty():
		return result.fail("Invalid site-feature generation profile: %s" % "; ".join(errors))
	world.register_layer_type(FoundationWorldData.PARKING_FACILITY_LAYER)
	world.register_layer_type(FoundationWorldData.PUBLIC_FEATURE_LAYER)

	var exclusions_by_parcel: Dictionary = {}
	for building in world.get_buildings():
		if building.footprint.size() >= 3:
			_add_exclusion(exclusions_by_parcel, building.parent_id, building.footprint)
	_remove_replaceable_records(world, exclusions_by_parcel, result)

	var buildings_by_parcel: Dictionary = {}
	for building in world.get_buildings():
		if not buildings_by_parcel.has(building.parent_id):
			buildings_by_parcel[building.parent_id] = building

	# Public sites reserve land first; parking then uses the remaining parcel space.
	var anchor_assignments := _public_anchor_assignments(world, active_profile, result)
	if _cap_exceeded(active_profile, result):
		return _cap_failure(world, active_profile, result)
	var claimed_use_districts: Dictionary = {}
	var public_targets: Dictionary = {}
	var served_public_targets: Dictionary = {}
	for parcel in world.get_parcels():
		result.generation_operation_count += 1
		if _cap_exceeded(active_profile, result):
			return _cap_failure(world, active_profile, result)
		if result.generated_public_feature_count >= active_profile.maximum_public_features:
			result.add_diagnostic(&"public_feature_record_cap", FoundationSiteFeatureValidationIssue.SEVERITY_WARNING)
			break
		if _valid_authored_public_exists(world, parcel, active_profile):
			continue
		var public_context := _parcel_context(world, parcel, buildings_by_parcel)
		var anchor := anchor_assignments.get(parcel.stable_id) as FoundationCityAnchor
		if not _public_eligible(public_context["use"], anchor):
			continue
		var public_district := public_context["district"] as FoundationDistrictRecord
		if anchor == null and public_district != null and claimed_use_districts.has(public_district.stable_id):
			continue
		var target_id := StringName("anchor:%s" % anchor.stable_id) if anchor != null else StringName("district:%s" % public_district.stable_id)
		public_targets[target_id] = {
			"parent_id": String(parcel.stable_id), "point": _point_dict(parcel.label_point),
		}
		var feature := _create_public_feature(world, parcel, public_context, anchor, _get_exclusions(exclusions_by_parcel, parcel.stable_id), terrain, terrain_origin_cell, active_profile, result)
		if feature != null:
			world.register_record(feature)
			_add_exclusion(exclusions_by_parcel, parcel.stable_id, feature.footprint)
			result.generated_public_feature_count += 1
			served_public_targets[target_id] = true
			if anchor == null and public_district != null:
				claimed_use_districts[public_district.stable_id] = true
	for target_id in public_targets:
		result.public_target_count += 1
		if not served_public_targets.has(target_id):
			result.unserved_public_target_count += 1
			var target_details: Dictionary = public_targets[target_id]
			target_details["target_id"] = String(target_id)
			result.add_diagnostic(&"public_feature_target_unserved", FoundationSiteFeatureValidationIssue.SEVERITY_WARNING, target_details)

	for parcel in world.get_parcels():
		result.generation_operation_count += 1
		if _cap_exceeded(active_profile, result):
			return _cap_failure(world, active_profile, result)
		if result.generated_parking_count >= active_profile.maximum_parking_facilities:
			result.add_diagnostic(&"parking_record_cap", FoundationSiteFeatureValidationIssue.SEVERITY_WARNING)
			break
		var context := _parcel_context(world, parcel, buildings_by_parcel)
		var demand := _parking_demand(parcel, context, active_profile)
		if demand <= 0:
			continue
		result.demand_spaces_total += demand
		var retained_parking := _valid_authored_parking(world, parcel, active_profile)
		if not retained_parking.is_empty():
			var authored_supply := 0
			for authored in retained_parking:
				authored_supply += authored.supplied_spaces
			result.supplied_spaces_total += authored_supply
			result.unmet_demand_total += maxi(0, demand - authored_supply)
			continue
		if not _parcel_can_host_parking(parcel):
			result.skipped_parcel_count += 1
			result.unmet_demand_total += demand
			result.add_diagnostic(&"parking_without_direct_access", FoundationSiteFeatureValidationIssue.SEVERITY_WARNING, {
				"parent_id": String(parcel.stable_id), "demand_spaces": demand, "point": _point_dict(parcel.label_point),
			})
			continue
		var parking := _create_parking_facility(world, parcel, context, demand, _get_exclusions(exclusions_by_parcel, parcel.stable_id), terrain, terrain_origin_cell, active_profile, result)
		if parking == null:
			result.skipped_parcel_count += 1
			result.unmet_demand_total += demand
			result.add_diagnostic(&"parking_site_unavailable", FoundationSiteFeatureValidationIssue.SEVERITY_WARNING, {
				"parent_id": String(parcel.stable_id), "demand_spaces": demand, "point": _point_dict(parcel.label_point),
			})
			continue
		world.register_record(parking)
		_add_exclusion(exclusions_by_parcel, parcel.stable_id, parking.footprint)
		result.generated_parking_count += 1
		result.supplied_spaces_total += parking.supplied_spaces
		result.unmet_demand_total += parking.unmet_demand

	var issues := FoundationSiteFeatureValidator.validate(world, active_profile, true)
	for issue in issues:
		result.diagnostics.append(issue.to_dict())
	result.diagnostics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	result.success = true
	_set_layer_metadata(world, active_profile, result)
	return result


static func clear_generated(world: FoundationWorldData) -> Dictionary:
	var counts := {"parking": 0, "public_features": 0}
	if world == null:
		return counts
	for parking in world.get_parking_facilities():
		if parking.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(parking.stable_id)
			counts["parking"] = int(counts["parking"]) + 1
	for feature in world.get_public_features():
		if feature.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(feature.stable_id)
			counts["public_features"] = int(counts["public_features"]) + 1
	return counts


static func _remove_replaceable_records(
	world: FoundationWorldData,
	exclusions_by_parcel: Dictionary,
	result: FoundationSiteFeatureGenerationResult
) -> void:
	var retained_parking: Array[FoundationParkingFacilityRecord] = []
	for parking in world.get_parking_facilities():
		if parking.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(parking.stable_id)
		else:
			retained_parking.append(parking)
	var retained_features: Array[FoundationPublicFeatureRecord] = []
	for feature in world.get_public_features():
		if feature.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(feature.stable_id)
		else:
			retained_features.append(feature)
	for parking in retained_parking:
		parking.refresh_metrics()
		world.register_record(parking)
		result.preserved_parking_count += 1
		if parking.footprint.size() >= 3 and world.get_record(parking.parent_id) is FoundationParcelRecord:
			_add_exclusion(exclusions_by_parcel, parking.parent_id, parking.footprint)
		else:
			result.add_diagnostic(&"invalid_authored_site", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, {"record_id": String(parking.stable_id)})
	for feature in retained_features:
		feature.refresh_metrics()
		world.register_record(feature)
		result.preserved_public_feature_count += 1
		if feature.footprint.size() >= 3 and world.get_record(feature.parent_id) is FoundationParcelRecord:
			_add_exclusion(exclusions_by_parcel, feature.parent_id, feature.footprint)
		else:
			result.add_diagnostic(&"invalid_authored_site", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR, {"record_id": String(feature.stable_id)})


static func _parcel_context(world: FoundationWorldData, parcel: FoundationParcelRecord, buildings_by_parcel: Dictionary) -> Dictionary:
	var district := world.get_district_for_parcel(parcel.stable_id)
	var use_key: StringName = FoundationDistrictRecord.USE_RESIDENTIAL
	if district != null:
		use_key = district.primary_use
		var assignment := district.get_assignment(parcel.parent_id)
		if assignment != null:
			use_key = assignment.primary_use
		if assignment != null and assignment.parcel_use_overrides.has(String(parcel.stable_id)):
			use_key = StringName(assignment.parcel_use_overrides[String(parcel.stable_id)])
	var building := buildings_by_parcel.get(parcel.stable_id) as FoundationBuildingRecord
	return {"district": district, "use": use_key, "building": building}


static func _valid_authored_public_exists(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	profile: FoundationSiteFeatureGenerationProfile
) -> bool:
	for feature in world.get_public_features_for_parcel(parcel.stable_id):
		if feature.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED and _footprint_in_parent(feature.footprint, parcel.boundary, profile.geometric_tolerance):
			return true
	return false


static func _valid_authored_parking(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	profile: FoundationSiteFeatureGenerationProfile
) -> Array[FoundationParkingFacilityRecord]:
	var result: Array[FoundationParkingFacilityRecord] = []
	for parking in world.get_parking_for_parcel(parcel.stable_id):
		if parking.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED and _footprint_in_parent(parking.footprint, parcel.boundary, profile.geometric_tolerance):
			result.append(parking)
	return result


static func _footprint_in_parent(footprint: PackedVector2Array, parent: PackedVector2Array, tolerance: float) -> bool:
	if footprint.size() < 3:
		return false
	for point in footprint:
		if not point_inside_or_boundary(point, parent, tolerance):
			return false
	return true


static func _public_eligible(use_key: StringName, anchor: FoundationCityAnchor) -> bool:
	return anchor != null or use_key in [
		FoundationDistrictRecord.USE_OPEN_SPACE,
		FoundationDistrictRecord.USE_CIVIC,
		FoundationDistrictRecord.USE_INSTITUTIONAL,
	]


static func _public_anchor_assignments(
	world: FoundationWorldData,
	profile: FoundationSiteFeatureGenerationProfile,
	result: FoundationSiteFeatureGenerationResult
) -> Dictionary:
	var assignments: Dictionary = {}
	for anchor in world.get_anchors():
		if anchor.anchor_category not in [
			FoundationCityAnchor.CATEGORY_PUBLIC_SQUARE,
			FoundationCityAnchor.CATEGORY_TRANSIT_NODE,
			FoundationCityAnchor.CATEGORY_LANDMARK,
			FoundationCityAnchor.CATEGORY_CIVIC_CENTER,
		]:
			continue
		var anchor_point := Vector2(anchor.world_position.x, anchor.world_position.z)
		var limit := maxf(profile.anchor_influence_distance, anchor.influence_radius)
		var bounds := Rect2(anchor_point - Vector2.ONE * limit, Vector2.ONE * limit * 2.0)
		var candidates := world.query_bounds(bounds, [FoundationWorldData.PARCEL_LAYER])
		var best_parcel: FoundationParcelRecord
		var best_distance := INF
		for candidate_record in candidates:
			if not (candidate_record is FoundationParcelRecord):
				continue
			result.generation_operation_count += 1
			if _cap_exceeded(profile, result):
				return {}
			var parcel := candidate_record as FoundationParcelRecord
			var distance := parcel.label_point.distance_to(anchor_point)
			if distance <= limit and (distance < best_distance - profile.geometric_tolerance or (
				is_equal_approx(distance, best_distance) and (best_parcel == null or String(parcel.stable_id) < String(best_parcel.stable_id))
			)):
				best_parcel = parcel
				best_distance = distance
		if best_parcel == null:
			_add_unserved_anchor_diagnostic(result, anchor, "no_parcel_in_influence")
			continue
		var existing: Dictionary = assignments.get(best_parcel.stable_id, {})
		if existing.is_empty() or best_distance < float(existing["distance"]) - profile.geometric_tolerance or (
			is_equal_approx(best_distance, float(existing["distance"])) and String(anchor.stable_id) < String((existing["anchor"] as FoundationCityAnchor).stable_id)
		):
			if not existing.is_empty():
				_add_unserved_anchor_diagnostic(result, existing["anchor"] as FoundationCityAnchor, "parcel_claimed_by_nearer_anchor")
			assignments[best_parcel.stable_id] = {"anchor": anchor, "distance": best_distance}
		else:
			_add_unserved_anchor_diagnostic(result, anchor, "parcel_claimed_by_nearer_anchor")
	var result_assignments: Dictionary = {}
	for parcel_id in assignments:
		result_assignments[parcel_id] = (assignments[parcel_id] as Dictionary)["anchor"]
	return result_assignments


static func _add_unserved_anchor_diagnostic(
	result: FoundationSiteFeatureGenerationResult,
	anchor: FoundationCityAnchor,
	reason: String
) -> void:
	result.public_target_count += 1
	result.unserved_public_target_count += 1
	result.add_diagnostic(&"public_feature_anchor_unserved", FoundationSiteFeatureValidationIssue.SEVERITY_INFO, {
		"anchor_id": String(anchor.stable_id),
		"reason": reason,
		"point": {"x": anchor.world_position.x, "y": anchor.world_position.z},
	})


static func _create_public_feature(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	context: Dictionary,
	anchor: FoundationCityAnchor,
	exclusions: Array[PackedVector2Array],
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationSiteFeatureGenerationProfile,
	result: FoundationSiteFeatureGenerationResult
) -> FoundationPublicFeatureRecord:
	if parcel.boundary.size() < 3 or parcel.area <= profile.geometric_tolerance:
		return null
	var kind := _public_kind(StringName(context["use"]), anchor, world, parcel, profile)
	var use_key := String(context["use"])
	var target_fraction := float(profile.public_feature_fraction_by_use.get(use_key, profile.public_feature_fraction))
	var target_area := clampf(
		parcel.area * target_fraction,
		profile.minimum_public_feature_area,
		profile.maximum_public_feature_area
	)
	var footprint := _find_site(world, parcel, target_area, profile.minimum_public_feature_area, exclusions, profile.STREAM_PUBLIC_PRIORITY, terrain, terrain_origin_cell, profile, result)
	if footprint.is_empty():
		result.add_diagnostic(&"public_feature_site_unavailable", FoundationSiteFeatureValidationIssue.SEVERITY_INFO, {
			"parent_id": String(parcel.stable_id), "feature_kind": String(kind), "point": _point_dict(parcel.label_point),
		})
		return null
	var semantic := "%s|policy:%s|%s" % [kind, profile.policy_id, boundary_key(footprint, profile)]
	var stable_id := FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		FoundationPublicFeatureRecord.ENTITY_TYPE, parcel.stable_id, semantic
	)
	stable_id = _repair_id(world, FoundationPublicFeatureRecord.ENTITY_TYPE, parcel.stable_id, semantic, stable_id, profile)
	var feature := FoundationPublicFeatureRecord.new(stable_id, parcel.stable_id, parcel.parent_id, footprint)
	feature.feature_kind = kind
	var district := context["district"] as FoundationDistrictRecord
	feature.district_id = district.stable_id if district != null else &""
	feature.source_anchor_id = anchor.stable_id if anchor != null else &""
	feature.orientation_degrees = _frontage_orientation(parcel)
	var terrain_evidence := _terrain_evidence(world, footprint, terrain, terrain_origin_cell, profile)
	feature.base_elevation = _base_elevation(world, context, terrain_evidence)
	var frontage := _primary_frontage(parcel)
	if frontage != null:
		feature.access_road_edge_id = frontage.road_edge_id
		feature.access_logical_road_id = frontage.logical_road_id
	feature.capacity = maxi(1, floori(feature.area / 9.0))
	feature.service_radius = profile.public_service_radius
	var anchor_distance := -1.0
	if anchor != null:
		anchor_distance = feature.position.distance_to(Vector2(anchor.world_position.x, anchor.world_position.z))
	feature.suitability_score = clampf(1.0 - maxf(anchor_distance, 0.0) / maxf(profile.anchor_influence_distance, 1.0), 0.0, 1.0) if anchor != null else 0.65
	feature.suitability_evidence = {
		"district_use": String(context["use"]),
		"source_anchor_category": String(anchor.anchor_category) if anchor != null else "",
		"anchor_distance": anchor_distance,
		"reserved_area": feature.area,
	}
	feature.suitability_evidence.merge(terrain_evidence, true)
	feature.source_pass = SOURCE_PASS
	feature.source_version = profile.generator_version
	feature.tags = PackedStringArray(["phase_10", "public_feature", String(kind)])
	_refresh_ownership(world, feature)
	return feature


static func _public_kind(
	use_key: StringName,
	anchor: FoundationCityAnchor,
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	profile: FoundationSiteFeatureGenerationProfile
) -> StringName:
	if anchor != null:
		match anchor.anchor_category:
			FoundationCityAnchor.CATEGORY_PUBLIC_SQUARE:
				return FoundationPublicFeatureRecord.KIND_PLAZA
			FoundationCityAnchor.CATEGORY_TRANSIT_NODE:
				return FoundationPublicFeatureRecord.KIND_TRANSIT_STOP
			FoundationCityAnchor.CATEGORY_LANDMARK:
				return FoundationPublicFeatureRecord.KIND_LANDMARK_SITE
			FoundationCityAnchor.CATEGORY_CIVIC_CENTER:
				return FoundationPublicFeatureRecord.KIND_CIVIC_MARKER
	if use_key == FoundationDistrictRecord.USE_OPEN_SPACE:
		var variation := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [profile.STREAM_PUBLIC_VARIATION, parcel.stable_id]))
		return FoundationPublicFeatureRecord.KIND_PLAYGROUND if variation % 4 == 0 else FoundationPublicFeatureRecord.KIND_PARK
	if use_key == FoundationDistrictRecord.USE_INSTITUTIONAL:
		return FoundationPublicFeatureRecord.KIND_CIVIC_MARKER
	return FoundationPublicFeatureRecord.KIND_PLAZA


static func _parking_demand(
	parcel: FoundationParcelRecord,
	context: Dictionary,
	profile: FoundationSiteFeatureGenerationProfile
) -> int:
	var use_key := String(context["use"])
	if not profile.demand_area_per_space.has(use_key):
		return 0
	var building := context["building"] as FoundationBuildingRecord
	var basis := building.gross_floor_area if building != null else parcel.area * 0.35
	var demand := ceili(basis / float(profile.demand_area_per_space[use_key]))
	return maxi(profile.minimum_parking_demand, demand)


static func _parcel_can_host_parking(parcel: FoundationParcelRecord) -> bool:
	return parcel.validation_state != FoundationParcelRecord.INVALID \
		and parcel.access_state == FoundationParcelRecord.ACCESS_DIRECT \
		and parcel.primary_frontage_index >= 0 \
		and parcel.primary_frontage_index < parcel.frontage_references.size() \
		and parcel.boundary.size() >= 3


static func _create_parking_facility(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	context: Dictionary,
	demand: int,
	exclusions: Array[PackedVector2Array],
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationSiteFeatureGenerationProfile,
	result: FoundationSiteFeatureGenerationResult
) -> FoundationParkingFacilityRecord:
	var bounded_demand := mini(demand, profile.maximum_spaces_per_facility)
	var target_area := clampf(
		float(bounded_demand) * profile.parking_area_per_space,
		profile.minimum_parking_area,
		parcel.area * profile.maximum_parking_fraction
	)
	if target_area < profile.minimum_parking_area:
		return null
	var footprint := _find_site(world, parcel, target_area, profile.minimum_parking_area, exclusions, profile.STREAM_PARKING_PRIORITY, terrain, terrain_origin_cell, profile, result)
	if footprint.is_empty():
		return null
	var semantic := "surface|policy:%s|%s" % [profile.policy_id, boundary_key(footprint, profile)]
	var stable_id := FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		FoundationParkingFacilityRecord.ENTITY_TYPE, parcel.stable_id, semantic
	)
	stable_id = _repair_id(world, FoundationParkingFacilityRecord.ENTITY_TYPE, parcel.stable_id, semantic, stable_id, profile)
	var parking := FoundationParkingFacilityRecord.new(stable_id, parcel.stable_id, parcel.parent_id, footprint)
	var building := context["building"] as FoundationBuildingRecord
	var district := context["district"] as FoundationDistrictRecord
	parking.parent_building_id = building.stable_id if building != null else &""
	parking.district_id = district.stable_id if district != null else &""
	var layout_seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [profile.STREAM_PARKING_LAYOUT, parcel.stable_id]))
	parking.orientation_degrees = _parking_orientation(parcel, layout_seed)
	var terrain_evidence := _terrain_evidence(world, footprint, terrain, terrain_origin_cell, profile)
	parking.base_elevation = _base_elevation(world, context, terrain_evidence)
	parking.demand_spaces = demand
	var frontage := _primary_frontage(parcel)
	parking.frontage_segment_index = frontage.parcel_boundary_segment_index
	parking.access_road_edge_id = frontage.road_edge_id
	parking.access_logical_road_id = frontage.logical_road_id
	_populate_parking_layout(world, parking, bounded_demand, profile)
	if parking.spaces.is_empty():
		return null
	parking.suitability_evidence = {
		"district_use": String(context["use"]),
		"demand_basis": "gross_floor_area" if building != null else "parcel_area",
		"candidate_area": parking.area,
		"frontage_segment_index": parking.frontage_segment_index,
	}
	parking.suitability_evidence.merge(terrain_evidence, true)
	parking.source_pass = SOURCE_PASS
	parking.source_version = profile.generator_version
	parking.tags = PackedStringArray(["phase_10", "parking", "surface_lot"])
	_refresh_ownership(world, parking)
	return parking


static func _populate_parking_layout(
	world: FoundationWorldData,
	parking: FoundationParkingFacilityRecord,
	space_limit: int,
	profile: FoundationSiteFeatureGenerationProfile
) -> void:
	# The facility footprint has already been placed with the configured site
	# clearance. Stall geometry may use that footprint without applying the
	# exterior setback a second time.
	var bounds := parking.world_bounds
	if bounds.size.x < profile.stall_width or bounds.size.y < profile.stall_length:
		return
	var horizontal := parking.orientation_degrees == 0.0
	var run_length := bounds.size.x if horizontal else bounds.size.y
	var row_depth := bounds.size.y if horizontal else bounds.size.x
	var columns := maxi(1, floori(run_length / profile.stall_width))
	var row_pitch := profile.stall_length + profile.aisle_width
	var rows := maxi(1, floori((row_depth + profile.aisle_width) / row_pitch))
	var capacity := mini(space_limit, rows * columns)
	var accessible_target := mini(capacity, maxi(1, ceili(float(capacity) * profile.accessible_ratio)))
	for row_index in range(rows):
		var depth_offset := profile.stall_length * 0.5 + float(row_index) * row_pitch
		var run_cursor := 0.0
		for column_index in range(columns):
			if parking.spaces.size() >= capacity:
				break
			var is_accessible := parking.spaces.size() < accessible_target
			var space_width := profile.accessible_stall_width if is_accessible else profile.stall_width
			if run_cursor + space_width > run_length + profile.geometric_tolerance:
				break
			var run_offset := run_cursor + space_width * 0.5
			var point := Vector2(
				bounds.position.x + run_offset,
				bounds.position.y + depth_offset
			) if horizontal else Vector2(
				bounds.position.x + depth_offset,
				bounds.position.y + run_offset
			)
			var space_id := FoundationSpatialId.make(
				world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
				&"parking_space", parking.stable_id, "row:%d|column:%d" % [row_index, column_index]
			)
			var space := FoundationParkingSpace.new(space_id, row_index, column_index, point)
			space.orientation_degrees = parking.orientation_degrees
			space.width = space_width
			space.length = profile.stall_length
			if is_accessible:
				space.accessible = true
				space.space_kind = FoundationParkingSpace.KIND_ACCESSIBLE
			parking.spaces.append(space)
			run_cursor += space_width
		if parking.spaces.size() >= capacity:
			break
		var aisle_offset := depth_offset + profile.stall_length * 0.5 + profile.aisle_width * 0.5
		if aisle_offset < row_depth:
			var aisle_points := PackedVector2Array([
				Vector2(bounds.position.x, bounds.position.y + aisle_offset),
				Vector2(bounds.end.x, bounds.position.y + aisle_offset),
			]) if horizontal else PackedVector2Array([
				Vector2(bounds.position.x + aisle_offset, bounds.position.y),
				Vector2(bounds.position.x + aisle_offset, bounds.end.y),
			])
			var path_id := FoundationSpatialId.make(
				world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
				&"parking_path", parking.stable_id, "aisle:%d" % row_index
			)
			var path := FoundationParkingAccessPath.new(path_id, FoundationParkingAccessPath.KIND_AISLE, aisle_points)
			path.width = profile.aisle_width
			parking.access_paths.append(path)
	parking.refresh_metrics()


static func _find_site(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	target_area: float,
	minimum_area: float,
	exclusions: Array[PackedVector2Array],
	stream: StringName,
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationSiteFeatureGenerationProfile,
	result: FoundationSiteFeatureGenerationResult
) -> PackedVector2Array:
	var bounds := parcel.world_bounds.grow(-profile.site_clearance)
	if bounds.size.x <= profile.geometric_tolerance or bounds.size.y <= profile.geometric_tolerance:
		return PackedVector2Array()
	var order: Array[Vector2] = [
		Vector2(0.20, 0.20), Vector2(0.50, 0.20), Vector2(0.80, 0.20),
		Vector2(0.20, 0.50), Vector2(0.50, 0.50), Vector2(0.80, 0.50),
		Vector2(0.20, 0.80), Vector2(0.50, 0.80), Vector2(0.80, 0.80),
	]
	var seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [stream, parcel.stable_id]))
	var rotation := int(seed % order.size())
	for index in range(rotation):
		order.append(order.pop_front())
	var scales: Array[float] = []
	for candidate_scale in [1.0, 0.65, 0.35, clampf(minimum_area / maxf(target_area, minimum_area), 0.01, 1.0)]:
		var duplicate_scale := false
		for existing_scale in scales:
			duplicate_scale = duplicate_scale or is_equal_approx(candidate_scale, existing_scale)
		if not duplicate_scale:
			scales.append(candidate_scale)
	var aspect_ratios: Array[float] = [1.55, 0.65, 4.0, 0.25]
	var parcel_candidates := 0
	for scale in scales:
		var area := target_area * scale
		if area < minimum_area:
			continue
		for aspect_ratio in aspect_ratios:
			var width := minf(bounds.size.x, sqrt(area * aspect_ratio))
			var height := minf(bounds.size.y, area / maxf(width, profile.geometric_tolerance))
			if height >= bounds.size.y:
				height = bounds.size.y
				width = minf(bounds.size.x, area / maxf(height, profile.geometric_tolerance))
			if width * height < minimum_area - profile.geometric_tolerance:
				continue
			for relative in order:
				if parcel_candidates >= profile.maximum_candidates_per_parcel:
					return PackedVector2Array()
				parcel_candidates += 1
				result.candidate_evaluations += 1
				result.generation_operation_count += 1
				if _cap_exceeded(profile, result):
					return PackedVector2Array()
				var center := bounds.position + Vector2(bounds.size.x * relative.x, bounds.size.y * relative.y)
				var candidate := canonicalize_boundary(PackedVector2Array([
					center + Vector2(-width, -height) * 0.5,
					center + Vector2(width, -height) * 0.5,
					center + Vector2(width, height) * 0.5,
					center + Vector2(-width, height) * 0.5,
				]), profile)
				if _site_valid(candidate, parcel.boundary, exclusions, profile.site_clearance, profile.geometric_tolerance) and bool(_terrain_evidence(world, candidate, terrain, terrain_origin_cell, profile)["terrain_valid"]):
					return candidate
	return PackedVector2Array()


static func _site_valid(
	candidate: PackedVector2Array,
	parent: PackedVector2Array,
	exclusions: Array[PackedVector2Array],
	clearance: float,
	tolerance: float
) -> bool:
	if candidate.size() < 3:
		return false
	for point in candidate:
		if not point_inside_or_boundary(point, parent, tolerance):
			return false
	for exclusion in exclusions:
		if polygons_violate_clearance(candidate, exclusion, clearance, tolerance):
			return false
	return true


static func polygons_overlap(a: PackedVector2Array, b: PackedVector2Array, tolerance := 0.01) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false
	if not FoundationBlockRecord._bounds_for_boundary(a).intersects(FoundationBlockRecord._bounds_for_boundary(b), true):
		return false
	for component in Geometry2D.intersect_polygons(a, b):
		if absf(FoundationBlockRecord._signed_area(component)) > tolerance:
			return true
	return false


static func polygons_violate_clearance(
	a: PackedVector2Array,
	b: PackedVector2Array,
	clearance: float,
	tolerance := 0.01
) -> bool:
	if polygons_overlap(a, b, tolerance):
		return true
	if clearance <= tolerance or a.size() < 2 or b.size() < 2:
		return false
	if not FoundationBlockRecord._bounds_for_boundary(a).grow(clearance).intersects(FoundationBlockRecord._bounds_for_boundary(b), true):
		return false
	for point in a:
		for index in range(b.size()):
			if Geometry2D.get_closest_point_to_segment(point, b[index], b[(index + 1) % b.size()]).distance_to(point) < clearance - tolerance:
				return true
	for point in b:
		for index in range(a.size()):
			if Geometry2D.get_closest_point_to_segment(point, a[index], a[(index + 1) % a.size()]).distance_to(point) < clearance - tolerance:
				return true
	return false


static func point_inside_or_boundary(point: Vector2, polygon: PackedVector2Array, tolerance := 0.01) -> bool:
	if Geometry2D.is_point_in_polygon(point, polygon):
		return true
	for index in range(polygon.size()):
		if Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()]).distance_to(point) <= tolerance:
			return true
	return false


static func canonicalize_boundary(points: PackedVector2Array, profile: FoundationSiteFeatureGenerationProfile) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		var quantized := Vector2(
			round(point.x / profile.point_quantization) * profile.point_quantization,
			round(point.y / profile.point_quantization) * profile.point_quantization
		)
		if result.is_empty() or result[result.size() - 1].distance_to(quantized) > profile.geometric_tolerance:
			result.append(quantized)
	if result.size() > 1 and result[0].distance_to(result[result.size() - 1]) <= profile.geometric_tolerance:
		result.remove_at(result.size() - 1)
	if result.size() >= 3 and FoundationBlockRecord._signed_area(result) < 0.0:
		result.reverse()
	return result


static func boundary_key(boundary: PackedVector2Array, profile: FoundationSiteFeatureGenerationProfile) -> String:
	var parts := PackedStringArray()
	for point in boundary:
		parts.append("%d,%d" % [roundi(point.x / profile.point_quantization), roundi(point.y / profile.point_quantization)])
	return ";".join(parts)


static func _primary_frontage(parcel: FoundationParcelRecord) -> FoundationParcelFrontageReference:
	if parcel.primary_frontage_index < 0 or parcel.primary_frontage_index >= parcel.frontage_references.size():
		return null
	return parcel.frontage_references[parcel.primary_frontage_index]


static func _frontage_orientation(parcel: FoundationParcelRecord) -> float:
	var frontage := _primary_frontage(parcel)
	if frontage == null or frontage.parcel_boundary_segment_index < 0 or frontage.parcel_boundary_segment_index >= parcel.boundary.size():
		return 0.0
	var first := parcel.boundary[frontage.parcel_boundary_segment_index]
	var second := parcel.boundary[(frontage.parcel_boundary_segment_index + 1) % parcel.boundary.size()]
	return fposmod(rad_to_deg((second - first).angle()), 360.0)


static func _parking_orientation(parcel: FoundationParcelRecord, layout_seed: int) -> float:
	var frontage := _primary_frontage(parcel)
	if frontage == null or frontage.parcel_boundary_segment_index < 0 or frontage.parcel_boundary_segment_index >= parcel.boundary.size():
		return 0.0 if layout_seed % 2 == 0 else 90.0
	var first := parcel.boundary[frontage.parcel_boundary_segment_index]
	var second := parcel.boundary[(frontage.parcel_boundary_segment_index + 1) % parcel.boundary.size()]
	var direction := (second - first).normalized()
	if absf(absf(direction.x) - absf(direction.y)) <= 0.10:
		return 0.0 if layout_seed % 2 == 0 else 90.0
	return 0.0 if absf(direction.x) > absf(direction.y) else 90.0


static func _base_elevation(world: FoundationWorldData, context: Dictionary, terrain_evidence: Dictionary) -> float:
	var building := context["building"] as FoundationBuildingRecord
	if building != null and world.terrain_grading_plan != null:
		for operation in world.terrain_grading_plan.operations:
			if operation.operation_kind == FoundationTerrainGradingOperation.KIND_BUILDING_PAD and operation.source_record_id == building.stable_id:
				return (operation.target_elevation_min + operation.target_elevation_max) * 0.5
	if bool(terrain_evidence.get("terrain_available", false)):
		return float(terrain_evidence.get("terrain_elevation", 0.0))
	return building.base_elevation if building != null else 0.0


static func _terrain_evidence(
	world: FoundationWorldData,
	footprint: PackedVector2Array,
	terrain: FoundationTerrainData,
	terrain_origin_cell: Vector2i,
	profile: FoundationSiteFeatureGenerationProfile
) -> Dictionary:
	var grading_state := String(world.terrain_grading_plan.state) if world.terrain_grading_plan != null else "none"
	if terrain == null:
		return {
			"terrain_available": false, "terrain_valid": true, "terrain_elevation": 0.0,
			"terrain_maximum_slope": 0.0, "terrain_elevation_delta": 0.0,
			"grading_plan_state": grading_state,
		}
	var sampler := FoundationTerrainSampler.new(terrain)
	var origin_world := Vector2(terrain_origin_cell) * terrain.cell_size
	var samples := footprint.duplicate()
	samples.append(FoundationBlockRecord._polygon_centroid(footprint))
	var minimum_elevation := INF
	var maximum_elevation := -INF
	var maximum_slope := 0.0
	var buildable := true
	var terrain_size := Vector2(terrain.grid_cells) * terrain.cell_size
	for world_point in samples:
		var local_point := world_point - origin_world
		if local_point.x < 0.0 or local_point.y < 0.0 or local_point.x >= terrain_size.x or local_point.y >= terrain_size.y:
			buildable = false
			continue
		var elevation := sampler.get_height_at_world(local_point)
		var slope := sampler.get_slope_degrees_at_world(local_point)
		minimum_elevation = minf(minimum_elevation, elevation)
		maximum_elevation = maxf(maximum_elevation, elevation)
		maximum_slope = maxf(maximum_slope, slope)
		buildable = buildable and sampler.is_buildable_at_world(local_point, profile.maximum_site_slope_degrees)
	var elevation_delta := maximum_elevation - minimum_elevation if minimum_elevation < INF else INF
	buildable = buildable and elevation_delta <= profile.maximum_site_elevation_delta
	return {
		"terrain_available": true, "terrain_valid": buildable,
		"terrain_elevation": (minimum_elevation + maximum_elevation) * 0.5 if minimum_elevation < INF else 0.0,
		"terrain_maximum_slope": maximum_slope, "terrain_elevation_delta": elevation_delta,
		"grading_plan_state": grading_state,
	}


static func _repair_id(
	world: FoundationWorldData,
	entity_type: StringName,
	parent_id: StringName,
	semantic: String,
	expected_id: StringName,
	profile: FoundationSiteFeatureGenerationProfile
) -> StringName:
	if world.get_record(expected_id) == null:
		return expected_id
	var ordinal := 1
	while true:
		var candidate := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			entity_type, parent_id, "%s|repair:%d" % [semantic, ordinal]
		)
		if world.get_record(candidate) == null:
			return candidate
		ordinal += 1
	return &""


static func _refresh_ownership(world: FoundationWorldData, record: FoundationSpatialRecord) -> void:
	record.set_owning_chunks(world.coordinate_system.world_bounds_to_chunks(record.world_bounds))
	var region_set: Dictionary = {}
	for chunk in record.owning_chunks:
		region_set[world.coordinate_system.chunk_to_region(chunk)] = true
	var regions: Array[Vector2i] = []
	for region: Vector2i in region_set:
		regions.append(region)
	record.set_owning_regions(regions)


static func _add_exclusion(exclusions_by_parcel: Dictionary, parcel_id: StringName, footprint: PackedVector2Array) -> void:
	if not exclusions_by_parcel.has(parcel_id):
		exclusions_by_parcel[parcel_id] = []
	(exclusions_by_parcel[parcel_id] as Array).append(footprint.duplicate())


static func _get_exclusions(exclusions_by_parcel: Dictionary, parcel_id: StringName) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for footprint: PackedVector2Array in exclusions_by_parcel.get(parcel_id, []):
		result.append(footprint)
	return result


static func _cap_exceeded(profile: FoundationSiteFeatureGenerationProfile, result: FoundationSiteFeatureGenerationResult) -> bool:
	return result.generation_operation_count > profile.maximum_generation_operations


static func _cap_failure(
	world: FoundationWorldData,
	profile: FoundationSiteFeatureGenerationProfile,
	result: FoundationSiteFeatureGenerationResult
) -> FoundationSiteFeatureGenerationResult:
	clear_generated(world)
	result.add_diagnostic(&"generation_operation_cap", FoundationSiteFeatureValidationIssue.SEVERITY_ERROR)
	_set_layer_metadata(world, profile, result)
	return result.fail("Site-feature generation exceeded its configured operation cap.")


static func _set_layer_metadata(
	world: FoundationWorldData,
	profile: FoundationSiteFeatureGenerationProfile,
	result: FoundationSiteFeatureGenerationResult
) -> void:
	var metadata := {
		"format_version": 1,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"profile": profile.to_dict(),
		"diagnostics": result.diagnostics.duplicate(true),
		"counts": result.to_dict(),
	}
	world.get_layer(FoundationWorldData.PARKING_FACILITY_LAYER).metadata = metadata.duplicate(true)
	world.get_layer(FoundationWorldData.PUBLIC_FEATURE_LAYER).metadata = metadata.duplicate(true)


static func _point_dict(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}
