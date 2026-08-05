class_name FoundationRoadTopologyDebugProvider
extends FoundationDebugProvider

## Disposable Phase 2 graph, planning, and diagnostic batches. No production geometry.


func _init(p_provider_id: StringName = &"road_topology") -> void:
	super(p_provider_id)


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	var edge_layer := world.get_layer(FoundationWorldData.ROAD_EDGE_LAYER)
	var profile_data: Dictionary = edge_layer.metadata.get("profile", {}) if edge_layer != null else {}
	var elevation_offset := float(profile_data.get("debug_elevation_offset", 0.35))
	if provider_id == &"road_costs":
		_append_cost_debug(edge_layer, builder)
		return
	if provider_id == &"road_candidates":
		_append_candidate_debug(edge_layer, builder, elevation_offset)
		return
	if provider_id == &"road_validation":
		_append_validation_debug(edge_layer, builder, elevation_offset)
		return
	# Keep authoritative edges first so callers can compare the first debug vertex to route data.
	for edge in world.get_road_edges():
		var purpose := _edge_purpose(edge)
		if edge.stable_id == selected_id:
			purpose = &"selected"
		var debug_points := PackedVector3Array()
		for point in edge.route_points:
			debug_points.append(point + Vector3.UP * elevation_offset)
		builder.add_polyline(debug_points, false, purpose)
		builder.add_polyline(debug_points, false, _class_purpose(edge.road_class))
		if edge.terrain_cost / maxf(1.0, edge.planar_length) > 3.0:
			builder.add_polyline(debug_points, false, &"road_cost_high")
		if not debug_points.is_empty():
			var midpoint := debug_points[debug_points.size() / 2] + Vector3.UP * 2.0
			builder.add_text(
				midpoint,
				"%s | %s\n%s\nlogical %s\nL %.1f | cost %.1f | max %.1f deg\n%d chunks | %d regions" % [
					edge.road_class,
					edge.physical_profile_key,
					edge.stable_id,
					edge.logical_road_id,
					edge.planar_length,
					edge.terrain_cost,
					edge.maximum_slope_degrees,
					edge.owning_chunks.size(),
					edge.owning_regions.size(),
				],
				purpose
			)
			if (
				float(edge.grading_requirements.get("maximum_cut_depth", 0.0)) > 0.01
				or float(edge.grading_requirements.get("maximum_fill_height", 0.0)) > 0.01
				or bool(edge.grading_requirements.get("bridge_candidate", false))
			):
				builder.add_text(
					midpoint + Vector3.UP * 2.0,
					"grading: cut %.1f | fill %.1f | bridge %s | retaining %s" % [
						float(edge.grading_requirements.get("maximum_cut_depth", 0.0)),
						float(edge.grading_requirements.get("maximum_fill_height", 0.0)),
						bool(edge.grading_requirements.get("bridge_candidate", false)),
						bool(edge.grading_requirements.get("retaining_wall_candidate", false)),
					],
					&"road_grading_warning"
				)
		var desired_points := PackedVector3Array()
		for sample in edge.desired_elevation_samples:
			desired_points.append(Vector3(
				sample.world_position.x,
				sample.desired_elevation + elevation_offset + 0.15,
				sample.world_position.z
			))
			if sample.bridge_candidate or sample.retaining_wall_candidate or sample.grade_violation > 0.0:
				builder.add_point(desired_points[-1], 0.65, &"road_grading_warning")
		builder.add_polyline(desired_points, false, &"road_desired_elevation")
	for node in world.get_road_nodes():
		var purpose := _node_purpose(node)
		if node.stable_id == selected_id:
			purpose = &"selected"
		builder.add_point(node.world_position + Vector3.UP * 0.6, 1.5, purpose)
		builder.add_text(
			node.world_position + Vector3.UP * 3.0,
			"%s | %s\n%s\ndegree %d" % [
				node.node_kind, node.anchor_connection_intent, node.stable_id, node.incident_edge_ids.size()
			],
			purpose
		)
		if node.node_kind == FoundationRoadNode.ROLE_DEAD_END:
			builder.add_point(
				node.world_position + Vector3.UP * 1.0,
				2.0,
				&"road_cul_de_sac" if bool(node.metadata.get("cul_de_sac", false)) else &"road_dead_end"
			)
	for anchor in world.get_anchors():
		builder.add_point(
			anchor.world_position + Vector3.UP * 1.0,
			0.5 + anchor.priority_weight * 1.5,
			&"road_anchor_priority"
		)
	for pattern in world.get_road_pattern_areas():
		var pattern_purpose := _pattern_purpose(pattern.pattern_family)
		builder.add_rect(pattern.world_bounds, elevation_offset, pattern_purpose)
		builder.add_text(
			Vector3(pattern.world_bounds.get_center().x, elevation_offset + 2.0, pattern.world_bounds.get_center().y),
			"%s\n%s" % [pattern.pattern_family, pattern.stable_id],
			pattern_purpose
		)
	for intersection in world.get_road_intersections():
		var node := world.get_record(intersection.node_id) as FoundationRoadNode
		if node == null:
			continue
		builder.add_point(
			node.world_position + Vector3.UP * 1.1,
			1.0 + intersection.intersection_degree * 0.25,
			&"road_intersection"
		)
		builder.add_text(
			node.world_position + Vector3.UP * 4.0,
			"%s | degree %d" % [intersection.provisional_intersection_type, intersection.intersection_degree],
			&"road_intersection"
		)
	_append_generation_summary(world, edge_layer, builder)


func _node_purpose(node: FoundationRoadNode) -> StringName:
	match node.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"road_node_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"road_node_overridden"
		_:
			return &"road_node_generated"


func _edge_purpose(edge: FoundationRoadEdge) -> StringName:
	match edge.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"road_edge_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"road_edge_overridden"
		_:
			return &"road_edge_generated"


func _class_purpose(road_class: StringName) -> StringName:
	match road_class:
		FoundationRoadEdge.CLASS_HIGHWAY: return &"road_class_highway"
		FoundationRoadEdge.CLASS_ARTERIAL: return &"road_class_arterial"
		FoundationRoadEdge.CLASS_COLLECTOR: return &"road_class_collector"
		FoundationRoadEdge.CLASS_LOCAL: return &"road_class_local"
		FoundationRoadEdge.CLASS_ALLEY: return &"road_class_alley"
		FoundationRoadEdge.CLASS_DIRT: return &"road_class_dirt"
		_: return &"road_edge_generated"


func _pattern_purpose(pattern_family: StringName) -> StringName:
	match pattern_family:
		FoundationRoadPatternArea.DOWNTOWN_GRID, FoundationRoadPatternArea.MIXED_USE_GRID:
			return &"road_pattern_grid"
		FoundationRoadPatternArea.SUBURBAN_LOOPS, FoundationRoadPatternArea.TRAILER_PARK_SPINE:
			return &"road_pattern_suburban"
		FoundationRoadPatternArea.RURAL_TERRAIN_FOLLOWING:
			return &"road_pattern_rural"
		_:
			return &"road_pattern_other"


func _append_candidate_debug(
	edge_layer: FoundationSpatialLayer,
	builder: FoundationDebugGeometryBuilder,
	elevation_offset: float
) -> void:
	if edge_layer == null:
		return
	for candidate: Dictionary in edge_layer.metadata.get("connection_candidates", []):
		var from_data: Dictionary = candidate.get("from", {})
		var to_data: Dictionary = candidate.get("to", {})
		var from := Vector3(
			float(from_data.get("x", 0.0)),
			float(from_data.get("y", 0.0)) + elevation_offset,
			float(from_data.get("z", 0.0))
		)
		var to := Vector3(
			float(to_data.get("x", 0.0)),
			float(to_data.get("y", 0.0)) + elevation_offset,
			float(to_data.get("z", 0.0))
		)
		builder.add_line(
			from, to,
			&"road_candidate_accepted" if bool(candidate.get("accepted", false)) else &"road_candidate_rejected"
		)


func _append_cost_debug(
	edge_layer: FoundationSpatialLayer,
	builder: FoundationDebugGeometryBuilder
) -> void:
	if edge_layer == null:
		return
	for cell_data: Dictionary in edge_layer.metadata.get("routing_cost_cells", []):
		var coordinate: Dictionary = cell_data.get("cell", {})
		var cell_size := float(cell_data.get("cell_size", 1.0))
		var stride := int(cell_data.get("stride", 1))
		var bounds := Rect2(
			Vector2(float(coordinate.get("x", 0)) * cell_size, float(coordinate.get("y", 0)) * cell_size),
			Vector2.ONE * cell_size * stride
		)
		var cost := float(cell_data.get("cost", 0.0))
		var purpose := &"road_cost_low"
		if cost >= 100.0:
			purpose = &"road_cost_high"
		elif cost >= 20.0:
			purpose = &"road_cost_medium"
		builder.add_heatmap_cell(bounds, purpose)


func _append_validation_debug(
	edge_layer: FoundationSpatialLayer,
	builder: FoundationDebugGeometryBuilder,
	elevation_offset: float
) -> void:
	if edge_layer == null:
		return
	for issue_data: Dictionary in edge_layer.metadata.get("validation_issues", []):
		var position_data: Dictionary = issue_data.get("world_position", {})
		var position := Vector3(
			float(position_data.get("x", 0.0)),
			float(position_data.get("y", 0.0)) + elevation_offset + 1.0,
			float(position_data.get("z", 0.0))
		)
		var purpose := (
			&"road_validation_error"
			if String(issue_data.get("severity", "warning")) == "error"
			else &"road_validation_warning"
		)
		builder.add_point(position, 1.25, purpose)
		builder.add_text(
			position + Vector3.UP * 1.5,
			"%s: %s" % [issue_data.get("code", "issue"), issue_data.get("message", "")],
			purpose
		)


func _append_generation_summary(
	world: FoundationWorldData,
	edge_layer: FoundationSpatialLayer,
	builder: FoundationDebugGeometryBuilder
) -> void:
	if edge_layer == null:
		return
	var counts: Dictionary = edge_layer.metadata.get("generation_counts", {})
	var center := world.metadata.world_bounds.get_center()
	var validation_data: Array = edge_layer.metadata.get("validation_issues", [])
	builder.add_text(
		Vector3(center.x, 8.0, center.y),
		"Phase 2: %d nodes | %d edges | %d logical | %d intersections\n%d expanded cells | %d validation issues" % [
			world.get_road_nodes().size(),
			world.get_road_edges().size(),
			world.get_logical_roads().size(),
			world.get_road_intersections().size(),
			int(counts.get("expanded_cell_count", 0)),
			validation_data.size(),
		],
		&"label"
	)
