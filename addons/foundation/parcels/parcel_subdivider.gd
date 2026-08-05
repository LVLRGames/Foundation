class_name FoundationParcelSubdivider
extends RefCounted

## Deterministic frontage-aware subdivision of Phase 3 polygons using clipped strip partitions.

const SOURCE_PASS: StringName = &"phase_4_parcel_subdivision"


static func generate(
	world: FoundationWorldData,
	profile: FoundationParcelGenerationProfile = null
) -> FoundationParcelGenerationResult:
	var result := FoundationParcelGenerationResult.new()
	if world == null:
		return result.fail("Parcel subdivision requires FoundationWorldData.")
	var active_profile := profile if profile != null else FoundationParcelGenerationProfile.new()
	var errors := active_profile.validation_errors()
	if not errors.is_empty():
		return result.fail("Invalid parcel generation profile: %s" % "; ".join(errors))
	world.register_layer_type(FoundationWorldData.PARCEL_LAYER)
	result.preserved_parcel_count = _remove_replaceable_parcels(world)
	for block in world.get_blocks():
		if block.validation_state != FoundationBlockRecord.VALID or block.outer_boundary.size() < 3:
			result.skipped_block_count += 1
			result.add_diagnostic(&"invalid_parent_block", FoundationParcelValidationIssue.SEVERITY_ERROR, {
				"parent_block_id": String(block.stable_id), "point": _point_dict(block.label_point),
			})
			continue
		_subdivide_block(world, block, active_profile, result)
		if result.subdivision_operation_count > active_profile.maximum_subdivision_operations:
			return result.fail("Parcel subdivision exceeded its configured operation cap.")

	var issues := FoundationParcelValidator.validate(world, active_profile, true)
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
	for parcel in world.get_parcels():
		if parcel.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(parcel.stable_id)
			removed += 1
	return removed


static func _remove_replaceable_parcels(world: FoundationWorldData) -> int:
	var retained: Array[FoundationParcelRecord] = []
	for parcel in world.get_parcels():
		if parcel.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(parcel.stable_id)
		else:
			retained.append(parcel)
	for parcel in retained:
		world.register_record(parcel)
	return retained.size()


static func _subdivide_block(
	world: FoundationWorldData,
	block: FoundationBlockRecord,
	profile: FoundationParcelGenerationProfile,
	result: FoundationParcelGenerationResult
) -> void:
	var canonical_block := canonicalize_boundary(block.outer_boundary, profile)
	if canonical_block.size() < 3 or not is_simple_polygon(canonical_block, profile.geometric_epsilon):
		result.skipped_block_count += 1
		result.add_diagnostic(&"invalid_parent_geometry", FoundationParcelValidationIssue.SEVERITY_ERROR, {
			"parent_block_id": String(block.stable_id), "point": _point_dict(block.label_point),
		})
		return
	result.parent_area_total += block.area
	var bounds := FoundationBlockRecord._bounds_for_boundary(canonical_block)
	var split_x := _choose_split_x(world, block, bounds, profile)
	var axis_extent := bounds.size.x if split_x else bounds.size.y
	var cross_extent := bounds.size.y if split_x else bounds.size.x
	var desired_width := clampf(
		profile.target_parcel_area / maxf(cross_extent, profile.minimum_depth),
		profile.minimum_frontage,
		profile.maximum_frontage
	)
	var spacing_seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [profile.STREAM_SPLIT_SPACING, block.stable_id]))
	var spacing_factor := 0.82 + float(spacing_seed % 3701) / 10000.0
	desired_width = maxf(profile.minimum_frontage, desired_width * spacing_factor)
	var strip_count := maxi(1, ceili(axis_extent / maxf(desired_width, profile.point_quantization)))
	strip_count = mini(strip_count, active_strip_cap(profile))
	var split_positions := _split_positions(world, block, axis_extent, strip_count, profile)
	var block_area_from_parcels := 0.0
	for strip_index in range(strip_count):
		result.subdivision_operation_count += 1
		var start := split_positions[strip_index]
		var finish := split_positions[strip_index + 1]
		var clip_polygon := _strip_polygon(bounds, split_x, start, finish, profile.geometric_epsilon)
		var components := Geometry2D.intersect_polygons(canonical_block, clip_polygon)
		var canonical_components: Array[PackedVector2Array] = []
		for component in components:
			var canonical := canonicalize_boundary(component, profile)
			if canonical.size() >= 3 and absf(FoundationBlockRecord._signed_area(canonical)) > profile.geometric_epsilon:
				canonical_components.append(canonical)
		canonical_components.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
			return boundary_key(a, profile) < boundary_key(b, profile)
		)
		for component_index in range(canonical_components.size()):
			var boundary := canonical_components[component_index]
			var expected_id := _parcel_id(world, block.stable_id, boundary_key(boundary, profile), profile)
			var preserved := world.get_record(expected_id) as FoundationParcelRecord
			if preserved != null and preserved.parent_id == block.stable_id and _boundaries_equal(preserved.boundary, boundary, profile.geometric_epsilon):
				block_area_from_parcels += preserved.area
				continue
			var references := _derive_frontage(world, block, boundary, profile, result)
			var parcel := _create_parcel(world, block, boundary, references, profile)
			_register_parcel(world, parcel, profile, result)
			block_area_from_parcels += parcel.area
	result.parcel_area_total += block_area_from_parcels
	var coverage_error := absf(block_area_from_parcels - block.area)
	result.coverage_error_total += coverage_error
	if coverage_error > maxf(profile.point_quantization * profile.point_quantization * 8.0, block.area * 0.00001):
		result.add_diagnostic(&"parent_coverage_gap", FoundationParcelValidationIssue.SEVERITY_ERROR, {
			"parent_block_id": String(block.stable_id), "coverage_error": coverage_error,
			"point": _point_dict(block.label_point),
		})


static func _choose_split_x(
	world: FoundationWorldData,
	block: FoundationBlockRecord,
	bounds: Rect2,
	profile: FoundationParcelGenerationProfile
) -> bool:
	var longer_is_x := bounds.size.x >= bounds.size.y
	var near_square := absf(bounds.size.x - bounds.size.y) <= maxf(bounds.size.x, bounds.size.y) * 0.35
	if not near_square:
		return longer_is_x
	var seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [profile.STREAM_SPLIT_ORIENTATION, block.stable_id]))
	return seed % 2 == 0


static func _split_positions(
	world: FoundationWorldData,
	block: FoundationBlockRecord,
	extent: float,
	count: int,
	profile: FoundationParcelGenerationProfile
) -> PackedFloat32Array:
	var result := PackedFloat32Array([0.0])
	var base_width := extent / float(count)
	for index in range(1, count):
		var seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s:%d" % [profile.STREAM_SPLIT_SPACING, block.stable_id, index]))
		var centered := float(seed % 2001) / 1000.0 - 1.0
		var position := base_width * float(index) + centered * base_width * 0.18
		position = clampf(position, result[result.size() - 1] + profile.point_quantization, extent - float(count - index) * profile.point_quantization)
		result.append(position)
	result.append(extent)
	return result


static func _strip_polygon(bounds: Rect2, split_x: bool, start: float, finish: float, epsilon: float) -> PackedVector2Array:
	var minimum := bounds.position - Vector2.ONE * epsilon * 4.0
	var maximum := bounds.end + Vector2.ONE * epsilon * 4.0
	if split_x:
		minimum.x = bounds.position.x + start
		maximum.x = bounds.position.x + finish
	else:
		minimum.y = bounds.position.y + start
		maximum.y = bounds.position.y + finish
	return PackedVector2Array([
		minimum, Vector2(maximum.x, minimum.y), maximum, Vector2(minimum.x, maximum.y),
	])


static func _derive_frontage(
	world: FoundationWorldData,
	block: FoundationBlockRecord,
	parcel_boundary: PackedVector2Array,
	profile: FoundationParcelGenerationProfile,
	result: FoundationParcelGenerationResult
) -> Array[FoundationParcelFrontageReference]:
	var references: Array[FoundationParcelFrontageReference] = []
	for parcel_index in range(parcel_boundary.size()):
		var parcel_a := parcel_boundary[parcel_index]
		var parcel_b := parcel_boundary[(parcel_index + 1) % parcel_boundary.size()]
		for block_index in range(block.outer_boundary.size()):
			result.subdivision_operation_count += 1
			var block_a := block.outer_boundary[block_index]
			var block_b := block.outer_boundary[(block_index + 1) % block.outer_boundary.size()]
			var overlap := _collinear_overlap(parcel_a, parcel_b, block_a, block_b, profile.geometric_epsilon)
			if overlap["length"] <= profile.geometric_epsilon:
				continue
			var source_references: Array[FoundationBlockBoundaryReference] = []
			var source_total := 0.0
			for source_reference in block.boundary_references:
				if source_reference.boundary_segment_index == block_index:
					source_references.append(source_reference)
					source_total += source_reference.frontage_length
			for source_reference in source_references:
				var edge := world.get_record(source_reference.road_edge_id) as FoundationRoadEdge
				var logical_id := edge.logical_road_id if edge != null else &""
				var weight := source_reference.frontage_length / source_total if source_total > profile.geometric_epsilon else 1.0 / float(maxi(1, source_references.size()))
				references.append(FoundationParcelFrontageReference.new(
					parcel_index, block_index, source_reference.road_edge_id, logical_id,
					lerpf(source_reference.source_t_start, source_reference.source_t_end, overlap["t_start"]),
					lerpf(source_reference.source_t_start, source_reference.source_t_end, overlap["t_end"]),
					overlap["length"] * weight
				))
	references.sort_custom(FoundationParcelFrontageReference.less)
	return references


static func _create_parcel(
	world: FoundationWorldData,
	block: FoundationBlockRecord,
	boundary: PackedVector2Array,
	references: Array[FoundationParcelFrontageReference],
	profile: FoundationParcelGenerationProfile
) -> FoundationParcelRecord:
	var stable_id := _parcel_id(world, block.stable_id, boundary_key(boundary, profile), profile)
	if world.get_record(stable_id) != null:
		stable_id = _repair_parcel_id(world, block.stable_id, boundary_key(boundary, profile), profile)
	var parcel := FoundationParcelRecord.new(stable_id, block.stable_id, boundary, references)
	parcel.primary_frontage_index = _choose_primary_frontage(world, parcel, profile)
	var primary_segment := -1
	if parcel.primary_frontage_index >= 0:
		primary_segment = parcel.frontage_references[parcel.primary_frontage_index].parcel_boundary_segment_index
	for index in range(parcel.frontage_references.size()):
		parcel.frontage_references[index].frontage_classification = (
			FoundationParcelFrontageReference.CLASS_PRIMARY
			if parcel.frontage_references[index].parcel_boundary_segment_index == primary_segment
			else FoundationParcelFrontageReference.CLASS_SECONDARY
		)
	if parcel.primary_frontage_index >= 0:
		parcel.approximate_frontage_width = 0.0
		for reference in parcel.frontage_references:
			if reference.parcel_boundary_segment_index == primary_segment:
				parcel.approximate_frontage_width += reference.frontage_length
		parcel.approximate_depth = parcel.area / maxf(parcel.approximate_frontage_width, profile.geometric_epsilon)
	var direct_frontage := parcel.approximate_frontage_width >= profile.minimum_frontage
	var area_eligible := parcel.area >= profile.minimum_parcel_area and parcel.area <= profile.maximum_parcel_area
	var depth_eligible := parcel.approximate_depth >= profile.minimum_depth and parcel.approximate_depth <= profile.maximum_depth
	parcel.buildable = direct_frontage and area_eligible and depth_eligible
	if parcel.buildable:
		parcel.access_state = FoundationParcelRecord.ACCESS_DIRECT
		parcel.parcel_kind = FoundationParcelRecord.KIND_CORNER if profile.allow_corner_parcels and _has_corner_frontage(block, parcel, profile) else FoundationParcelRecord.KIND_STANDARD
	elif parcel.area <= profile.non_buildable_remainder_threshold or parcel.area < profile.minimum_parcel_area:
		parcel.access_state = FoundationParcelRecord.ACCESS_NONE
		parcel.parcel_kind = FoundationParcelRecord.KIND_REMAINDER
	else:
		parcel.access_state = FoundationParcelRecord.ACCESS_REQUIRED
		parcel.parcel_kind = FoundationParcelRecord.KIND_FLAG_ACCESS
	parcel.source_pass = SOURCE_PASS
	parcel.source_version = profile.generator_version
	parcel.tags = PackedStringArray(["phase_4", "abstract_parcel", String(parcel.parcel_kind)])
	parcel.metadata = {"boundary_key": boundary_key(boundary, profile)}
	return parcel


static func _choose_primary_frontage(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	profile: FoundationParcelGenerationProfile
) -> int:
	var best := -1
	var best_rank := -1
	var best_tie := 2147483647
	for index in range(parcel.frontage_references.size()):
		var reference := parcel.frontage_references[index]
		var edge := world.get_record(reference.road_edge_id) as FoundationRoadEdge
		var rank := _frontage_rank(edge.road_class if edge != null else &"")
		var tie_seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s:%s:%d" % [
			profile.STREAM_FRONTAGE_PRIORITY, parcel.stable_id, reference.road_edge_id,
			reference.parcel_boundary_segment_index,
		]))
		if best < 0 or rank > best_rank:
			best = index
			best_rank = rank
			best_tie = tie_seed
			continue
		if rank == best_rank:
			var candidate_key := "%010.3f:%010d:%s" % [-reference.frontage_length, tie_seed, reference.road_edge_id]
			var current := parcel.frontage_references[best]
			var current_key := "%010.3f:%010d:%s" % [-current.frontage_length, best_tie, current.road_edge_id]
			if candidate_key < current_key:
				best = index
				best_tie = tie_seed
	return best


static func _frontage_rank(road_class: StringName) -> int:
	match road_class:
		FoundationRoadEdge.CLASS_LOCAL:
			return 6
		FoundationRoadEdge.CLASS_ALLEY:
			return 5
		FoundationRoadEdge.CLASS_COLLECTOR:
			return 4
		FoundationRoadEdge.CLASS_DIRT:
			return 3
		FoundationRoadEdge.CLASS_ARTERIAL:
			return 2
		FoundationRoadEdge.CLASS_HIGHWAY:
			return 1
		_:
			return 0


static func _has_corner_frontage(
	block: FoundationBlockRecord,
	parcel: FoundationParcelRecord,
	profile: FoundationParcelGenerationProfile
) -> bool:
	var segments: Array[int] = []
	for reference in parcel.frontage_references:
		if reference.block_boundary_segment_index not in segments:
			segments.append(reference.block_boundary_segment_index)
	for first_index in range(segments.size()):
		for second_index in range(first_index + 1, segments.size()):
			var first := block.outer_boundary[(segments[first_index] + 1) % block.outer_boundary.size()] - block.outer_boundary[segments[first_index]]
			var second := block.outer_boundary[(segments[second_index] + 1) % block.outer_boundary.size()] - block.outer_boundary[segments[second_index]]
			if absf(first.normalized().cross(second.normalized())) > profile.geometric_epsilon:
				return true
	return false


static func _register_parcel(
	world: FoundationWorldData,
	parcel: FoundationParcelRecord,
	profile: FoundationParcelGenerationProfile,
	result: FoundationParcelGenerationResult
) -> void:
	world.register_record(parcel)
	result.generated_parcel_count += 1
	match parcel.parcel_kind:
		FoundationParcelRecord.KIND_STANDARD:
			result.standard_parcel_count += 1
		FoundationParcelRecord.KIND_CORNER:
			result.corner_parcel_count += 1
		_:
			result.remainder_parcel_count += 1


static func _set_layer_metadata(
	world: FoundationWorldData,
	profile: FoundationParcelGenerationProfile,
	result: FoundationParcelGenerationResult
) -> void:
	world.get_layer(FoundationWorldData.PARCEL_LAYER).metadata = {
		"format_version": 1,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"profile": profile.to_dict(),
		"diagnostics": result.diagnostics.duplicate(true),
		"counts": result.to_dict(),
	}


static func canonicalize_boundary(
	points: PackedVector2Array,
	profile: FoundationParcelGenerationProfile
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
		if normalized[index].x < normalized[first_index].x or (is_equal_approx(normalized[index].x, normalized[first_index].x) and normalized[index].y < normalized[first_index].y):
			first_index = index
	var canonical := PackedVector2Array()
	for offset in range(normalized.size()):
		canonical.append(normalized[(first_index + offset) % normalized.size()])
	return canonical


static func boundary_key(boundary: PackedVector2Array, profile: FoundationParcelGenerationProfile) -> String:
	var parts := PackedStringArray()
	for point in boundary:
		parts.append("%d,%d" % [roundi(point.x / profile.point_quantization), roundi(point.y / profile.point_quantization)])
	return ";".join(parts)


static func is_simple_polygon(boundary: PackedVector2Array, epsilon: float) -> bool:
	if boundary.size() < 3:
		return false
	for first_index in range(boundary.size()):
		var first_next := (first_index + 1) % boundary.size()
		for second_index in range(first_index + 1, boundary.size()):
			var second_next := (second_index + 1) % boundary.size()
			if first_index == second_index or first_next == second_index or second_next == first_index:
				continue
			if _proper_segments_intersect(boundary[first_index], boundary[first_next], boundary[second_index], boundary[second_next], epsilon):
				return false
	return true


static func _proper_segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2, epsilon: float) -> bool:
	var r := b - a
	var s := d - c
	var denominator := r.cross(s)
	if absf(denominator) <= epsilon:
		return false
	var difference := c - a
	var t := difference.cross(s) / denominator
	var u := difference.cross(r) / denominator
	return t > epsilon and t < 1.0 - epsilon and u > epsilon and u < 1.0 - epsilon


static func _boundaries_equal(first: PackedVector2Array, second: PackedVector2Array, epsilon: float) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if first[index].distance_to(second[index]) > epsilon:
			return false
	return true


static func _collinear_overlap(a: Vector2, b: Vector2, c: Vector2, d: Vector2, epsilon: float) -> Dictionary:
	var source := d - c
	var length_squared := source.length_squared()
	if length_squared <= epsilon * epsilon:
		return {"length": 0.0, "t_start": 0.0, "t_end": 0.0}
	if absf(source.cross(a - c)) > epsilon * maxf(1.0, source.length()) or absf(source.cross(b - c)) > epsilon * maxf(1.0, source.length()):
		return {"length": 0.0, "t_start": 0.0, "t_end": 0.0}
	var first_t := (a - c).dot(source) / length_squared
	var second_t := (b - c).dot(source) / length_squared
	var start := maxf(0.0, minf(first_t, second_t))
	var finish := minf(1.0, maxf(first_t, second_t))
	if finish - start <= epsilon:
		return {"length": 0.0, "t_start": start, "t_end": finish}
	return {"length": (finish - start) * sqrt(length_squared), "t_start": start, "t_end": finish}


static func _parcel_id(
	world: FoundationWorldData,
	block_id: StringName,
	key: String,
	profile: FoundationParcelGenerationProfile
) -> StringName:
	return FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		FoundationParcelRecord.ENTITY_TYPE, block_id, key
	)


static func _repair_parcel_id(
	world: FoundationWorldData,
	block_id: StringName,
	key: String,
	profile: FoundationParcelGenerationProfile
) -> StringName:
	var ordinal := 1
	while true:
		var candidate := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			FoundationParcelRecord.ENTITY_TYPE, block_id, "%s|repair:%d" % [key, ordinal]
		)
		if world.get_record(candidate) == null:
			return candidate
		ordinal += 1
	return &""


static func active_strip_cap(profile: FoundationParcelGenerationProfile) -> int:
	return maxi(1, mini(4096, profile.maximum_subdivision_operations / 8))


static func _point_dict(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}
