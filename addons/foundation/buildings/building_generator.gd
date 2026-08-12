class_name FoundationBuildingGenerator
extends RefCounted

## Deterministic parcel-aware footprint and primitive-massing generation.

const SOURCE_PASS: StringName = &"phase_5_building_massing"


static func generate(
	world: FoundationWorldData,
	profile: FoundationBuildingGenerationProfile = null
) -> FoundationBuildingGenerationResult:
	var result := FoundationBuildingGenerationResult.new()
	if world == null:
		return result.fail("Building generation requires FoundationWorldData.")
	var active_profile := profile if profile != null else FoundationBuildingGenerationProfile.new()
	var errors := active_profile.validation_errors()
	if not errors.is_empty():
		return result.fail("Invalid building generation profile: %s" % "; ".join(errors))
	world.register_layer_type(FoundationWorldData.BUILDING_LAYER)
	result.preserved_building_count = _remove_replaceable_buildings(world)
	for parcel in world.get_parcels():
		_generate_for_parcel(world, parcel, active_profile, result)
		if result.generation_operation_count > active_profile.maximum_generation_operations:
			return result.fail("Building generation exceeded its configured operation cap.")

	var issues := FoundationBuildingValidator.validate(world, active_profile, true)
	for issue in issues:
		result.diagnostics.append(issue.to_dict())
	result.diagnostics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	result.success = true
	_set_layer_metadata(world, active_profile, result)
	return result


static func clear_generated(world: FoundationWorldData) -> int:
	var removed := 0
	for building in world.get_buildings():
		if building.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(building.stable_id)
			removed += 1
	return removed


static func _remove_replaceable_buildings(world: FoundationWorldData) -> int:
	var retained: Array[FoundationBuildingRecord] = []
	for building in world.get_buildings():
		if building.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(building.stable_id)
		else:
			retained.append(building)
	for building in retained:
		world.register_record(building)
	return retained.size()


static func _generate_for_parcel(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	profile: FoundationBuildingGenerationProfile,
	result: FoundationBuildingGenerationResult
) -> void:
	if parcel.validation_state == FoundationParcelRecord.INVALID:
		_skip_parcel(result, parcel, &"invalid_parent_parcel", "Parcel validation state is invalid.")
		return
	if not parcel.buildable or parcel.access_state != FoundationParcelRecord.ACCESS_DIRECT:
		_skip_parcel(result, parcel, &"parcel_not_buildable", "Parcel is not directly buildable.")
		return
	if parcel.boundary.size() < 3 or parcel.area <= profile.geometric_epsilon:
		_skip_parcel(result, parcel, &"invalid_parent_geometry", "Parcel geometry is degenerate.")
		return
	if parcel.primary_frontage_index < 0 or parcel.primary_frontage_index >= parcel.frontage_references.size():
		_skip_parcel(result, parcel, &"missing_primary_frontage", "Buildable parcel has no primary frontage reference.")
		return
	var primary := parcel.frontage_references[parcel.primary_frontage_index]
	if primary.parcel_boundary_segment_index < 0 or primary.parcel_boundary_segment_index >= parcel.boundary.size():
		_skip_parcel(result, parcel, &"invalid_primary_frontage", "Primary frontage segment is outside the parcel boundary.")
		return

	var target_coverage := _target_coverage(world, parcel, profile)
	var footprint := _create_footprint(parcel, primary, target_coverage, profile, result)
	var footprint_area := absf(FoundationBlockRecord._signed_area(footprint))
	if footprint.size() < 3 or footprint_area < profile.minimum_footprint_area:
		_skip_parcel(result, parcel, &"setbacks_exhaust_parcel", "Configured setbacks leave no usable footprint.")
		return

	var expected_id := _building_id(world, parcel.stable_id, profile)
	var preserved := world.get_record(expected_id) as FoundationBuildingRecord
	if preserved != null and preserved.parent_id == parcel.stable_id and _boundaries_equal(
		preserved.footprint, footprint, profile.geometric_epsilon
	):
		return
	var stable_id := expected_id
	if world.get_record(stable_id) != null:
		stable_id = _repair_building_id(world, parcel.stable_id, profile)
	var building := _create_building(world, parcel, primary, footprint, target_coverage, stable_id, profile)
	world.register_record(building)
	result.generated_building_count += 1
	result.footprint_area_total += building.footprint_area
	result.gross_floor_area_total += building.gross_floor_area


static func _skip_parcel(
	result: FoundationBuildingGenerationResult,
	parcel: FoundationParcelRecord,
	kind: StringName,
	message: String
) -> void:
	result.skipped_parcel_count += 1
	result.add_diagnostic(kind, FoundationBuildingValidationIssue.SEVERITY_INFO, {
		"parent_parcel_id": String(parcel.stable_id),
		"message": message,
		"point": _point_dict(parcel.label_point),
	})


static func _create_footprint(
	parcel: FoundationParcelRecord,
	primary: FoundationParcelFrontageReference,
	target_coverage: float,
	profile: FoundationBuildingGenerationProfile,
	result: FoundationBuildingGenerationResult
) -> PackedVector2Array:
	var source_boundary := parcel.boundary
	var components := _offset_components(source_boundary, profile.side_setback, profile, result)
	if components.is_empty():
		return PackedVector2Array()

	var primary_segment := primary.parcel_boundary_segment_index
	var primary_a := source_boundary[primary_segment]
	var primary_b := source_boundary[(primary_segment + 1) % source_boundary.size()]
	var inward := _inward_normal(primary_a, primary_b)
	var maximum_depth := 0.0
	for point in source_boundary:
		maximum_depth = maxf(maximum_depth, (point - primary_a).dot(inward))
	var rear_limit := maximum_depth - profile.rear_setback
	if not profile.allow_long_form_massing:
		rear_limit = minf(rear_limit, profile.front_setback + profile.maximum_footprint_depth)
	if rear_limit <= profile.front_setback + profile.geometric_epsilon:
		return PackedVector2Array()
	var clip_extent := maxf(parcel.world_bounds.size.x, parcel.world_bounds.size.y) * 6.0 + 32.0
	components = _clip_components(
		components,
		_depth_strip(primary_a, primary_b, profile.front_setback, rear_limit, clip_extent),
		profile,
		result
	)
	if components.is_empty():
		return PackedVector2Array()
	if not profile.allow_long_form_massing:
		components = _clip_components(
			components,
			_frontage_span_window(primary_a, primary_b, profile.maximum_frontage_span, clip_extent),
			profile,
			result
		)
		if components.is_empty():
			return PackedVector2Array()

	var frontage_segments := _unique_frontage_segments(parcel)
	for segment_index in frontage_segments:
		if segment_index == primary_segment or profile.corner_side_setback <= profile.side_setback + profile.geometric_epsilon:
			continue
		var first := source_boundary[segment_index]
		var second := source_boundary[(segment_index + 1) % source_boundary.size()]
		components = _clip_components(
			components,
			_inward_half_plane(first, second, profile.corner_side_setback, clip_extent),
			profile,
			result
		)
		if components.is_empty():
			return PackedVector2Array()

	var footprint := _largest_component(components, profile)
	if not profile.allow_long_form_massing:
		footprint = _compact_component(footprint, primary_a, primary_b, profile, result)
	var target_area := parcel.area * target_coverage
	if absf(FoundationBlockRecord._signed_area(footprint)) > target_area + profile.geometric_epsilon:
		footprint = _fit_coverage(footprint, target_area, profile, result)
	if not profile.allow_long_form_massing:
		footprint = _compact_component(footprint, primary_a, primary_b, profile, result)
	return canonicalize_boundary(footprint, profile)


static func _offset_components(
	boundary: PackedVector2Array,
	inset: float,
	profile: FoundationBuildingGenerationProfile,
	result: FoundationBuildingGenerationResult
) -> Array[PackedVector2Array]:
	result.generation_operation_count += 1
	var components: Array[PackedVector2Array] = []
	var raw_components: Array[PackedVector2Array]
	if inset <= profile.geometric_epsilon:
		raw_components = [boundary]
	else:
		raw_components = Geometry2D.offset_polygon(boundary, -inset)
	for raw in raw_components:
		var canonical := canonicalize_boundary(raw, profile)
		if canonical.size() >= 3 and absf(FoundationBlockRecord._signed_area(canonical)) > profile.geometric_epsilon:
			components.append(canonical)
	_sort_components(components, profile)
	return components


static func _clip_components(
	components: Array[PackedVector2Array],
	clip_polygon: PackedVector2Array,
	profile: FoundationBuildingGenerationProfile,
	result: FoundationBuildingGenerationResult
) -> Array[PackedVector2Array]:
	var clipped: Array[PackedVector2Array] = []
	for component in components:
		result.generation_operation_count += 1
		for raw in Geometry2D.intersect_polygons(component, clip_polygon):
			var canonical := canonicalize_boundary(raw, profile)
			if canonical.size() >= 3 and absf(FoundationBlockRecord._signed_area(canonical)) > profile.geometric_epsilon:
				clipped.append(canonical)
	_sort_components(clipped, profile)
	return clipped


static func _fit_coverage(
	boundary: PackedVector2Array,
	target_area: float,
	profile: FoundationBuildingGenerationProfile,
	result: FoundationBuildingGenerationResult
) -> PackedVector2Array:
	var bounds := FoundationBlockRecord._bounds_for_boundary(boundary)
	var low := 0.0
	var high := maxf(bounds.size.x, bounds.size.y)
	var best := PackedVector2Array()
	for _iteration in range(profile.coverage_search_iterations):
		var inset := (low + high) * 0.5
		var components := _offset_components(boundary, inset, profile, result)
		var candidate := _largest_component(components, profile)
		var area := absf(FoundationBlockRecord._signed_area(candidate))
		if candidate.is_empty() or area < target_area:
			if area >= profile.minimum_footprint_area:
				best = candidate
			high = inset
		else:
			low = inset
	if best.is_empty():
		var components := _offset_components(boundary, high, profile, result)
		var candidate := _largest_component(components, profile)
		if absf(FoundationBlockRecord._signed_area(candidate)) >= profile.minimum_footprint_area:
			best = candidate
	return best


static func _create_building(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	primary: FoundationParcelFrontageReference,
	footprint: PackedVector2Array,
	target_coverage: float,
	stable_id: StringName,
	profile: FoundationBuildingGenerationProfile
) -> FoundationBuildingRecord:
	var building := FoundationBuildingRecord.new(stable_id, parcel.stable_id, parcel.parent_id, footprint)
	building.target_coverage_ratio = target_coverage
	building.front_setback = profile.front_setback
	building.side_setback = profile.side_setback
	building.rear_setback = profile.rear_setback
	building.corner_side_setback = profile.corner_side_setback
	building.primary_frontage_segment_index = primary.parcel_boundary_segment_index
	building.primary_road_edge_id = primary.road_edge_id
	building.primary_logical_road_id = primary.logical_road_id
	var first := parcel.boundary[primary.parcel_boundary_segment_index]
	var second := parcel.boundary[(primary.parcel_boundary_segment_index + 1) % parcel.boundary.size()]
	building.frontage_direction = -_inward_normal(first, second)
	building.orientation_degrees = rad_to_deg((second - first).angle())
	var oriented_extents := _oriented_extents(footprint, first, second)
	building.frontage_span = float(oriented_extents["span"])
	building.footprint_depth = float(oriented_extents["depth"])
	building.footprint_aspect_ratio = _aspect_ratio(building.frontage_span, building.footprint_depth)
	building.long_form = profile.allow_long_form_massing and (
		building.frontage_span > profile.maximum_frontage_span + profile.geometric_epsilon
		or building.footprint_depth > profile.maximum_footprint_depth + profile.geometric_epsilon
		or building.footprint_aspect_ratio > profile.maximum_footprint_aspect_ratio + profile.geometric_epsilon
	)
	building.base_elevation = profile.base_elevation
	building.floor_height = profile.floor_height
	var height_floor_cap := maxi(1, floori(profile.maximum_building_height / profile.floor_height))
	var maximum_floors := mini(profile.maximum_floor_count, height_floor_cap)
	var floor_span := maxi(0, maximum_floors - profile.minimum_floor_count)
	var floor_seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [
		profile.STREAM_FLOOR_COUNT, parcel.stable_id,
	]))
	building.floor_count = profile.minimum_floor_count + int(floor_seed % (floor_span + 1))
	building.refresh_metrics(parcel.area)
	building.refresh_massing()
	building.source_pass = SOURCE_PASS
	building.source_version = profile.generator_version
	building.tags = PackedStringArray(["phase_5", "building_footprint", "primitive_massing"])
	if building.long_form:
		building.tags.append("long_form_exception")
	building.metadata = {
		"footprint_key": boundary_key(footprint, profile),
		"parent_parcel_kind": String(parcel.parcel_kind),
	}
	return building


static func _target_coverage(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	profile: FoundationBuildingGenerationProfile
) -> float:
	var seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [
		profile.STREAM_COVERAGE, parcel.stable_id,
	]))
	var weight := float(seed % 10001) / 10000.0
	return lerpf(profile.minimum_coverage_ratio, profile.maximum_coverage_ratio, weight)


static func _depth_strip(
	a: Vector2,
	b: Vector2,
	front_depth: float,
	rear_depth: float,
	extent: float
) -> PackedVector2Array:
	var tangent := (b - a).normalized()
	var inward := _inward_normal(a, b)
	return PackedVector2Array([
		a - tangent * extent + inward * front_depth,
		a + tangent * extent + inward * front_depth,
		a + tangent * extent + inward * rear_depth,
		a - tangent * extent + inward * rear_depth,
	])


static func _frontage_span_window(
	a: Vector2,
	b: Vector2,
	maximum_span: float,
	extent: float
) -> PackedVector2Array:
	var tangent := (b - a).normalized()
	var inward := _inward_normal(a, b)
	var center := (a + b) * 0.5
	var half_span := maximum_span * 0.5
	return PackedVector2Array([
		center - tangent * half_span - inward * extent,
		center + tangent * half_span - inward * extent,
		center + tangent * half_span + inward * extent,
		center - tangent * half_span + inward * extent,
	])


static func _compact_component(
	boundary: PackedVector2Array,
	frontage_a: Vector2,
	frontage_b: Vector2,
	profile: FoundationBuildingGenerationProfile,
	result: FoundationBuildingGenerationResult
) -> PackedVector2Array:
	if boundary.size() < 3:
		return PackedVector2Array()
	var extents := _oriented_extents(boundary, frontage_a, frontage_b)
	var minimum_tangent := float(extents["minimum_tangent"])
	var maximum_tangent := float(extents["maximum_tangent"])
	var minimum_depth := float(extents["minimum_depth"])
	var maximum_depth := float(extents["maximum_depth"])
	var span := maximum_tangent - minimum_tangent
	var depth := maximum_depth - minimum_depth
	if span <= profile.geometric_epsilon or depth <= profile.geometric_epsilon:
		return PackedVector2Array()
	var changed := false
	if span > profile.maximum_frontage_span:
		var center := (minimum_tangent + maximum_tangent) * 0.5
		minimum_tangent = center - profile.maximum_frontage_span * 0.5
		maximum_tangent = center + profile.maximum_frontage_span * 0.5
		span = profile.maximum_frontage_span
		changed = true
	if depth > profile.maximum_footprint_depth:
		maximum_depth = minimum_depth + profile.maximum_footprint_depth
		depth = profile.maximum_footprint_depth
		changed = true
	if span > depth * profile.maximum_footprint_aspect_ratio:
		var center := (minimum_tangent + maximum_tangent) * 0.5
		var compact_span := depth * profile.maximum_footprint_aspect_ratio
		minimum_tangent = center - compact_span * 0.5
		maximum_tangent = center + compact_span * 0.5
		changed = true
	elif depth > span * profile.maximum_footprint_aspect_ratio:
		maximum_depth = minimum_depth + span * profile.maximum_footprint_aspect_ratio
		changed = true
	if not changed:
		return boundary
	var tangent := (frontage_b - frontage_a).normalized()
	var inward := _inward_normal(frontage_a, frontage_b)
	var window := PackedVector2Array([
		frontage_a + tangent * minimum_tangent + inward * minimum_depth,
		frontage_a + tangent * maximum_tangent + inward * minimum_depth,
		frontage_a + tangent * maximum_tangent + inward * maximum_depth,
		frontage_a + tangent * minimum_tangent + inward * maximum_depth,
	])
	return _largest_component(_clip_components([boundary], window, profile, result), profile)


static func _oriented_extents(
	boundary: PackedVector2Array,
	frontage_a: Vector2,
	frontage_b: Vector2
) -> Dictionary:
	var tangent := (frontage_b - frontage_a).normalized()
	var inward := _inward_normal(frontage_a, frontage_b)
	var minimum_tangent := INF
	var maximum_tangent := -INF
	var minimum_depth := INF
	var maximum_depth := -INF
	for point in boundary:
		var relative := point - frontage_a
		var tangent_projection := relative.dot(tangent)
		var depth_projection := relative.dot(inward)
		minimum_tangent = minf(minimum_tangent, tangent_projection)
		maximum_tangent = maxf(maximum_tangent, tangent_projection)
		minimum_depth = minf(minimum_depth, depth_projection)
		maximum_depth = maxf(maximum_depth, depth_projection)
	return {
		"minimum_tangent": minimum_tangent,
		"maximum_tangent": maximum_tangent,
		"minimum_depth": minimum_depth,
		"maximum_depth": maximum_depth,
		"span": maximum_tangent - minimum_tangent,
		"depth": maximum_depth - minimum_depth,
	}


static func _aspect_ratio(first: float, second: float) -> float:
	var shortest := minf(first, second)
	if shortest <= 0.000001:
		return 0.0
	return maxf(first, second) / shortest


static func _inward_half_plane(a: Vector2, b: Vector2, depth: float, extent: float) -> PackedVector2Array:
	var tangent := (b - a).normalized()
	var inward := _inward_normal(a, b)
	return PackedVector2Array([
		a - tangent * extent + inward * depth,
		a + tangent * extent + inward * depth,
		a + tangent * extent + inward * extent,
		a - tangent * extent + inward * extent,
	])


static func _inward_normal(a: Vector2, b: Vector2) -> Vector2:
	var direction := (b - a).normalized()
	return Vector2(-direction.y, direction.x)


static func _unique_frontage_segments(parcel: FoundationParcelRecord) -> Array[int]:
	var unique: Dictionary = {}
	for reference in parcel.frontage_references:
		if reference.parcel_boundary_segment_index >= 0 and reference.parcel_boundary_segment_index < parcel.boundary.size():
			unique[reference.parcel_boundary_segment_index] = true
	var segments: Array[int] = []
	for segment_index: int in unique:
		segments.append(segment_index)
	segments.sort()
	return segments


static func canonicalize_boundary(
	points: PackedVector2Array,
	profile: FoundationBuildingGenerationProfile
) -> PackedVector2Array:
	var normalized := PackedVector2Array()
	for point in points:
		var quantized := Vector2(
			round(point.x / profile.point_quantization) * profile.point_quantization,
			round(point.y / profile.point_quantization) * profile.point_quantization
		)
		if normalized.is_empty() or normalized[normalized.size() - 1].distance_to(quantized) > profile.geometric_epsilon:
			normalized.append(quantized)
	if normalized.size() > 1 and normalized[0].distance_to(normalized[normalized.size() - 1]) <= profile.geometric_epsilon:
		normalized.remove_at(normalized.size() - 1)
	var changed := true
	while changed and normalized.size() >= 3:
		changed = false
		for index in range(normalized.size()):
			var previous := normalized[(index - 1 + normalized.size()) % normalized.size()]
			var current := normalized[index]
			var next := normalized[(index + 1) % normalized.size()]
			if absf((current - previous).cross(next - current)) <= profile.geometric_epsilon and (current - previous).dot(next - current) >= 0.0:
				normalized.remove_at(index)
				changed = true
				break
	if normalized.size() < 3:
		return PackedVector2Array()
	if FoundationBlockRecord._signed_area(normalized) < 0.0:
		normalized.reverse()
	var first_index := 0
	for index in range(1, normalized.size()):
		if normalized[index].x < normalized[first_index].x or (
			is_equal_approx(normalized[index].x, normalized[first_index].x)
			and normalized[index].y < normalized[first_index].y
		):
			first_index = index
	var canonical := PackedVector2Array()
	for offset in range(normalized.size()):
		canonical.append(normalized[(first_index + offset) % normalized.size()])
	return canonical


static func boundary_key(
	boundary: PackedVector2Array,
	profile: FoundationBuildingGenerationProfile
) -> String:
	var parts := PackedStringArray()
	for point in boundary:
		parts.append("%d,%d" % [
			roundi(point.x / profile.point_quantization),
			roundi(point.y / profile.point_quantization),
		])
	return ";".join(parts)


static func _largest_component(
	components: Array[PackedVector2Array],
	profile: FoundationBuildingGenerationProfile
) -> PackedVector2Array:
	if components.is_empty():
		return PackedVector2Array()
	_sort_components(components, profile)
	return components[0]


static func _sort_components(
	components: Array[PackedVector2Array],
	profile: FoundationBuildingGenerationProfile
) -> void:
	components.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		var a_area := absf(FoundationBlockRecord._signed_area(a))
		var b_area := absf(FoundationBlockRecord._signed_area(b))
		if not is_equal_approx(a_area, b_area):
			return a_area > b_area
		return boundary_key(a, profile) < boundary_key(b, profile)
	)


static func _boundaries_equal(
	first: PackedVector2Array,
	second: PackedVector2Array,
	epsilon: float
) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if first[index].distance_to(second[index]) > epsilon:
			return false
	return true


static func _building_id(
	world: FoundationWorldData,
	parcel_id: StringName,
	profile: FoundationBuildingGenerationProfile
) -> StringName:
	return FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		FoundationBuildingRecord.ENTITY_TYPE, parcel_id, "primary_massing"
	)


static func _repair_building_id(
	world: FoundationWorldData,
	parcel_id: StringName,
	profile: FoundationBuildingGenerationProfile
) -> StringName:
	var ordinal := 1
	while true:
		var candidate := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			FoundationBuildingRecord.ENTITY_TYPE, parcel_id, "primary_massing|repair:%d" % ordinal
		)
		if world.get_record(candidate) == null:
			return candidate
		ordinal += 1
	return &""


static func _set_layer_metadata(
	world: FoundationWorldData,
	profile: FoundationBuildingGenerationProfile,
	result: FoundationBuildingGenerationResult
) -> void:
	world.get_layer(FoundationWorldData.BUILDING_LAYER).metadata = {
		"format_version": 2,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"profile": profile.to_dict(),
		"diagnostics": result.diagnostics.duplicate(true),
		"counts": result.to_dict(),
	}


static func _point_dict(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}
