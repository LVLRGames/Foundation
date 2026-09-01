class_name FoundationTrafficMetadataGenerator
extends RefCounted

## Deterministic bounded Phase 13 lanes, approaches, movements, and control metadata.

const SOURCE_PASS: StringName = &"phase_13_traffic_metadata_generation"


static func generate(
	world: FoundationWorldData,
	profile: FoundationTrafficMetadataProfile = null
) -> FoundationTrafficMetadataGenerationResult:
	var result := FoundationTrafficMetadataGenerationResult.new()
	if world == null:
		return result.fail("Traffic metadata generation requires FoundationWorldData.")
	var active_profile := profile if profile != null else FoundationTrafficMetadataProfile.new()
	var errors := active_profile.validation_errors()
	if not errors.is_empty():
		return result.fail("Invalid traffic metadata profile: %s" % "; ".join(errors))
	var edges := world.get_road_edges()
	var intersections := world.get_road_intersections()
	if edges.size() > active_profile.maximum_cross_sections:
		return result.fail("Road-edge count exceeds the configured cross-section cap.")
	if intersections.size() > active_profile.maximum_intersection_records:
		return result.fail("Intersection count exceeds the configured traffic-record cap.")
	world.register_layer_type(FoundationWorldData.ROAD_CROSS_SECTION_LAYER)
	world.register_layer_type(FoundationWorldData.INTERSECTION_TRAFFIC_LAYER)
	_remove_replaceable_records(world, result)

	var cross_sections_by_edge: Dictionary = {}
	for existing in world.get_road_cross_sections():
		if not cross_sections_by_edge.has(existing.road_edge_id):
			cross_sections_by_edge[existing.road_edge_id] = existing
	for edge in edges:
		result.generation_operation_count += 1
		if _cap_exceeded(active_profile, result):
			return _cap_failure(world, result)
		if cross_sections_by_edge.has(edge.stable_id):
			continue
		var cross_section := _create_cross_section(world, edge, active_profile, result)
		if _cap_exceeded(active_profile, result):
			return _cap_failure(world, result)
		if cross_section == null:
			continue
		world.register_record(cross_section)
		cross_sections_by_edge[edge.stable_id] = cross_section
		result.generated_cross_section_count += 1
		result.generated_lane_count += cross_section.lanes.size()

	var traffic_by_intersection: Dictionary = {}
	for existing in world.get_intersection_traffic():
		if not traffic_by_intersection.has(existing.intersection_id):
			traffic_by_intersection[existing.intersection_id] = existing
	for intersection in intersections:
		result.generation_operation_count += 1
		if _cap_exceeded(active_profile, result):
			return _cap_failure(world, result)
		if traffic_by_intersection.has(intersection.stable_id):
			continue
		var traffic := _create_intersection_traffic(world, intersection, cross_sections_by_edge, active_profile, result)
		if _cap_exceeded(active_profile, result):
			return _cap_failure(world, result)
		if traffic == null:
			continue
		world.register_record(traffic)
		traffic_by_intersection[intersection.stable_id] = traffic
		result.generated_intersection_traffic_count += 1
		result.generated_approach_count += traffic.approaches.size()
		result.generated_movement_count += traffic.movements.size()

	var issues := FoundationTrafficMetadataValidator.validate(world, active_profile)
	for issue in issues:
		result.diagnostics.append(issue.to_dict())
	result.diagnostics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	result.success = true
	_set_layer_metadata(world, active_profile, result)
	return result


static func clear_generated(world: FoundationWorldData) -> Dictionary:
	var counts := {"cross_sections": 0, "intersection_traffic": 0}
	if world == null:
		return counts
	for record in world.get_road_cross_sections():
		if record.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(record.stable_id)
			counts["cross_sections"] = int(counts["cross_sections"]) + 1
	for record in world.get_intersection_traffic():
		if record.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(record.stable_id)
			counts["intersection_traffic"] = int(counts["intersection_traffic"]) + 1
	return counts


static func topology_fingerprint_for_edge(edge: FoundationRoadEdge) -> String:
	var points: Array[Dictionary] = []
	for point in edge.route_points:
		points.append({"x": point.x, "y": point.y, "z": point.z})
	return FoundationSpatialRecordCodec.fingerprint({
		"stable_id": String(edge.stable_id),
		"from_node_id": String(edge.from_node_id),
		"to_node_id": String(edge.to_node_id),
		"road_class": String(edge.road_class),
		"logical_road_id": String(edge.logical_road_id),
		"physical_profile_key": String(edge.physical_profile_key),
		"directionality": String(edge.directionality),
		"allowed_movement_modes": Array(edge.allowed_movement_modes),
		"route_points": points,
	})


static func topology_fingerprint_for_intersection(
	intersection: FoundationIntersectionRecord,
	cross_sections_by_edge: Dictionary
) -> String:
	var edges: Array[Dictionary] = []
	for edge_id in intersection.connected_edge_ids:
		var cross_section := cross_sections_by_edge.get(edge_id) as FoundationRoadCrossSectionRecord
		edges.append({
			"edge_id": String(edge_id),
			"cross_section_id": String(cross_section.stable_id) if cross_section != null else "",
			"lane_ids": _lane_id_strings(cross_section.lanes) if cross_section != null else [],
		})
	return FoundationSpatialRecordCodec.fingerprint({
		"intersection_id": String(intersection.stable_id),
		"node_id": String(intersection.node_id),
		"connected_edges": edges,
	})


static func cross_section_semantic(profile: FoundationTrafficMetadataProfile) -> String:
	return "policy:%s|cross_section" % profile.policy_id


static func intersection_traffic_semantic(profile: FoundationTrafficMetadataProfile) -> String:
	return "policy:%s|intersection_traffic" % profile.policy_id


static func _remove_replaceable_records(
	world: FoundationWorldData,
	result: FoundationTrafficMetadataGenerationResult
) -> void:
	for cross_section in world.get_road_cross_sections():
		if cross_section.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(cross_section.stable_id)
		else:
			_refresh_ownership(world, cross_section)
			world.register_record(cross_section)
			result.preserved_cross_section_count += 1
	for traffic in world.get_intersection_traffic():
		if traffic.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(traffic.stable_id)
		else:
			_refresh_ownership(world, traffic)
			world.register_record(traffic)
			result.preserved_intersection_traffic_count += 1


static func _create_cross_section(
	world: FoundationWorldData,
	edge: FoundationRoadEdge,
	profile: FoundationTrafficMetadataProfile,
	result: FoundationTrafficMetadataGenerationResult
) -> FoundationRoadCrossSectionRecord:
	if edge.route_points.size() < 2:
		result.add_diagnostic(&"cross_section_missing_route", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, {
			"record_id": String(edge.stable_id),
		})
		return null
	var directions: Array[StringName] = []
	match edge.directionality:
		FoundationRoadEdge.DIRECTION_ONE_WAY_FORWARD:
			directions.append(FoundationRoadLane.DIRECTION_FORWARD)
		FoundationRoadEdge.DIRECTION_ONE_WAY_REVERSE:
			directions.append(FoundationRoadLane.DIRECTION_REVERSE)
		_:
			directions.append(FoundationRoadLane.DIRECTION_FORWARD)
			directions.append(FoundationRoadLane.DIRECTION_REVERSE)
	var lanes_per_direction := profile.lane_count_per_direction(edge.road_class)
	if directions.size() * lanes_per_direction > profile.maximum_lanes_per_edge:
		result.add_diagnostic(&"lane_cap", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, {
			"record_id": String(edge.stable_id),
		})
		return null
	var stable_id := FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		FoundationRoadCrossSectionRecord.ENTITY_TYPE, edge.stable_id, cross_section_semantic(profile)
	)
	stable_id = _repair_id(world, FoundationRoadCrossSectionRecord.ENTITY_TYPE, edge.stable_id, cross_section_semantic(profile), stable_id, profile)
	if String(stable_id).is_empty():
		result.add_diagnostic(&"stable_id_exhausted", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, {"record_id": String(edge.stable_id)})
		return null
	var record := FoundationRoadCrossSectionRecord.new(stable_id, edge.stable_id, edge.world_bounds)
	record.logical_road_id = edge.logical_road_id
	record.physical_profile_key = edge.physical_profile_key
	record.speed_limit_kph = profile.speed_limit_for(edge.road_class)
	record.median_width = profile.median_width_divided if edge.directionality == FoundationRoadEdge.DIRECTION_DIVIDED_CONCEPT else 0.0
	record.shoulder_width = profile.shoulder_width_highway if edge.road_class == FoundationRoadEdge.CLASS_HIGHWAY else 0.0
	record.sidewalk_width = 0.0 if edge.road_class in [FoundationRoadEdge.CLASS_HIGHWAY, FoundationRoadEdge.CLASS_DIRT] else profile.sidewalk_width_urban
	var lane_width := profile.lane_width_for(edge.road_class)
	for direction in directions:
		for lane_index in range(lanes_per_direction):
			result.generation_operation_count += 1
			if _cap_exceeded(profile, result):
				return null
			var lane_id := FoundationSpatialId.make(
				world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
				&"road_lane", record.stable_id, "%s:%d" % [direction, lane_index]
			)
			var lane := FoundationRoadLane.new(lane_id, lane_index, direction)
			lane.width = lane_width
			lane.speed_limit_kph = record.speed_limit_kph
			lane.abstract_capacity_per_hour = profile.capacity_per_lane_for(edge.road_class)
			lane.allowed_movement_modes = _lane_modes(edge.allowed_movement_modes)
			lane.turn_permissions = _turn_permissions(lane_index, lanes_per_direction)
			var oriented_points := edge.route_points.duplicate()
			if direction == FoundationRoadLane.DIRECTION_REVERSE:
				oriented_points.reverse()
			var offset := record.median_width * 0.5 + lane_width * (float(lane_index) + 0.5)
			lane.centerline = _offset_polyline(oriented_points, offset)
			record.lanes.append(lane)
	record.source_topology_fingerprint = topology_fingerprint_for_edge(edge)
	record.source_pass = SOURCE_PASS
	record.source_version = profile.generator_version
	record.tags = PackedStringArray(["phase_13", "road_cross_section", String(edge.road_class)])
	record.refresh_metrics()
	_refresh_ownership(world, record)
	return record


static func _create_intersection_traffic(
	world: FoundationWorldData,
	intersection: FoundationIntersectionRecord,
	cross_sections_by_edge: Dictionary,
	profile: FoundationTrafficMetadataProfile,
	result: FoundationTrafficMetadataGenerationResult
) -> FoundationIntersectionTrafficRecord:
	var node := world.get_record(intersection.node_id) as FoundationRoadNode
	if node == null:
		result.add_diagnostic(&"traffic_missing_node", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, {
			"record_id": String(intersection.stable_id),
		})
		return null
	var stable_id := FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		FoundationIntersectionTrafficRecord.ENTITY_TYPE, intersection.stable_id, intersection_traffic_semantic(profile)
	)
	stable_id = _repair_id(world, FoundationIntersectionTrafficRecord.ENTITY_TYPE, intersection.stable_id, intersection_traffic_semantic(profile), stable_id, profile)
	if String(stable_id).is_empty():
		result.add_diagnostic(&"stable_id_exhausted", FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR, {"record_id": String(intersection.stable_id)})
		return null
	var traffic := FoundationIntersectionTrafficRecord.new(stable_id, intersection.stable_id, intersection.node_id, node.world_position)
	traffic.control_type = _control_type(world, intersection, profile)
	var lane_lookup: Dictionary = {}
	for edge_id in intersection.connected_edge_ids:
		result.generation_operation_count += 1
		if _cap_exceeded(profile, result):
			return null
		var edge := world.get_record(edge_id) as FoundationRoadEdge
		var cross_section := cross_sections_by_edge.get(edge_id) as FoundationRoadCrossSectionRecord
		if edge == null or cross_section == null:
			result.add_diagnostic(&"traffic_missing_cross_section", FoundationTrafficMetadataValidationIssue.SEVERITY_WARNING, {
				"record_id": String(intersection.stable_id), "road_edge_id": String(edge_id),
			})
			continue
		var approach_id := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			&"traffic_approach", traffic.stable_id, String(edge_id)
		)
		var approach := FoundationTrafficApproach.new(approach_id, edge_id)
		approach.bearing_degrees = _approach_bearing(edge, intersection.node_id)
		approach.priority_rank = profile.priority_rank_for(edge.road_class)
		for lane in cross_section.lanes:
			lane_lookup[lane.lane_id] = lane
			if _lane_enters_node(lane, edge, intersection.node_id):
				approach.inbound_lane_ids.append(lane.lane_id)
			if _lane_leaves_node(lane, edge, intersection.node_id):
				approach.outbound_lane_ids.append(lane.lane_id)
		approach.inbound_lane_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		approach.outbound_lane_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		traffic.approaches.append(approach)
	traffic.approaches.sort_custom(FoundationTrafficApproach.less)
	for from_approach in traffic.approaches:
		for to_approach in traffic.approaches:
			if from_approach.approach_id == to_approach.approach_id or to_approach.outbound_lane_ids.is_empty():
				continue
			var turn_type := _turn_type(from_approach.bearing_degrees, to_approach.bearing_degrees)
			for inbound_index in range(from_approach.inbound_lane_ids.size()):
				result.generation_operation_count += 1
				if _cap_exceeded(profile, result):
					return null
				var from_lane := lane_lookup.get(from_approach.inbound_lane_ids[inbound_index]) as FoundationRoadLane
				if from_lane == null or String(turn_type) not in from_lane.turn_permissions:
					continue
				var target_index := mini(inbound_index, to_approach.outbound_lane_ids.size() - 1)
				var to_lane := lane_lookup.get(to_approach.outbound_lane_ids[target_index]) as FoundationRoadLane
				if to_lane == null:
					continue
				if traffic.movements.size() >= profile.maximum_movements_per_intersection:
					result.add_diagnostic(&"movement_cap", FoundationTrafficMetadataValidationIssue.SEVERITY_WARNING, {
						"record_id": String(intersection.stable_id),
					})
					break
				var movement := FoundationTurnMovement.new()
				movement.from_approach_id = from_approach.approach_id
				movement.to_approach_id = to_approach.approach_id
				movement.from_lane_id = from_lane.lane_id
				movement.to_lane_id = to_lane.lane_id
				movement.turn_type = turn_type
				movement.priority_rank = from_approach.priority_rank + _turn_priority(turn_type)
				movement.conflict_group_id = StringName("approach:%s" % from_approach.approach_id)
				movement.movement_id = FoundationSpatialId.make(
					world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
					&"turn_movement", traffic.stable_id,
					"%s|%s|%s" % [from_lane.lane_id, to_lane.lane_id, turn_type]
				)
				movement.path_hint = PackedVector3Array([
					from_lane.centerline[-1], node.world_position, to_lane.centerline[0],
				])
				traffic.movements.append(movement)
	if traffic.control_type == FoundationIntersectionTrafficRecord.CONTROL_SIGNAL_PLAN:
		for approach in traffic.approaches:
			var group := PackedStringArray()
			for movement in traffic.movements:
				if movement.from_approach_id == approach.approach_id and movement.permitted:
					group.append(String(movement.movement_id))
			if not group.is_empty():
				group.sort()
				traffic.phase_groups.append(group)
	traffic.source_topology_fingerprint = topology_fingerprint_for_intersection(intersection, cross_sections_by_edge)
	traffic.source_pass = SOURCE_PASS
	traffic.source_version = profile.generator_version
	traffic.tags = PackedStringArray(["phase_13", "intersection_traffic", String(traffic.control_type)])
	traffic.refresh_order()
	_refresh_ownership(world, traffic)
	return traffic


static func _control_type(
	world: FoundationWorldData,
	intersection: FoundationIntersectionRecord,
	profile: FoundationTrafficMetadataProfile
) -> StringName:
	var best_rank := 99
	var worst_rank := -1
	for edge_id in intersection.connected_edge_ids:
		var edge := world.get_record(edge_id) as FoundationRoadEdge
		if edge == null:
			continue
		var rank := profile.priority_rank_for(edge.road_class)
		best_rank = mini(best_rank, rank)
		worst_rank = maxi(worst_rank, rank)
	if best_rank == 0 or worst_rank - best_rank >= 2:
		return FoundationIntersectionTrafficRecord.CONTROL_PRIORITY
	if profile.enable_signal_plans and intersection.intersection_degree >= profile.signal_minimum_degree and best_rank <= 1:
		return FoundationIntersectionTrafficRecord.CONTROL_SIGNAL_PLAN
	return FoundationIntersectionTrafficRecord.CONTROL_ALL_WAY_STOP


static func _lane_enters_node(lane: FoundationRoadLane, edge: FoundationRoadEdge, node_id: StringName) -> bool:
	return (
		lane.direction == FoundationRoadLane.DIRECTION_FORWARD and edge.to_node_id == node_id
	) or (
		lane.direction == FoundationRoadLane.DIRECTION_REVERSE and edge.from_node_id == node_id
	)


static func _lane_leaves_node(lane: FoundationRoadLane, edge: FoundationRoadEdge, node_id: StringName) -> bool:
	return (
		lane.direction == FoundationRoadLane.DIRECTION_FORWARD and edge.from_node_id == node_id
	) or (
		lane.direction == FoundationRoadLane.DIRECTION_REVERSE and edge.to_node_id == node_id
	)


static func _approach_bearing(edge: FoundationRoadEdge, node_id: StringName) -> float:
	var outward := Vector2.ZERO
	if edge.from_node_id == node_id:
		outward = Vector2(edge.route_points[1].x - edge.route_points[0].x, edge.route_points[1].z - edge.route_points[0].z)
	else:
		var last := edge.route_points.size() - 1
		outward = Vector2(edge.route_points[last - 1].x - edge.route_points[last].x, edge.route_points[last - 1].z - edge.route_points[last].z)
	var degrees := rad_to_deg(atan2(outward.y, outward.x))
	return fposmod(degrees, 360.0)


static func _turn_type(from_bearing: float, to_bearing: float) -> StringName:
	var inbound := Vector2.from_angle(deg_to_rad(from_bearing)) * -1.0
	var outbound := Vector2.from_angle(deg_to_rad(to_bearing))
	var angle := rad_to_deg(inbound.angle_to(outbound))
	if absf(angle) <= 35.0:
		return FoundationTurnMovement.TURN_THROUGH
	return FoundationTurnMovement.TURN_RIGHT if angle > 0.0 else FoundationTurnMovement.TURN_LEFT


static func _turn_priority(turn_type: StringName) -> int:
	match turn_type:
		FoundationTurnMovement.TURN_THROUGH: return 0
		FoundationTurnMovement.TURN_RIGHT: return 1
		_: return 2


static func _turn_permissions(lane_index: int, lane_count: int) -> PackedStringArray:
	if lane_count <= 1:
		return PackedStringArray(["left", "through", "right"])
	if lane_index == 0:
		return PackedStringArray(["left", "through"])
	if lane_index == lane_count - 1:
		return PackedStringArray(["through", "right"])
	return PackedStringArray(["through"])


static func _lane_modes(edge_modes: PackedStringArray) -> PackedStringArray:
	var modes := PackedStringArray()
	for mode in edge_modes:
		if mode != "pedestrian":
			modes.append(mode)
	if modes.is_empty():
		modes.append("motor_vehicle")
	return modes


static func _offset_polyline(points: PackedVector3Array, offset: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	for index in range(points.size()):
		var previous := points[maxi(0, index - 1)]
		var following := points[mini(points.size() - 1, index + 1)]
		var tangent := Vector2(following.x - previous.x, following.z - previous.z).normalized()
		if tangent == Vector2.ZERO:
			tangent = Vector2.RIGHT
		var right := Vector2(-tangent.y, tangent.x)
		result.append(points[index] + Vector3(right.x * offset, 0.0, right.y * offset))
	return result


static func _repair_id(
	world: FoundationWorldData,
	entity_type: StringName,
	parent_id: StringName,
	semantic: String,
	preferred_id: StringName,
	profile: FoundationTrafficMetadataProfile
) -> StringName:
	if world.get_record(preferred_id) == null:
		return preferred_id
	for ordinal in range(1, profile.maximum_cross_sections + profile.maximum_intersection_records + 2):
		var candidate := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			entity_type, parent_id, "%s|repair:%d" % [semantic, ordinal]
		)
		if world.get_record(candidate) == null:
			return candidate
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


static func _cap_exceeded(
	profile: FoundationTrafficMetadataProfile,
	result: FoundationTrafficMetadataGenerationResult
) -> bool:
	return result.generation_operation_count > profile.maximum_generation_operations


static func _cap_failure(
	world: FoundationWorldData,
	result: FoundationTrafficMetadataGenerationResult
) -> FoundationTrafficMetadataGenerationResult:
	clear_generated(world)
	return result.fail("Traffic metadata generation exceeded the configured operation cap; partial generated records were removed.")


static func _set_layer_metadata(
	world: FoundationWorldData,
	profile: FoundationTrafficMetadataProfile,
	result: FoundationTrafficMetadataGenerationResult
) -> void:
	for layer_type in [FoundationWorldData.ROAD_CROSS_SECTION_LAYER, FoundationWorldData.INTERSECTION_TRAFFIC_LAYER]:
		var layer := world.get_layer(layer_type)
		if layer == null:
			continue
		layer.metadata["phase"] = 13
		layer.metadata["profile"] = profile.to_dict()
		layer.metadata["counts"] = result.to_dict()
		layer.metadata["diagnostics"] = result.diagnostics.duplicate(true)


static func _lane_id_strings(lanes: Array[FoundationRoadLane]) -> Array[String]:
	var result: Array[String] = []
	for lane in lanes:
		result.append(String(lane.lane_id))
	return result
