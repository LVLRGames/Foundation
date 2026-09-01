class_name FoundationTrafficMetadataValidator
extends RefCounted

## Read-only deterministic validation for Phase 13 advanced-road metadata.


static func validate(
	world: FoundationWorldData,
	profile: FoundationTrafficMetadataProfile = null
) -> Array[FoundationTrafficMetadataValidationIssue]:
	var issues: Array[FoundationTrafficMetadataValidationIssue] = []
	if world == null:
		issues.append(FoundationTrafficMetadataValidationIssue.new(
			&"missing_world", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR,
			&"", &"", "Traffic metadata validation requires world data."
		))
		return issues
	var active_profile := profile if profile != null else FoundationTrafficMetadataProfile.new()
	var cross_sections := world.get_road_cross_sections()
	var traffic_records := world.get_intersection_traffic()
	var cross_sections_by_edge: Dictionary = {}
	var lane_lookup: Dictionary = {}
	for cross_section in cross_sections:
		if cross_sections_by_edge.has(cross_section.road_edge_id):
			_add(issues, &"duplicate_cross_section", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, cross_section, "A road edge has more than one Phase 13 cross section.")
		else:
			cross_sections_by_edge[cross_section.road_edge_id] = cross_section
		_validate_cross_section(world, cross_section, lane_lookup, active_profile, issues)
	for edge in world.get_road_edges():
		if not cross_sections_by_edge.has(edge.stable_id):
			issues.append(FoundationTrafficMetadataValidationIssue.new(
				&"missing_cross_section", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR,
				edge.stable_id, edge.stable_id, "Road edge has no Phase 13 cross-section metadata."
			))
	var traffic_by_intersection: Dictionary = {}
	for traffic in traffic_records:
		if traffic_by_intersection.has(traffic.intersection_id):
			_add(issues, &"duplicate_intersection_traffic", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, traffic, "An intersection has more than one Phase 13 traffic record.")
		else:
			traffic_by_intersection[traffic.intersection_id] = traffic
		_validate_intersection_traffic(world, traffic, cross_sections_by_edge, lane_lookup, active_profile, issues)
	for intersection in world.get_road_intersections():
		if not traffic_by_intersection.has(intersection.stable_id):
			issues.append(FoundationTrafficMetadataValidationIssue.new(
				&"missing_intersection_traffic", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR,
				intersection.stable_id, intersection.stable_id, "Phase 2 intersection has no Phase 13 traffic metadata."
			))
	_validate_layer_accounting(world, active_profile, issues)
	issues.sort_custom(FoundationTrafficMetadataValidationIssue.less)
	return issues


static func _validate_cross_section(
	world: FoundationWorldData,
	record: FoundationRoadCrossSectionRecord,
	lane_lookup: Dictionary,
	profile: FoundationTrafficMetadataProfile,
	issues: Array[FoundationTrafficMetadataValidationIssue]
) -> void:
	var edge := world.get_record(record.road_edge_id) as FoundationRoadEdge
	if edge == null:
		_add(issues, &"missing_source_edge", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Cross section references a missing Phase 2 road edge.")
		return
	if record.parent_id != record.road_edge_id or record.logical_road_id != edge.logical_road_id:
		_add(issues, &"cross_section_lineage_mismatch", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Cross-section parent or logical-road lineage is inconsistent.")
	if record.lanes.is_empty() or record.lanes.size() > profile.maximum_lanes_per_edge:
		_add(issues, &"invalid_lane_count", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Cross-section lane count is empty or exceeds the configured cap.")
	var previous: FoundationRoadLane
	var width_total := record.median_width
	var lane_ids: Dictionary = {}
	for lane in record.lanes:
		if previous != null and FoundationRoadLane.less(lane, previous):
			_add(issues, &"lane_order", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Lanes are not in canonical direction/index order.")
		previous = lane
		if String(lane.lane_id).is_empty() or lane_ids.has(lane.lane_id) or lane_lookup.has(lane.lane_id):
			_add(issues, &"duplicate_lane_identity", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Lane identities must be globally unique and non-empty.")
		lane_ids[lane.lane_id] = true
		lane_lookup[lane.lane_id] = lane
		if lane.direction not in [FoundationRoadLane.DIRECTION_FORWARD, FoundationRoadLane.DIRECTION_REVERSE]:
			_add(issues, &"invalid_lane_direction", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Lane direction is unsupported.")
		if lane.lane_role != FoundationRoadLane.ROLE_TRAVEL or lane.width <= 0.0 or lane.speed_limit_kph <= 0.0 or lane.abstract_capacity_per_hour <= 0:
			_add(issues, &"invalid_lane_policy", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Generated travel-lane dimensions, speed, or capacity are invalid.")
		if lane.centerline.size() != edge.route_points.size() or lane.centerline.size() < 2 or not _finite_points(lane.centerline):
			_add(issues, &"invalid_lane_centerline", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Lane centerline must parallel the complete finite source route.")
		if lane.turn_permissions.is_empty() or lane.allowed_movement_modes.is_empty():
			_add(issues, &"empty_lane_policy", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Lane movement modes and turn permissions must be explicit.")
		if record.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			var expected_lane_id := FoundationSpatialId.make(
				world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
				&"road_lane", record.stable_id, "%s:%d" % [lane.direction, lane.lane_index]
			)
			if lane.lane_id != expected_lane_id:
				_add(issues, &"lane_identity_mismatch", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Generated lane identity does not match its canonical direction/index key.")
		width_total += lane.width
	if absf(width_total - record.carriageway_width) > profile.geometric_tolerance:
		_add(issues, &"carriageway_width_mismatch", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Stored carriageway width does not equal median plus lane widths.")
	if record.source_topology_fingerprint != FoundationTrafficMetadataGenerator.topology_fingerprint_for_edge(edge):
		_add(issues, &"stale_cross_section", FoundationTrafficMetadataValidationIssue.SEVERITY_WARNING, record, "Cross section was derived from different road topology.")
	_validate_generation_contract(record, profile, issues)
	_validate_stable_identity(world, record, FoundationTrafficMetadataGenerator.cross_section_semantic(profile), profile, issues)
	_validate_ownership(world, record, issues)


static func _validate_intersection_traffic(
	world: FoundationWorldData,
	record: FoundationIntersectionTrafficRecord,
	cross_sections_by_edge: Dictionary,
	lane_lookup: Dictionary,
	profile: FoundationTrafficMetadataProfile,
	issues: Array[FoundationTrafficMetadataValidationIssue]
) -> void:
	var intersection := world.get_record(record.intersection_id) as FoundationIntersectionRecord
	var node := world.get_record(record.node_id) as FoundationRoadNode
	if intersection == null or node == null:
		_add(issues, &"missing_traffic_source", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Intersection traffic references missing Phase 2 source data.")
		return
	if record.parent_id != record.intersection_id or intersection.node_id != record.node_id:
		_add(issues, &"traffic_lineage_mismatch", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Intersection traffic parent or node lineage is inconsistent.")
	if record.control_type not in [
		FoundationIntersectionTrafficRecord.CONTROL_UNCONTROLLED,
		FoundationIntersectionTrafficRecord.CONTROL_PRIORITY,
		FoundationIntersectionTrafficRecord.CONTROL_ALL_WAY_STOP,
		FoundationIntersectionTrafficRecord.CONTROL_SIGNAL_PLAN,
	]:
		_add(issues, &"invalid_control_type", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Intersection control type is unsupported.")
	var approaches: Dictionary = {}
	var previous_approach: FoundationTrafficApproach
	for approach in record.approaches:
		if previous_approach != null and FoundationTrafficApproach.less(approach, previous_approach):
			_add(issues, &"approach_order", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Approaches are not in canonical stable-ID order.")
		previous_approach = approach
		if String(approach.approach_id).is_empty() or approaches.has(approach.approach_id):
			_add(issues, &"duplicate_approach_identity", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Approach identities must be unique and non-empty.")
		approaches[approach.approach_id] = approach
		if approach.road_edge_id not in intersection.connected_edge_ids or not cross_sections_by_edge.has(approach.road_edge_id):
			_add(issues, &"invalid_approach_edge", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Approach references a disconnected or missing cross-section edge.")
		if not is_finite(approach.bearing_degrees) or approach.bearing_degrees < 0.0 or approach.bearing_degrees >= 360.0 or approach.priority_rank < 0:
			_add(issues, &"invalid_approach_policy", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Approach bearing or priority is invalid.")
		for lane_id in approach.inbound_lane_ids:
			if not lane_lookup.has(lane_id):
				_add(issues, &"missing_approach_lane", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Approach references a missing inbound lane.")
		for lane_id in approach.outbound_lane_ids:
			if not lane_lookup.has(lane_id):
				_add(issues, &"missing_approach_lane", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Approach references a missing outbound lane.")
	var movements: Dictionary = {}
	var previous_movement: FoundationTurnMovement
	for movement in record.movements:
		if previous_movement != null and FoundationTurnMovement.less(movement, previous_movement):
			_add(issues, &"movement_order", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Movements are not in canonical stable-ID order.")
		previous_movement = movement
		if String(movement.movement_id).is_empty() or movements.has(movement.movement_id):
			_add(issues, &"duplicate_movement_identity", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Movement identities must be unique and non-empty.")
		movements[movement.movement_id] = movement
		var from_approach := approaches.get(movement.from_approach_id) as FoundationTrafficApproach
		var to_approach := approaches.get(movement.to_approach_id) as FoundationTrafficApproach
		if from_approach == null or to_approach == null or from_approach == to_approach:
			_add(issues, &"invalid_movement_approach", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Movement approach lineage is missing or forms a U-turn.")
		elif movement.from_lane_id not in from_approach.inbound_lane_ids or movement.to_lane_id not in to_approach.outbound_lane_ids:
			_add(issues, &"invalid_movement_lane", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Movement lanes are not members of the referenced approaches.")
		if movement.turn_type not in [FoundationTurnMovement.TURN_LEFT, FoundationTurnMovement.TURN_THROUGH, FoundationTurnMovement.TURN_RIGHT]:
			_add(issues, &"invalid_turn_type", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Movement turn type is unsupported.")
		if movement.path_hint.size() < 3 or not _finite_points(movement.path_hint):
			_add(issues, &"invalid_movement_hint", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Movement path hint must contain finite inbound, node, and outbound points.")
		if record.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			var expected_movement_id := FoundationSpatialId.make(
				world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
				&"turn_movement", record.stable_id,
				"%s|%s|%s" % [movement.from_lane_id, movement.to_lane_id, movement.turn_type]
			)
			if movement.movement_id != expected_movement_id:
				_add(issues, &"movement_identity_mismatch", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Generated movement identity does not match its canonical lane-pair key.")
	if record.movements.size() > profile.maximum_movements_per_intersection:
		_add(issues, &"movement_cap", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Stored movements exceed the configured per-intersection cap.")
	_validate_phase_groups(record, movements, issues)
	if record.source_topology_fingerprint != FoundationTrafficMetadataGenerator.topology_fingerprint_for_intersection(intersection, cross_sections_by_edge):
		_add(issues, &"stale_intersection_traffic", FoundationTrafficMetadataValidationIssue.SEVERITY_WARNING, record, "Intersection traffic was derived from different topology or lane metadata.")
	_validate_generation_contract(record, profile, issues)
	_validate_stable_identity(world, record, FoundationTrafficMetadataGenerator.intersection_traffic_semantic(profile), profile, issues)
	_validate_ownership(world, record, issues)


static func _validate_phase_groups(
	record: FoundationIntersectionTrafficRecord,
	movements: Dictionary,
	issues: Array[FoundationTrafficMetadataValidationIssue]
) -> void:
	if record.control_type != FoundationIntersectionTrafficRecord.CONTROL_SIGNAL_PLAN:
		if not record.phase_groups.is_empty():
			_add(issues, &"unexpected_signal_phases", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Non-signal control cannot contain signal phase groups.")
		return
	if record.phase_groups.is_empty():
		_add(issues, &"missing_signal_phases", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Signal-plan control requires at least one movement phase group.")
		return
	var grouped: Dictionary = {}
	for group in record.phase_groups:
		if group.is_empty():
			_add(issues, &"empty_signal_phase", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Signal phase groups cannot be empty.")
		for movement_id in group:
			if not movements.has(StringName(movement_id)) or grouped.has(StringName(movement_id)):
				_add(issues, &"invalid_signal_phase_membership", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Signal phases reference missing or duplicate movements.")
			grouped[StringName(movement_id)] = true


static func _validate_generation_contract(
	record: FoundationSpatialRecord,
	profile: FoundationTrafficMetadataProfile,
	issues: Array[FoundationTrafficMetadataValidationIssue]
) -> void:
	if String(record.stable_id).is_empty():
		_add(issues, &"missing_stable_id", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Phase 13 records require stable identity.")
	if record.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED and (
		record.source_pass != FoundationTrafficMetadataGenerator.SOURCE_PASS or record.source_version != profile.generator_version
	):
		_add(issues, &"generation_source_mismatch", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Generated Phase 13 source pass/version is inconsistent.")


static func _validate_stable_identity(
	world: FoundationWorldData,
	record: FoundationSpatialRecord,
	semantic: String,
	profile: FoundationTrafficMetadataProfile,
	issues: Array[FoundationTrafficMetadataValidationIssue]
) -> void:
	if record.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
		return
	var expected := FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		record.entity_type, record.parent_id, semantic
	)
	if record.stable_id == expected:
		return
	var limit := profile.maximum_cross_sections + profile.maximum_intersection_records + 1
	for ordinal in range(1, limit + 1):
		var candidate := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			record.entity_type, record.parent_id, "%s|repair:%d" % [semantic, ordinal]
		)
		if record.stable_id == candidate:
			return
		if world.get_record(candidate) == null:
			break
	_add(issues, &"traffic_identity_mismatch", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Generated Phase 13 identity is not canonical or collision-repaired.")


static func _validate_ownership(
	world: FoundationWorldData,
	record: FoundationSpatialRecord,
	issues: Array[FoundationTrafficMetadataValidationIssue]
) -> void:
	var expected := world.coordinate_system.world_bounds_to_chunks(record.world_bounds)
	if expected != record.owning_chunks:
		_add(issues, &"chunk_ownership_mismatch", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, record, "Phase 13 chunk ownership does not match record bounds.")


static func _validate_layer_accounting(
	world: FoundationWorldData,
	profile: FoundationTrafficMetadataProfile,
	issues: Array[FoundationTrafficMetadataValidationIssue]
) -> void:
	if world.get_road_cross_sections().size() > profile.maximum_cross_sections or world.get_intersection_traffic().size() > profile.maximum_intersection_records:
		issues.append(FoundationTrafficMetadataValidationIssue.new(
			&"traffic_record_cap", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR,
			&"", &"", "Stored Phase 13 records exceed configured layer caps."
		))
	var layer := world.get_layer(FoundationWorldData.ROAD_CROSS_SECTION_LAYER)
	var counts: Dictionary = layer.metadata.get("counts", {}) if layer != null else {}
	if int(counts.get("generation_operation_count", 0)) > profile.maximum_generation_operations:
		issues.append(FoundationTrafficMetadataValidationIssue.new(
			&"generation_operation_cap", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR,
			&"", &"", "Stored Phase 13 work exceeds the configured operation cap."
		))


static func _finite_points(points: PackedVector3Array) -> bool:
	for point in points:
		if not is_finite(point.x) or not is_finite(point.y) or not is_finite(point.z):
			return false
	return true


static func _add(
	issues: Array[FoundationTrafficMetadataValidationIssue],
	kind: StringName,
	severity: StringName,
	record: FoundationSpatialRecord,
	message: String
) -> void:
	issues.append(FoundationTrafficMetadataValidationIssue.new(kind, severity, record.stable_id, record.parent_id, message))
