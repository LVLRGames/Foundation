class_name FoundationParcelSubdivider
extends RefCounted

## Deterministic frontage-led subdivision of Phase 3 polygons using at most four road-backed rows.

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
	var unassigned: Array[PackedVector2Array] = [canonical_block]
	var parcel_specs: Array[Dictionary] = []
	var frontage_candidates := _select_frontage_candidates(world, block, profile)
	for row_index in range(frontage_candidates.size()):
		var candidate: Dictionary = frontage_candidates[row_index]
		var segment_index := int(candidate["segment_index"])
		var segment_a := block.outer_boundary[segment_index]
		var segment_b := block.outer_boundary[(segment_index + 1) % block.outer_boundary.size()]
		var segment_length := segment_a.distance_to(segment_b)
		var row_depth := _frontage_row_depth(world, block, segment_index, profile)
		var desired_width := clampf(
			profile.target_parcel_area / maxf(row_depth, profile.minimum_depth),
			profile.minimum_frontage,
			profile.maximum_frontage
		)
		var spacing_seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s:%d" % [
			profile.STREAM_SPLIT_SPACING, block.stable_id, segment_index,
		]))
		desired_width *= 0.88 + float(spacing_seed % 2401) / 10000.0
		desired_width = clampf(desired_width, profile.minimum_frontage, profile.maximum_frontage)
		var cell_count := maxi(1, ceili(segment_length / maxf(desired_width, profile.point_quantization)))
		cell_count = mini(cell_count, active_strip_cap(profile))
		var positions := _frontage_split_positions(
			world, block, segment_index, segment_length, cell_count, profile
		)
		for cell_index in range(cell_count):
			result.subdivision_operation_count += 1
			var clip_polygon := _frontage_cell_polygon(
				segment_a, segment_b, positions[cell_index], positions[cell_index + 1],
				row_depth, FoundationBlockRecord._signed_area(block.outer_boundary) >= 0.0,
				profile.geometric_epsilon
			)
			var accepted: Array[PackedVector2Array] = []
			for component in unassigned:
				result.subdivision_operation_count += 1
				for raw in Geometry2D.intersect_polygons(component, clip_polygon):
					for boundary in _split_repeated_vertex_components(raw, profile):
						var references := _derive_frontage(world, block, boundary, profile, result)
						if not _has_frontage_on_segment(references, segment_index):
							continue
						accepted.append(boundary)
			accepted.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
				return boundary_key(a, profile) < boundary_key(b, profile)
			)
			for boundary in accepted:
				parcel_specs.append({
					"boundary": boundary,
					"frontage_row_index": row_index,
					"source_block_segment_index": segment_index,
				})
				unassigned = _subtract_components(unassigned, boundary, profile, result)

	# Land that cannot be reached by one of the selected street frontages remains
	# explicit and auditable. It is never silently promoted to a buildable parcel.
	for component in unassigned:
		var remainder := canonicalize_boundary(component, profile)
		if remainder.size() >= 3 and absf(FoundationBlockRecord._signed_area(remainder)) > profile.geometric_epsilon:
			parcel_specs.append({
				"boundary": remainder,
				"frontage_row_index": -1,
				"source_block_segment_index": -1,
			})
	parcel_specs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_row := int(a["frontage_row_index"])
		var b_row := int(b["frontage_row_index"])
		if a_row != b_row:
			return a_row < b_row
		return boundary_key(a["boundary"], profile) < boundary_key(b["boundary"], profile)
	)
	var block_area_from_parcels := 0.0
	for spec in parcel_specs:
		var boundary: PackedVector2Array = spec["boundary"]
		var expected_id := _parcel_id(world, block.stable_id, boundary_key(boundary, profile), profile)
		var preserved := world.get_record(expected_id) as FoundationParcelRecord
		if preserved != null and preserved.parent_id == block.stable_id and _boundaries_equal(preserved.boundary, boundary, profile.geometric_epsilon):
			block_area_from_parcels += preserved.area
			continue
		var references := _derive_frontage(world, block, boundary, profile, result)
		var parcel := _create_parcel(
			world, block, boundary, references, profile,
			int(spec["frontage_row_index"]), int(spec["source_block_segment_index"])
		)
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


static func _select_frontage_candidates(
	world: FoundationWorldData,
	block: FoundationBlockRecord,
	profile: FoundationParcelGenerationProfile
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for segment_index in range(block.outer_boundary.size()):
		var has_road_frontage := false
		for reference in block.boundary_references:
			if reference.boundary_segment_index == segment_index and not String(reference.road_edge_id).is_empty():
				has_road_frontage = true
				break
		if not has_road_frontage:
			continue
		var first := block.outer_boundary[segment_index]
		var second := block.outer_boundary[(segment_index + 1) % block.outer_boundary.size()]
		var length := first.distance_to(second)
		if length <= profile.geometric_epsilon:
			continue
		candidates.append({
			"segment_index": segment_index,
			"length": length,
			"direction": (second - first) / length,
			"tie_seed": FoundationSeed.derive(world.metadata.seed, StringName("%s:%s:%d" % [
				profile.STREAM_SPLIT_ORIENTATION, block.stable_id, segment_index,
			])),
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["length"]), float(b["length"])):
			return float(a["length"]) > float(b["length"])
		if int(a["tie_seed"]) != int(b["tie_seed"]):
			return int(a["tie_seed"]) < int(b["tie_seed"])
		return int(a["segment_index"]) < int(b["segment_index"])
	)
	var selected: Array[Dictionary] = []
	while not candidates.is_empty() and selected.size() < profile.maximum_frontage_rows:
		var chosen_index := 0
		if selected.size() % 2 == 1:
			var previous_direction: Vector2 = selected[selected.size() - 1]["direction"]
			var best_dot := 2.0
			for index in range(candidates.size()):
				var candidate_direction: Vector2 = candidates[index]["direction"]
				var direction_dot := previous_direction.dot(candidate_direction)
				if direction_dot < best_dot - profile.geometric_epsilon:
					best_dot = direction_dot
					chosen_index = index
		selected.append(candidates[chosen_index])
		candidates.remove_at(chosen_index)
	return selected


static func _frontage_row_depth(
	world: FoundationWorldData,
	block: FoundationBlockRecord,
	segment_index: int,
	profile: FoundationParcelGenerationProfile
) -> float:
	var seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s:%d:depth" % [
		profile.STREAM_SPLIT_SPACING, block.stable_id, segment_index,
	]))
	var factor := 0.92 + float(seed % 1601) / 10000.0
	return clampf(profile.preferred_depth * factor, profile.minimum_depth, profile.maximum_depth)


static func _frontage_split_positions(
	world: FoundationWorldData,
	block: FoundationBlockRecord,
	segment_index: int,
	extent: float,
	count: int,
	profile: FoundationParcelGenerationProfile
) -> PackedFloat32Array:
	var positions := PackedFloat32Array([0.0])
	var base_width := extent / float(count)
	for index in range(1, count):
		var seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s:%d:%d" % [
			profile.STREAM_SPLIT_SPACING, block.stable_id, segment_index, index,
		]))
		var centered := float(seed % 2001) / 1000.0 - 1.0
		var position := base_width * float(index) + centered * base_width * 0.12
		position = clampf(
			position,
			positions[positions.size() - 1] + profile.point_quantization,
			extent - float(count - index) * profile.point_quantization
		)
		positions.append(position)
	positions.append(extent)
	return positions


static func _frontage_cell_polygon(
	a: Vector2,
	b: Vector2,
	start: float,
	finish: float,
	depth: float,
	block_is_counter_clockwise: bool,
	epsilon: float
) -> PackedVector2Array:
	var tangent := (b - a).normalized()
	var inward := Vector2(-tangent.y, tangent.x)
	if not block_is_counter_clockwise:
		inward = -inward
	var first := a + tangent * start
	var second := a + tangent * finish
	return PackedVector2Array([
		first - inward * epsilon * 4.0,
		second - inward * epsilon * 4.0,
		second + inward * depth,
		first + inward * depth,
	])


static func _has_frontage_on_segment(
	references: Array[FoundationParcelFrontageReference],
	segment_index: int
) -> bool:
	for reference in references:
		if reference.block_boundary_segment_index == segment_index:
			return true
	return false


static func _subtract_components(
	components: Array[PackedVector2Array],
	cutter: PackedVector2Array,
	profile: FoundationParcelGenerationProfile,
	result: FoundationParcelGenerationResult
) -> Array[PackedVector2Array]:
	var remaining: Array[PackedVector2Array] = []
	for component in components:
		result.subdivision_operation_count += 1
		for raw in Geometry2D.clip_polygons(component, cutter):
			for canonical in _split_repeated_vertex_components(raw, profile):
				remaining.append(canonical)
	remaining.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		return boundary_key(a, profile) < boundary_key(b, profile)
	)
	return remaining


static func _split_repeated_vertex_components(
	boundary: PackedVector2Array,
	profile: FoundationParcelGenerationProfile
) -> Array[PackedVector2Array]:
	var canonical := canonicalize_boundary(boundary, profile)
	var components: Array[PackedVector2Array] = []
	if canonical.size() < 3 or absf(FoundationBlockRecord._signed_area(canonical)) <= profile.geometric_epsilon:
		return components
	for first_index in range(canonical.size()):
		for second_index in range(first_index + 2, canonical.size()):
			if first_index == 0 and second_index == canonical.size() - 1:
				continue
			if canonical[first_index].distance_to(canonical[second_index]) > profile.geometric_epsilon:
				continue
			var first_loop := PackedVector2Array()
			for index in range(first_index, second_index):
				first_loop.append(canonical[index])
			var second_loop := PackedVector2Array()
			for index in range(second_index, canonical.size()):
				second_loop.append(canonical[index])
			for index in range(0, first_index):
				second_loop.append(canonical[index])
			components.append_array(_split_repeated_vertex_components(first_loop, profile))
			components.append_array(_split_repeated_vertex_components(second_loop, profile))
			return components
	components.append(canonical)
	return components


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
	profile: FoundationParcelGenerationProfile,
	frontage_row_index := -1,
	source_block_segment_index := -1
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
	parcel.approximate_aspect_ratio = FoundationParcelRecord._aspect_ratio(
		parcel.approximate_frontage_width, parcel.approximate_depth
	)
	parcel.frontage_row_index = frontage_row_index
	parcel.source_block_segment_index = source_block_segment_index
	var direct_frontage := parcel.approximate_frontage_width >= profile.minimum_frontage
	var area_eligible := parcel.area >= profile.minimum_parcel_area and parcel.area <= profile.maximum_parcel_area
	var depth_eligible := parcel.approximate_depth >= profile.minimum_depth and (
		profile.allow_long_form_parcels or parcel.approximate_depth <= profile.maximum_depth
	)
	var aspect_eligible := profile.allow_long_form_parcels or (
		parcel.approximate_aspect_ratio <= profile.maximum_buildable_aspect_ratio
	)
	parcel.buildable = direct_frontage and area_eligible and depth_eligible and aspect_eligible
	parcel.long_form = profile.allow_long_form_parcels and parcel.buildable and (
		parcel.approximate_depth > profile.maximum_depth
		or parcel.approximate_aspect_ratio > profile.maximum_buildable_aspect_ratio
	)
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
	if parcel.long_form:
		parcel.tags.append("long_form_exception")
	parcel.metadata = {
		"boundary_key": boundary_key(boundary, profile),
		"layout_kind": "frontage_row" if frontage_row_index >= 0 else "center_remainder",
	}
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
	var frontage_row_counts: Dictionary = {}
	for block in world.get_blocks():
		var rows: Dictionary = {}
		for parcel in world.get_parcels():
			if parcel.parent_id == block.stable_id and parcel.frontage_row_index >= 0:
				rows[parcel.frontage_row_index] = true
		frontage_row_counts[String(block.stable_id)] = rows.size()
	world.get_layer(FoundationWorldData.PARCEL_LAYER).metadata = {
		"format_version": 2,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"profile": profile.to_dict(),
		"diagnostics": result.diagnostics.duplicate(true),
		"counts": result.to_dict(),
		"frontage_row_counts": frontage_row_counts,
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
