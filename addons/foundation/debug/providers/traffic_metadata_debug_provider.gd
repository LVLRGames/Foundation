class_name FoundationTrafficMetadataDebugProvider
extends FoundationDebugProvider

## Disposable Phase 13 lane, movement-hint, and control-policy inspection.


func _init() -> void:
	super(&"traffic_metadata")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	var layer := world.get_layer(FoundationWorldData.ROAD_CROSS_SECTION_LAYER)
	var profile_data: Dictionary = layer.metadata.get("profile", {}) if layer != null else {}
	var lift := float(profile_data.get("debug_elevation_offset", 0.72))
	for cross_section in world.get_road_cross_sections():
		var purpose := _cross_section_purpose(cross_section)
		if cross_section.stable_id == selected_id:
			purpose = &"selected"
		for lane in cross_section.lanes:
			var points := PackedVector3Array()
			for point in lane.centerline:
				points.append(point + Vector3.UP * lift)
			builder.add_polyline(points, false, purpose if cross_section.stable_id == selected_id else _lane_purpose(lane))
		if cross_section.stable_id == selected_id and not cross_section.lanes.is_empty():
			var midpoint := cross_section.lanes[0].centerline[cross_section.lanes[0].centerline.size() / 2]
			builder.add_text(
				midpoint + Vector3.UP * (lift + 1.5),
				"%s\n%d lanes | %.1f m | %.0f km/h" % [cross_section.stable_id, cross_section.lanes.size(), cross_section.carriageway_width, cross_section.speed_limit_kph],
				purpose
			)
	for traffic in world.get_intersection_traffic():
		var selected := traffic.stable_id == selected_id
		var node := world.get_record(traffic.node_id) as FoundationRoadNode
		if node == null:
			continue
		var purpose: StringName = &"selected" if selected else _control_purpose(traffic.control_type)
		builder.add_point(node.world_position + Vector3.UP * (lift + 0.2), 1.1, purpose)
		for movement in traffic.movements:
			var points := PackedVector3Array()
			for point in movement.path_hint:
				points.append(point + Vector3.UP * (lift + 0.12))
			builder.add_polyline(points, false, purpose if selected else _movement_purpose(movement.turn_type))
		builder.add_text(
			node.world_position + Vector3.UP * (lift + 3.0),
			"%s\n%s | %d approaches | %d movements | %d phases" % [traffic.stable_id, traffic.control_type, traffic.approaches.size(), traffic.movements.size(), traffic.phase_groups.size()],
			purpose
		)
	_append_diagnostics(layer, builder, lift)


func _append_diagnostics(
	layer: FoundationSpatialLayer,
	builder: FoundationDebugGeometryBuilder,
	lift: float
) -> void:
	if layer == null:
		return
	for diagnostic: Dictionary in layer.metadata.get("diagnostics", []):
		var point_data: Dictionary = diagnostic.get("point", diagnostic.get("details", {}).get("point", {}))
		if point_data.is_empty():
			continue
		var point := Vector3(float(point_data.get("x", 0.0)), lift + 1.0, float(point_data.get("y", 0.0)))
		var purpose: StringName = &"traffic_invalid" if diagnostic.get("severity", "") == String(FoundationTrafficMetadataValidationIssue.SEVERITY_ERROR) else &"traffic_warning"
		builder.add_point(point, 0.8, purpose)
		builder.add_text(point + Vector3.UP, String(diagnostic.get("kind", "traffic diagnostic")), purpose)


func _cross_section_purpose(record: FoundationRoadCrossSectionRecord) -> StringName:
	if record.validation_state == FoundationRoadCrossSectionRecord.INVALID:
		return &"traffic_invalid"
	match record.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED: return &"traffic_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN: return &"traffic_overridden"
		_: return &"traffic_lane_forward"


func _lane_purpose(lane: FoundationRoadLane) -> StringName:
	return &"traffic_lane_forward" if lane.direction == FoundationRoadLane.DIRECTION_FORWARD else &"traffic_lane_reverse"


func _movement_purpose(turn_type: StringName) -> StringName:
	match turn_type:
		FoundationTurnMovement.TURN_LEFT: return &"traffic_turn_left"
		FoundationTurnMovement.TURN_RIGHT: return &"traffic_turn_right"
		_: return &"traffic_turn_through"


func _control_purpose(control_type: StringName) -> StringName:
	match control_type:
		FoundationIntersectionTrafficRecord.CONTROL_SIGNAL_PLAN: return &"traffic_control_signal"
		FoundationIntersectionTrafficRecord.CONTROL_PRIORITY: return &"traffic_control_priority"
		FoundationIntersectionTrafficRecord.CONTROL_ALL_WAY_STOP: return &"traffic_control_stop"
		_: return &"traffic_warning"
