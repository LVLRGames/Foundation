class_name FoundationDistrictGenerator
extends RefCounted

## Deterministic bounded block clustering and district/use policy assignment.

const SOURCE_PASS: StringName = &"phase_8_district_generation"


static func generate(
	world: FoundationWorldData,
	profile: FoundationDistrictGenerationProfile = null
) -> FoundationDistrictGenerationResult:
	var result := FoundationDistrictGenerationResult.new()
	if world == null:
		return result.fail("District generation requires FoundationWorldData.")
	var active_profile := profile if profile != null else FoundationDistrictGenerationProfile.new()
	var errors := active_profile.validation_errors()
	if not errors.is_empty():
		return result.fail("Invalid district generation profile: %s" % "; ".join(errors))
	world.register_layer_type(FoundationWorldData.DISTRICT_LAYER)
	var reserved := _remove_replaceable_districts(world, result)
	var eligible: Array[FoundationBlockRecord] = []
	for block in world.get_blocks():
		if block.validation_state == FoundationBlockRecord.INVALID or block.outer_boundary.size() < 3 or block.area <= active_profile.geometric_tolerance:
			result.skipped_block_count += 1
			result.add_diagnostic(&"invalid_parent_block", FoundationDistrictValidationIssue.SEVERITY_INFO, {
				"block_id": String(block.stable_id), "point": _point_dict(block.label_point),
			})
			continue
		if not reserved.has(block.stable_id):
			eligible.append(block)
	result.unrestricted_pair_reference_count = eligible.size() * (eligible.size() - 1) / 2
	var adjacency := _build_adjacency(world, eligible, active_profile, result)
	if result.generation_operation_count > active_profile.maximum_generation_operations:
		return _cap_failure(world, active_profile, result)
	var unassigned: Dictionary = {}
	for block in eligible:
		unassigned[block.stable_id] = block
	while not unassigned.is_empty():
		var seed := _select_seed(world, unassigned, active_profile)
		var members := _grow_district(seed, unassigned, adjacency, active_profile, result)
		if result.generation_operation_count > active_profile.maximum_generation_operations:
			return _cap_failure(world, active_profile, result)
		var district := _create_district(world, members, active_profile)
		var expected_id := district.stable_id
		if world.get_record(expected_id) != null:
			district.stable_id = _repair_district_id(world, district, active_profile)
			_refresh_assignment_ids(world, district, active_profile)
		world.register_record(district)
		result.generated_district_count += 1
		result.assigned_block_count += members.size()
	var issues := FoundationDistrictValidator.validate(world, active_profile, true)
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
	for district in world.get_districts():
		if district.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(district.stable_id)
			removed += 1
	return removed


static func _remove_replaceable_districts(
	world: FoundationWorldData,
	result: FoundationDistrictGenerationResult
) -> Dictionary:
	var retained: Array[FoundationDistrictRecord] = []
	for district in world.get_districts():
		if district.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(district.stable_id)
		else:
			retained.append(district)
	var reserved: Dictionary = {}
	for district in retained:
		district.refresh_metrics()
		world.register_record(district)
		result.preserved_district_count += 1
		var valid_membership := not district.member_block_ids.is_empty()
		var local_claims: Dictionary = {}
		for block_id in district.member_block_ids:
			if local_claims.has(block_id) or not (world.get_record(block_id) is FoundationBlockRecord):
				valid_membership = false
			local_claims[block_id] = true
		if not valid_membership:
			result.add_diagnostic(&"invalid_authored_membership", FoundationDistrictValidationIssue.SEVERITY_ERROR, {
				"district_id": String(district.stable_id),
			})
			continue
		for block_id in district.member_block_ids:
			if reserved.has(block_id):
				result.add_diagnostic(&"duplicate_authored_block_claim", FoundationDistrictValidationIssue.SEVERITY_ERROR, {
					"district_id": String(district.stable_id), "block_id": String(block_id),
				})
			else:
				reserved[block_id] = district.stable_id
	return reserved


static func _build_adjacency(
	world: FoundationWorldData,
	blocks: Array[FoundationBlockRecord],
	profile: FoundationDistrictGenerationProfile,
	result: FoundationDistrictGenerationResult
) -> Dictionary:
	var adjacency: Dictionary = {}
	var eligible_ids: Dictionary = {}
	for block in blocks:
		adjacency[block.stable_id] = []
		eligible_ids[block.stable_id] = true
	var seen_pairs: Dictionary = {}
	for block in blocks:
		for chunk in block.owning_chunks:
			for offset_y in range(-1, 2):
				for offset_x in range(-1, 2):
					var candidate_chunk := chunk + Vector2i(offset_x, offset_y)
					var candidates := world.get_records_in_chunk(candidate_chunk, FoundationWorldData.BLOCK_LAYER)
					for candidate_record in candidates:
						if not (candidate_record is FoundationBlockRecord):
							continue
						var candidate := candidate_record as FoundationBlockRecord
						if not eligible_ids.has(candidate.stable_id) or candidate.stable_id == block.stable_id:
							continue
						var first_id := block.stable_id if String(block.stable_id) < String(candidate.stable_id) else candidate.stable_id
						var second_id := candidate.stable_id if first_id == block.stable_id else block.stable_id
						var pair_key := "%s|%s" % [first_id, second_id]
						if seen_pairs.has(pair_key):
							continue
						seen_pairs[pair_key] = true
						result.adjacency_candidate_comparisons += 1
						result.generation_operation_count += 1
						var shared := _shared_boundary_length(block.outer_boundary, candidate.outer_boundary, profile.geometric_tolerance)
						if shared <= profile.geometric_tolerance:
							continue
						var road_data := _shared_road_data(world, block, candidate, profile)
						var connection := {
							"neighbor_id": candidate.stable_id,
							"shared_length": shared,
							"crossing_penalty": road_data["penalty"],
							"road_ids": road_data["road_ids"],
						}
						var reverse := connection.duplicate(true)
						reverse["neighbor_id"] = block.stable_id
						(adjacency[block.stable_id] as Array).append(connection)
						(adjacency[candidate.stable_id] as Array).append(reverse)
						result.adjacency_edge_count += 1
	for block_id in adjacency:
		(adjacency[block_id] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["neighbor_id"]) < String(b["neighbor_id"])
		)
	return adjacency


static func _select_seed(
	world: FoundationWorldData,
	unassigned: Dictionary,
	profile: FoundationDistrictGenerationProfile
) -> FoundationBlockRecord:
	var candidates: Array[Dictionary] = []
	for block: FoundationBlockRecord in unassigned.values():
		candidates.append({"block": block, "evidence": _seed_evidence(world, block, profile)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := float((a["evidence"] as Dictionary)["score"])
		var b_score := float((b["evidence"] as Dictionary)["score"])
		if not is_equal_approx(a_score, b_score):
			return a_score > b_score
		return String((a["block"] as FoundationBlockRecord).stable_id) < String((b["block"] as FoundationBlockRecord).stable_id)
	)
	return candidates[0]["block"] as FoundationBlockRecord


static func _grow_district(
	seed: FoundationBlockRecord,
	unassigned: Dictionary,
	adjacency: Dictionary,
	profile: FoundationDistrictGenerationProfile,
	result: FoundationDistrictGenerationResult
) -> Array[FoundationBlockRecord]:
	var members: Array[FoundationBlockRecord] = [seed]
	var member_ids: Dictionary = {seed.stable_id: true}
	unassigned.erase(seed.stable_id)
	var total_area := seed.area
	var neighbor_operations := 0
	while members.size() < profile.target_blocks_per_district and members.size() < profile.maximum_blocks_per_district:
		var frontier: Array[Dictionary] = []
		var frontier_ids: Dictionary = {}
		for member in members:
			for connection: Dictionary in adjacency.get(member.stable_id, []):
				neighbor_operations += 1
				result.generation_operation_count += 1
				if neighbor_operations > profile.maximum_neighbor_expansion_operations:
					result.add_diagnostic(&"neighbor_expansion_cap", FoundationDistrictValidationIssue.SEVERITY_WARNING, {"block_id": String(seed.stable_id)})
					return members
				var neighbor_id: StringName = connection["neighbor_id"]
				if member_ids.has(neighbor_id) or not unassigned.has(neighbor_id):
					continue
				var score := float(connection["shared_length"]) * profile.shared_boundary_weight - float(connection["crossing_penalty"])
				if not frontier_ids.has(neighbor_id) or score > float(frontier_ids[neighbor_id]):
					frontier_ids[neighbor_id] = score
		if frontier_ids.is_empty():
			break
		for neighbor_id in frontier_ids:
			frontier.append({"block": unassigned[neighbor_id], "score": frontier_ids[neighbor_id]})
		frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(float(a["score"]), float(b["score"])):
				return float(a["score"]) > float(b["score"])
			return String((a["block"] as FoundationBlockRecord).stable_id) < String((b["block"] as FoundationBlockRecord).stable_id)
		)
		var next_block := frontier[0]["block"] as FoundationBlockRecord
		if total_area + next_block.area > profile.maximum_district_area:
			result.add_diagnostic(&"district_area_cap", FoundationDistrictValidationIssue.SEVERITY_INFO, {
				"block_id": String(next_block.stable_id), "seed_block_id": String(seed.stable_id),
			})
			break
		members.append(next_block)
		member_ids[next_block.stable_id] = true
		unassigned.erase(next_block.stable_id)
		total_area += next_block.area
	return members


static func _create_district(
	world: FoundationWorldData,
	members: Array[FoundationBlockRecord],
	profile: FoundationDistrictGenerationProfile
) -> FoundationDistrictRecord:
	var block_ids: Array[StringName] = []
	for block in members:
		block_ids.append(block.stable_id)
	block_ids.sort_custom(FoundationDistrictRecord._string_name_less)
	var components := boundary_components_for_blocks(members, profile.geometric_tolerance)
	var seed_block := members[0]
	var seed_evidence := _seed_evidence(world, seed_block, profile)
	var source_anchor_id: StringName = seed_evidence["anchor_id"]
	var source_patterns: Array[StringName] = []
	for pattern in world.get_road_pattern_areas():
		for block in members:
			if pattern.world_bounds.has_point(block.label_point):
				source_patterns.append(pattern.stable_id)
				break
	source_patterns.sort_custom(FoundationDistrictRecord._string_name_less)
	var stable_id := _district_id(world, source_anchor_id, seed_block.stable_id, block_ids, profile)
	var district := FoundationDistrictRecord.new(stable_id, block_ids, components)
	district.source_anchor_id = source_anchor_id
	district.source_pattern_ids = source_patterns
	district.character_key = _select_character(world, district, seed_evidence, profile)
	district.primary_use = _primary_use_for_character(district.character_key)
	district.allowed_uses = _allowed_uses_for_character(district.character_key)
	_apply_policy(world, district, profile)
	district.road_class_exposure = _road_exposure(world, members)
	district.access_score = _access_score(district.road_class_exposure)
	district.assignments = _create_assignments(world, district, members, profile)
	district.source_pass = SOURCE_PASS
	district.source_version = profile.generator_version
	district.tags = PackedStringArray(["phase_8", "district", String(district.character_key), String(district.primary_use)])
	district.metadata = {
		"policy_id": String(profile.policy_id),
		"seed_block_id": String(seed_block.stable_id),
		"seed_score": float(seed_evidence["score"]),
	}
	district.refresh_metrics()
	return district


static func _seed_evidence(
	world: FoundationWorldData,
	block: FoundationBlockRecord,
	profile: FoundationDistrictGenerationProfile
) -> Dictionary:
	var best_anchor_id: StringName
	var best_anchor_category: StringName
	var best_anchor_score := 0.0
	for anchor in world.get_anchors():
		if not _district_anchor_categories().has(anchor.anchor_category):
			continue
		var anchor_point := Vector2(anchor.world_position.x, anchor.world_position.z)
		var distance := block.label_point.distance_to(anchor_point)
		var scale := maxf(anchor.influence_radius, 32.0)
		var score := anchor.priority_weight * profile.anchor_influence_weight / (1.0 + distance / scale)
		if anchor.world_bounds.has_point(block.label_point):
			score += profile.anchor_influence_weight
		if score > best_anchor_score + 0.000001 or (is_equal_approx(score, best_anchor_score) and String(anchor.stable_id) < String(best_anchor_id)):
			best_anchor_score = score
			best_anchor_id = anchor.stable_id
			best_anchor_category = anchor.anchor_category
	var pattern_ids: Array[StringName] = []
	var pattern_families: Array[StringName] = []
	for pattern in world.get_road_pattern_areas():
		if pattern.world_bounds.has_point(block.label_point):
			pattern_ids.append(pattern.stable_id)
			pattern_families.append(pattern.pattern_family)
	pattern_ids.sort_custom(FoundationDistrictRecord._string_name_less)
	pattern_families.sort_custom(FoundationDistrictRecord._string_name_less)
	var total_floors := 0
	var building_count := 0
	for building in world.get_buildings():
		if building.parent_block_id == block.stable_id:
			total_floors += building.floor_count
			building_count += 1
	var building_floor_average := float(total_floors) / float(building_count) if building_count > 0 else 0.0
	var variation_seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [profile.STREAM_SEED_PRIORITY, block.stable_id]))
	var score := best_anchor_score + float(pattern_ids.size()) * profile.pattern_influence_weight + building_floor_average * profile.density_evidence_weight + float(variation_seed % 1000) / 1000000.0
	return {
		"score": score,
		"anchor_id": best_anchor_id,
		"anchor_category": best_anchor_category,
		"pattern_ids": pattern_ids,
		"pattern_families": pattern_families,
		"building_floor_average": building_floor_average,
	}


static func _select_character(
	world: FoundationWorldData,
	district: FoundationDistrictRecord,
	evidence: Dictionary,
	profile: FoundationDistrictGenerationProfile
) -> StringName:
	var families: Array[StringName] = evidence["pattern_families"]
	for family in families:
		if profile.pattern_character_preferences.has(String(family)):
			return StringName(profile.pattern_character_preferences[String(family)])
	var category: StringName = evidence["anchor_category"]
	if profile.anchor_character_preferences.has(String(category)):
		return StringName(profile.anchor_character_preferences[String(category)])
	var total_floors := 0
	var building_count := 0
	for building in world.get_buildings():
		if district.member_block_ids.has(building.parent_block_id):
			total_floors += building.floor_count
			building_count += 1
	if building_count > 0 and float(total_floors) / float(building_count) >= 4.0:
		return FoundationDistrictRecord.CHARACTER_MIXED_USE
	var variation := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [profile.STREAM_CHARACTER, district.stable_id]))
	return FoundationDistrictRecord.CHARACTER_SUBURBAN if variation % 3 == 0 else FoundationDistrictRecord.CHARACTER_RESIDENTIAL


static func _apply_policy(
	world: FoundationWorldData,
	district: FoundationDistrictRecord,
	profile: FoundationDistrictGenerationProfile
) -> void:
	var base: Dictionary = profile.character_policies.get(String(district.character_key), {})
	var variation_seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s" % [profile.STREAM_POLICY_VARIATION, district.stable_id]))
	var variation := (float(variation_seed % 2001) / 2000.0 - 0.5) * 0.10
	district.target_density = clampf(float(base.get("density", 0.44)) + variation, 0.0, 1.0)
	district.minimum_height = float(base.get("minimum_height", 3.0))
	district.maximum_height = float(base.get("maximum_height", 24.0))
	district.target_intensity = clampf(float(base.get("intensity", 0.50)) + variation, 0.0, 1.0)
	district.open_space_target = clampf(float(base.get("open_space", 0.22)) - variation * 0.5, 0.0, 1.0)
	district.mixed_use_ratio = clampf(float(base.get("mixed_use", 0.18)) + variation, 0.0, 1.0)
	district.style_policy_key = StringName("style_%s" % district.character_key)
	district.content_policy_key = StringName("content_%s" % district.primary_use)


static func _create_assignments(
	world: FoundationWorldData,
	district: FoundationDistrictRecord,
	members: Array[FoundationBlockRecord],
	profile: FoundationDistrictGenerationProfile
) -> Array[FoundationDistrictMemberAssignment]:
	var result: Array[FoundationDistrictMemberAssignment] = []
	for block in members:
		var use_key := district.primary_use
		var variation := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s:%s" % [profile.STREAM_MEMBER_USE, district.stable_id, block.stable_id]))
		if district.character_key == FoundationDistrictRecord.CHARACTER_MIXED_USE:
			var mixed_options: Array[StringName] = [FoundationDistrictRecord.USE_MIXED, FoundationDistrictRecord.USE_COMMERCIAL, FoundationDistrictRecord.USE_RESIDENTIAL]
			use_key = mixed_options[variation % mixed_options.size()]
		elif district.character_key == FoundationDistrictRecord.CHARACTER_CIVIC and variation % 3 == 0:
			use_key = FoundationDistrictRecord.USE_OPEN_SPACE
		elif district.character_key == FoundationDistrictRecord.CHARACTER_RURAL and variation % 3 == 0:
			use_key = FoundationDistrictRecord.USE_UNDEVELOPED
		var assignment_id := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			&"district_assignment", district.stable_id, String(block.stable_id)
		)
		var assignment := FoundationDistrictMemberAssignment.new(assignment_id, district.stable_id, block.stable_id, use_key)
		assignment.allowed_uses = district.allowed_uses.duplicate()
		assignment.suitability_score = clampf(0.55 + float(variation % 4001) / 10000.0, 0.0, 1.0)
		assignment.target_density = district.target_density
		assignment.target_intensity = district.target_intensity
		assignment.evidence = {
			"block_area": block.area,
			"boundary_road_count": block.boundary_road_ids.size(),
			"policy_variation": variation % 10001,
		}
		result.append(assignment)
	result.sort_custom(FoundationDistrictMemberAssignment.less)
	return result


static func _refresh_assignment_ids(
	world: FoundationWorldData,
	district: FoundationDistrictRecord,
	profile: FoundationDistrictGenerationProfile
) -> void:
	for assignment in district.assignments:
		assignment.district_id = district.stable_id
		assignment.assignment_id = FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			&"district_assignment", district.stable_id, String(assignment.block_id)
		)


static func _shared_boundary_length(first: PackedVector2Array, second: PackedVector2Array, tolerance: float) -> float:
	var total := 0.0
	for first_index in range(first.size()):
		var a := first[first_index]
		var b := first[(first_index + 1) % first.size()]
		var direction := b - a
		var length := direction.length()
		if length <= tolerance:
			continue
		var axis := direction / length
		for second_index in range(second.size()):
			var c := second[second_index]
			var d := second[(second_index + 1) % second.size()]
			if absf((c - a).cross(axis)) > tolerance or absf((d - a).cross(axis)) > tolerance:
				continue
			var start := maxf(0.0, minf((c - a).dot(axis), (d - a).dot(axis)))
			var finish := minf(length, maxf((c - a).dot(axis), (d - a).dot(axis)))
			if finish > start + tolerance:
				total += finish - start
	return total


static func boundary_components_for_blocks(
	blocks: Array[FoundationBlockRecord],
	quantization: float
) -> Array[PackedVector2Array]:
	var ordered := blocks.duplicate()
	ordered.sort_custom(func(a: FoundationBlockRecord, b: FoundationBlockRecord) -> bool:
		return String(a.stable_id) < String(b.stable_id)
	)
	var components: Array[PackedVector2Array] = []
	for block in ordered:
		var pending := _canonicalize_boundary(block.outer_boundary, quantization)
		var remaining: Array[PackedVector2Array] = []
		for existing in components:
			var merged := Geometry2D.merge_polygons(existing, pending)
			if merged.size() == 1:
				pending = _canonicalize_boundary(merged[0], quantization)
			else:
				remaining.append(existing)
		remaining.append(pending)
		components = remaining
	components.sort_custom(FoundationDistrictRecord._component_less)
	return components


static func _canonicalize_boundary(points: PackedVector2Array, quantization: float) -> PackedVector2Array:
	var tolerance := quantization * 0.5
	var normalized := PackedVector2Array()
	for point in points:
		var quantized := Vector2(
			round(point.x / quantization) * quantization,
			round(point.y / quantization) * quantization
		)
		if normalized.is_empty() or normalized[normalized.size() - 1].distance_to(quantized) > tolerance:
			normalized.append(quantized)
	if normalized.size() > 1 and normalized[0].distance_to(normalized[normalized.size() - 1]) <= tolerance:
		normalized.remove_at(normalized.size() - 1)
	var changed := true
	while changed and normalized.size() >= 3:
		changed = false
		for index in range(normalized.size()):
			var previous := normalized[(index - 1 + normalized.size()) % normalized.size()]
			var current := normalized[index]
			var next := normalized[(index + 1) % normalized.size()]
			if absf((current - previous).cross(next - current)) <= tolerance and (current - previous).dot(next - current) >= 0.0:
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


static func _shared_road_data(
	world: FoundationWorldData,
	first: FoundationBlockRecord,
	second: FoundationBlockRecord,
	profile: FoundationDistrictGenerationProfile
) -> Dictionary:
	var shared: Array[StringName] = []
	for road_id in first.boundary_road_ids:
		if second.boundary_road_ids.has(road_id):
			shared.append(road_id)
	shared.sort_custom(FoundationDistrictRecord._string_name_less)
	var penalty := 0.0
	for road_id in shared:
		var edge := world.get_record(road_id) as FoundationRoadEdge
		if edge == null:
			continue
		match edge.road_class:
			FoundationRoadEdge.CLASS_HIGHWAY:
				penalty = maxf(penalty, profile.highway_crossing_penalty)
			FoundationRoadEdge.CLASS_ARTERIAL:
				penalty = maxf(penalty, profile.arterial_crossing_penalty)
			FoundationRoadEdge.CLASS_COLLECTOR:
				penalty = maxf(penalty, profile.collector_crossing_penalty)
			_:
				penalty = maxf(penalty, profile.local_crossing_penalty)
	return {"road_ids": shared, "penalty": penalty}


static func _road_exposure(world: FoundationWorldData, members: Array[FoundationBlockRecord]) -> Dictionary:
	var exposure := {
		String(FoundationRoadEdge.CLASS_HIGHWAY): 0.0,
		String(FoundationRoadEdge.CLASS_ARTERIAL): 0.0,
		String(FoundationRoadEdge.CLASS_COLLECTOR): 0.0,
		String(FoundationRoadEdge.CLASS_LOCAL): 0.0,
		String(FoundationRoadEdge.CLASS_ALLEY): 0.0,
		String(FoundationRoadEdge.CLASS_DIRT): 0.0,
	}
	var seen: Dictionary = {}
	for block in members:
		for reference in block.boundary_references:
			var key := "%s|%d|%.6f|%.6f" % [reference.road_edge_id, reference.source_segment_index, reference.source_t_start, reference.source_t_end]
			if seen.has(key):
				continue
			seen[key] = true
			var edge := world.get_record(reference.road_edge_id) as FoundationRoadEdge
			var road_class := String(edge.road_class) if edge != null else String(FoundationRoadEdge.CLASS_LOCAL)
			exposure[road_class] = float(exposure.get(road_class, 0.0)) + reference.frontage_length
	return exposure


static func _access_score(exposure: Dictionary) -> float:
	var local := float(exposure.get(String(FoundationRoadEdge.CLASS_LOCAL), 0.0))
	var collector := float(exposure.get(String(FoundationRoadEdge.CLASS_COLLECTOR), 0.0))
	var arterial := float(exposure.get(String(FoundationRoadEdge.CLASS_ARTERIAL), 0.0))
	var highway := float(exposure.get(String(FoundationRoadEdge.CLASS_HIGHWAY), 0.0))
	var total := 0.0
	for value in exposure.values():
		total += float(value)
	return clampf((local + collector * 1.2 + arterial * 0.8 + highway * 0.25) / maxf(total, 1.0), 0.0, 1.0)


static func _primary_use_for_character(character: StringName) -> StringName:
	match character:
		FoundationDistrictRecord.CHARACTER_DOWNTOWN, FoundationDistrictRecord.CHARACTER_MIXED_USE:
			return FoundationDistrictRecord.USE_MIXED
		FoundationDistrictRecord.CHARACTER_INDUSTRIAL:
			return FoundationDistrictRecord.USE_INDUSTRIAL
		FoundationDistrictRecord.CHARACTER_CIVIC:
			return FoundationDistrictRecord.USE_CIVIC
		FoundationDistrictRecord.CHARACTER_RURAL:
			return FoundationDistrictRecord.USE_AGRICULTURAL
		_:
			return FoundationDistrictRecord.USE_RESIDENTIAL


static func _allowed_uses_for_character(character: StringName) -> Array[StringName]:
	var values: Array[StringName]
	match character:
		FoundationDistrictRecord.CHARACTER_DOWNTOWN:
			values = [FoundationDistrictRecord.USE_COMMERCIAL, FoundationDistrictRecord.USE_CIVIC, FoundationDistrictRecord.USE_MIXED, FoundationDistrictRecord.USE_RESIDENTIAL]
		FoundationDistrictRecord.CHARACTER_MIXED_USE:
			values = [FoundationDistrictRecord.USE_COMMERCIAL, FoundationDistrictRecord.USE_MIXED, FoundationDistrictRecord.USE_OPEN_SPACE, FoundationDistrictRecord.USE_RESIDENTIAL]
		FoundationDistrictRecord.CHARACTER_INDUSTRIAL:
			values = [FoundationDistrictRecord.USE_COMMERCIAL, FoundationDistrictRecord.USE_INDUSTRIAL, FoundationDistrictRecord.USE_OPEN_SPACE]
		FoundationDistrictRecord.CHARACTER_CIVIC:
			values = [FoundationDistrictRecord.USE_CIVIC, FoundationDistrictRecord.USE_INSTITUTIONAL, FoundationDistrictRecord.USE_OPEN_SPACE]
		FoundationDistrictRecord.CHARACTER_RURAL:
			values = [FoundationDistrictRecord.USE_AGRICULTURAL, FoundationDistrictRecord.USE_OPEN_SPACE, FoundationDistrictRecord.USE_RESIDENTIAL, FoundationDistrictRecord.USE_UNDEVELOPED]
		_:
			values = [FoundationDistrictRecord.USE_COMMERCIAL, FoundationDistrictRecord.USE_OPEN_SPACE, FoundationDistrictRecord.USE_RESIDENTIAL]
	values.sort_custom(FoundationDistrictRecord._string_name_less)
	return values


static func _district_anchor_categories() -> Array[StringName]:
	return [
		FoundationCityAnchor.CATEGORY_CITY_CENTER, FoundationCityAnchor.CATEGORY_CIVIC_CENTER,
		FoundationCityAnchor.CATEGORY_INDUSTRIAL_CENTER, FoundationCityAnchor.CATEGORY_COMMERCIAL_CENTER,
		FoundationCityAnchor.CATEGORY_TRANSIT_NODE, FoundationCityAnchor.CATEGORY_LANDMARK,
		FoundationCityAnchor.CATEGORY_PUBLIC_SQUARE, FoundationCityAnchor.CATEGORY_DISTRICT_SEED,
	]


static func _district_id(
	world: FoundationWorldData,
	anchor_id: StringName,
	seed_block_id: StringName,
	member_ids: Array[StringName],
	profile: FoundationDistrictGenerationProfile
) -> StringName:
	var member_parts := PackedStringArray()
	for member_id in member_ids:
		member_parts.append(String(member_id))
	var seed_identity := anchor_id if not String(anchor_id).is_empty() else seed_block_id
	return FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		FoundationDistrictRecord.ENTITY_TYPE, seed_identity,
		"policy:%s|members:%s" % [profile.policy_id, ",".join(member_parts)]
	)


static func _repair_district_id(
	world: FoundationWorldData,
	district: FoundationDistrictRecord,
	profile: FoundationDistrictGenerationProfile
) -> StringName:
	var member_parts := PackedStringArray()
	for member_id in district.member_block_ids:
		member_parts.append(String(member_id))
	var ordinal := 1
	while true:
		var candidate := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			FoundationDistrictRecord.ENTITY_TYPE, district.source_anchor_id,
			"policy:%s|members:%s|repair:%d" % [profile.policy_id, ",".join(member_parts), ordinal]
		)
		if world.get_record(candidate) == null:
			return candidate
		ordinal += 1
	return &""


static func _cap_failure(
	world: FoundationWorldData,
	profile: FoundationDistrictGenerationProfile,
	result: FoundationDistrictGenerationResult
) -> FoundationDistrictGenerationResult:
	result.add_diagnostic(&"generation_operation_cap", FoundationDistrictValidationIssue.SEVERITY_ERROR, {
		"operation_count": result.generation_operation_count,
		"maximum": profile.maximum_generation_operations,
	})
	result.fail("District generation exceeded its configured operation cap.")
	_set_layer_metadata(world, profile, result)
	return result


static func _set_layer_metadata(
	world: FoundationWorldData,
	profile: FoundationDistrictGenerationProfile,
	result: FoundationDistrictGenerationResult
) -> void:
	world.get_layer(FoundationWorldData.DISTRICT_LAYER).metadata = {
		"format_version": 1,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"policy_id": String(profile.policy_id),
		"profile": profile.to_dict(),
		"diagnostics": result.diagnostics.duplicate(true),
		"counts": result.to_dict(),
	}


static func _point_dict(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}
