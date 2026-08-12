class_name FoundationFacadeGenerator
extends RefCounted

## Deterministic modular facade grammar derived from Phase 5 building massing.

const SOURCE_PASS: StringName = &"phase_7_modular_facades"


static func generate(
	world: FoundationWorldData,
	profile: FoundationFacadeGenerationProfile = null
) -> FoundationFacadeGenerationResult:
	var result := FoundationFacadeGenerationResult.new()
	if world == null:
		return result.fail("Facade generation requires FoundationWorldData.")
	var active_profile := profile if profile != null else FoundationFacadeGenerationProfile.new()
	var errors := active_profile.validation_errors()
	if not errors.is_empty():
		return result.fail("Invalid facade generation profile: %s" % "; ".join(errors))
	world.register_layer_type(FoundationWorldData.FACADE_LAYER)
	result.preserved_facade_count = _remove_replaceable_facades(world)
	for building in world.get_buildings():
		_generate_for_building(world, building, active_profile, result)
		if result.generation_operation_count > active_profile.maximum_generation_operations:
			return result.fail("Facade generation exceeded its configured operation cap.")

	var issues := FoundationFacadeValidator.validate(world, active_profile, true)
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
	for facade in world.get_facades():
		if facade.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(facade.stable_id)
			removed += 1
	return removed


static func _remove_replaceable_facades(world: FoundationWorldData) -> int:
	var retained: Array[FoundationFacadeRecord] = []
	for facade in world.get_facades():
		if facade.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(facade.stable_id)
		else:
			retained.append(facade)
	for facade in retained:
		world.register_record(facade)
	return retained.size()


static func _generate_for_building(
	world: FoundationWorldData,
	building: FoundationBuildingRecord,
	profile: FoundationFacadeGenerationProfile,
	result: FoundationFacadeGenerationResult
) -> void:
	if building.validation_state == FoundationBuildingRecord.INVALID:
		_skip_building(result, building, &"invalid_parent_building", "Building validation state is invalid.")
		return
	if building.footprint.size() < 3 or building.height <= profile.geometric_epsilon or building.floor_count <= 0 or building.floor_height <= profile.geometric_epsilon:
		_skip_building(result, building, &"invalid_building_massing", "Building footprint or height is degenerate.")
		return
	if building.floor_height <= profile.top_opening_margin + profile.geometric_epsilon:
		_skip_building(result, building, &"floor_too_short_for_openings", "Building floors cannot contain openings with the configured top margin.")
		return
	var parcel := world.get_record(building.parent_id) as FoundationParcelRecord
	if parcel == null:
		_skip_building(result, building, &"missing_parent_parcel", "Building parent parcel is missing.")
		return
	var eligible_segments: Array[int] = []
	for segment_index in range(building.footprint.size()):
		result.generation_operation_count += 1
		var first := building.footprint[segment_index]
		var second := building.footprint[(segment_index + 1) % building.footprint.size()]
		var length := first.distance_to(second)
		if length < maxf(profile.minimum_facade_length, profile.minimum_bay_width) - profile.geometric_epsilon:
			result.add_diagnostic(&"facade_edge_too_short", FoundationFacadeValidationIssue.SEVERITY_INFO, {
				"parent_building_id": String(building.stable_id),
				"source_segment_index": segment_index,
				"message": "Building edge is too short for the configured modular bay.",
				"point": _point_dict((first + second) * 0.5),
			})
			continue
		if _bay_count(length, profile) <= 0:
			result.add_diagnostic(&"facade_bay_cap_exhausted", FoundationFacadeValidationIssue.SEVERITY_INFO, {
				"parent_building_id": String(building.stable_id),
				"source_segment_index": segment_index,
				"message": "Building edge requires more bays than the configured facade cap.",
				"point": _point_dict((first + second) * 0.5),
			})
			continue
		eligible_segments.append(segment_index)
	if eligible_segments.is_empty():
		_skip_building(result, building, &"no_eligible_facade_edges", "Building has no edges eligible for the configured facade grammar.")
		return
	var primary_index := _primary_segment_index(building, parcel, eligible_segments)
	var primary_outward := _segment_outward(building.footprint, primary_index)
	for segment_index in eligible_segments:
		var first := building.footprint[segment_index]
		var second := building.footprint[(segment_index + 1) % building.footprint.size()]
		var role := _role_for_segment(building.footprint, segment_index, primary_index, primary_outward)
		_generate_facade(world, building, segment_index, first, second, role, profile, result)


static func _generate_facade(
	world: FoundationWorldData,
	building: FoundationBuildingRecord,
	segment_index: int,
	first: Vector2,
	second: Vector2,
	role: StringName,
	profile: FoundationFacadeGenerationProfile,
	result: FoundationFacadeGenerationResult
) -> void:
	var expected_id := _facade_id(world, building.stable_id, segment_index, profile)
	var preserved := world.get_record(expected_id) as FoundationFacadeRecord
	if preserved != null and preserved.parent_id == building.stable_id and preserved.source_segment_index == segment_index and preserved.start.distance_to(first) <= profile.geometric_epsilon and preserved.end.distance_to(second) <= profile.geometric_epsilon:
		return
	var stable_id := expected_id
	if world.get_record(stable_id) != null:
		stable_id = _repair_facade_id(world, building.stable_id, segment_index, profile)
	var facade := FoundationFacadeRecord.new(stable_id, building.stable_id, segment_index, first, second)
	facade.parent_parcel_id = building.parent_id
	facade.parent_block_id = building.parent_block_id
	facade.facade_role = role
	facade.grammar_id = profile.grammar_id
	facade.base_elevation = building.base_elevation
	facade.height = building.height
	facade.floor_count = building.floor_count
	facade.floor_height = building.floor_height
	facade.bay_count = _bay_count(facade.facade_length, profile)
	if facade.bay_count <= 0:
		result.add_diagnostic(&"facade_bay_cap_exhausted", FoundationFacadeValidationIssue.SEVERITY_INFO, {
			"parent_building_id": String(building.stable_id),
			"source_segment_index": segment_index,
			"message": "Building edge requires more bays than the configured facade cap.",
			"point": _point_dict((first + second) * 0.5),
		})
		return
	facade.pattern_phase = int(FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [
		profile.STREAM_PATTERN, facade.stable_id,
	])) % 4)
	_generate_modules(world, facade, profile, result)
	facade.refresh_metrics()
	facade.source_pass = SOURCE_PASS
	facade.source_version = profile.generator_version
	facade.tags = PackedStringArray(["phase_7", "modular_facade", String(role)])
	facade.metadata = {
		"source_building_segment": segment_index,
		"source_building_footprint_key": FoundationBuildingGenerator.boundary_key(building.footprint, FoundationBuildingGenerationProfile.new()),
	}
	world.register_record(facade)
	result.generated_facade_count += 1


static func _generate_modules(
	world: FoundationWorldData,
	facade: FoundationFacadeRecord,
	profile: FoundationFacadeGenerationProfile,
	result: FoundationFacadeGenerationResult
) -> void:
	if facade.bay_count <= 0:
		return
	var bay_width := facade.facade_length / float(facade.bay_count)
	var entrance_bay := -1
	if facade.facade_role == FoundationFacadeRecord.ROLE_PRIMARY:
		var entrance_seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [
			profile.STREAM_ENTRANCE, facade.stable_id,
		]))
		entrance_bay = int(entrance_seed % facade.bay_count)
	for floor_index in range(facade.floor_count):
		for bay_index in range(facade.bay_count):
			result.generation_operation_count += 1
			var module_id := StringName("%s:module_%02d_%02d" % [facade.stable_id, floor_index, bay_index])
			var kind := FoundationFacadeModule.KIND_WALL
			if floor_index == 0 and bay_index == entrance_bay:
				kind = FoundationFacadeModule.KIND_ENTRANCE
			elif _has_window(world, facade, floor_index, bay_index, profile):
				kind = FoundationFacadeModule.KIND_WINDOW
			var module := FoundationFacadeModule.new(module_id, kind, floor_index, bay_index)
			var bay_start := float(bay_index) * bay_width
			var bay_end := float(bay_index + 1) * bay_width
			var floor_start := float(floor_index) * facade.floor_height
			var floor_end := float(floor_index + 1) * facade.floor_height
			if kind == FoundationFacadeModule.KIND_ENTRANCE:
				var entrance_width := minf(profile.entrance_width, maxf(profile.geometric_epsilon, bay_width - profile.horizontal_opening_margin * 2.0))
				var center := (bay_start + bay_end) * 0.5
				module.horizontal_start = center - entrance_width * 0.5
				module.horizontal_end = center + entrance_width * 0.5
				module.vertical_start = floor_start
				module.vertical_end = minf(floor_end - profile.top_opening_margin, floor_start + profile.entrance_height)
				facade.entrance_module_id = module.module_id
				result.entrance_module_count += 1
			elif kind == FoundationFacadeModule.KIND_WINDOW:
				var margin := minf(profile.horizontal_opening_margin, bay_width * 0.3)
				var sill := profile.ground_window_sill if floor_index == 0 else profile.upper_window_sill
				module.horizontal_start = bay_start + margin
				module.horizontal_end = bay_end - margin
				module.vertical_start = floor_start + sill
				module.vertical_end = minf(floor_end - profile.top_opening_margin, module.vertical_start + profile.window_height)
				if module.horizontal_end - module.horizontal_start <= profile.geometric_epsilon or module.vertical_end - module.vertical_start <= profile.geometric_epsilon:
					module.kind = FoundationFacadeModule.KIND_WALL
					module.horizontal_start = bay_start
					module.horizontal_end = bay_end
					module.vertical_start = floor_start
					module.vertical_end = floor_end
				else:
					result.window_module_count += 1
			else:
				module.horizontal_start = bay_start
				module.horizontal_end = bay_end
				module.vertical_start = floor_start
				module.vertical_end = floor_end
			facade.modules.append(module)
			result.generated_module_count += 1


static func _has_window(
	world: FoundationWorldData,
	facade: FoundationFacadeRecord,
	floor_index: int,
	bay_index: int,
	profile: FoundationFacadeGenerationProfile
) -> bool:
	var probability := profile.side_window_probability
	if facade.facade_role == FoundationFacadeRecord.ROLE_PRIMARY:
		probability = profile.primary_window_probability
	elif facade.facade_role == FoundationFacadeRecord.ROLE_REAR:
		probability = profile.rear_window_probability
	var seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s:%d:%d" % [
		profile.STREAM_PATTERN, facade.stable_id, floor_index, bay_index,
	]))
	return float(seed % 10000) < probability * 10000.0


static func _bay_count(length: float, profile: FoundationFacadeGenerationProfile) -> int:
	var minimum_count := maxi(1, ceili(length / profile.maximum_bay_width))
	if minimum_count > profile.maximum_bays_per_facade:
		return 0
	var maximum_count := mini(profile.maximum_bays_per_facade, maxi(1, floori(length / profile.minimum_bay_width)))
	if maximum_count < minimum_count:
		return minimum_count
	return clampi(roundi(length / profile.preferred_bay_width), minimum_count, maximum_count)


static func _primary_segment_index(
	building: FoundationBuildingRecord,
	parcel: FoundationParcelRecord,
	eligible_segments: Array[int]
) -> int:
	var target := building.frontage_direction.normalized()
	var frontage_a := Vector2.ZERO
	var frontage_b := Vector2.ZERO
	var has_frontage := false
	if parcel.primary_frontage_index >= 0 and parcel.primary_frontage_index < parcel.frontage_references.size():
		var reference := parcel.frontage_references[parcel.primary_frontage_index]
		var segment_index := reference.parcel_boundary_segment_index
		if segment_index >= 0 and segment_index < parcel.boundary.size():
			frontage_a = parcel.boundary[segment_index]
			frontage_b = parcel.boundary[(segment_index + 1) % parcel.boundary.size()]
			has_frontage = true
	var best_index := eligible_segments[0]
	var best_score := -INF
	for index in eligible_segments:
		var first := building.footprint[index]
		var second := building.footprint[(index + 1) % building.footprint.size()]
		var outward := _segment_outward(building.footprint, index)
		var score := outward.dot(target) * 100000.0
		if has_frontage:
			score -= _point_segment_distance((first + second) * 0.5, frontage_a, frontage_b)
		if score > best_score:
			best_score = score
			best_index = index
	return best_index


static func _role_for_segment(
	boundary: PackedVector2Array,
	segment_index: int,
	primary_index: int,
	primary_outward: Vector2
) -> StringName:
	if segment_index == primary_index:
		return FoundationFacadeRecord.ROLE_PRIMARY
	var outward := _segment_outward(boundary, segment_index)
	if outward.dot(primary_outward) < -0.5:
		return FoundationFacadeRecord.ROLE_REAR
	return FoundationFacadeRecord.ROLE_SIDE


static func _segment_outward(boundary: PackedVector2Array, segment_index: int) -> Vector2:
	var direction := (boundary[(segment_index + 1) % boundary.size()] - boundary[segment_index]).normalized()
	return Vector2(direction.y, -direction.x)


static func _point_segment_distance(point: Vector2, first: Vector2, second: Vector2) -> float:
	var delta := second - first
	var denominator := delta.length_squared()
	if denominator <= 0.0000001:
		return point.distance_to(first)
	var weight := clampf((point - first).dot(delta) / denominator, 0.0, 1.0)
	return point.distance_to(first + delta * weight)


static func _skip_building(
	result: FoundationFacadeGenerationResult,
	building: FoundationBuildingRecord,
	kind: StringName,
	message: String
) -> void:
	result.skipped_building_count += 1
	result.add_diagnostic(kind, FoundationFacadeValidationIssue.SEVERITY_INFO, {
		"parent_building_id": String(building.stable_id),
		"message": message,
		"point": _point_dict(building.label_point),
	})


static func _facade_id(
	world: FoundationWorldData,
	building_id: StringName,
	segment_index: int,
	profile: FoundationFacadeGenerationProfile
) -> StringName:
	return FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		FoundationFacadeRecord.ENTITY_TYPE, building_id,
		"edge:%d|grammar:%s" % [segment_index, profile.grammar_id]
	)


static func _repair_facade_id(
	world: FoundationWorldData,
	building_id: StringName,
	segment_index: int,
	profile: FoundationFacadeGenerationProfile
) -> StringName:
	var ordinal := 1
	while true:
		var candidate := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			FoundationFacadeRecord.ENTITY_TYPE, building_id,
			"edge:%d|grammar:%s|repair:%d" % [segment_index, profile.grammar_id, ordinal]
		)
		if world.get_record(candidate) == null:
			return candidate
		ordinal += 1
	return &""


static func _set_layer_metadata(
	world: FoundationWorldData,
	profile: FoundationFacadeGenerationProfile,
	result: FoundationFacadeGenerationResult
) -> void:
	world.get_layer(FoundationWorldData.FACADE_LAYER).metadata = {
		"format_version": 1,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"profile": profile.to_dict(),
		"diagnostics": result.diagnostics.duplicate(true),
		"counts": result.to_dict(),
	}


static func _point_dict(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}
