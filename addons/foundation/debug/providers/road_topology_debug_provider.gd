class_name FoundationRoadTopologyDebugProvider
extends FoundationDebugProvider

## Disposable Phase 2 topology lines and markers. No production road geometry is created.


func _init() -> void:
	super(&"road_topology")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	for edge in world.get_road_edges():
		var purpose := _edge_purpose(edge)
		if edge.stable_id == selected_id:
			purpose = &"selected"
		builder.add_polyline(edge.route_points, false, purpose)
		if not edge.route_points.is_empty():
			var midpoint := edge.route_points[edge.route_points.size() / 2] + Vector3.UP * 2.0
			builder.add_text(
				midpoint,
				"%s\n%s\nL %.1f | cost %.1f | max %.1f°\n%d chunks | %d regions" % [
					edge.road_class,
					edge.stable_id,
					edge.planar_length,
					edge.terrain_cost,
					edge.maximum_slope_degrees,
					edge.owning_chunks.size(),
					edge.owning_regions.size(),
				],
				purpose
			)
	for node in world.get_road_nodes():
		var purpose := _node_purpose(node)
		if node.stable_id == selected_id:
			purpose = &"selected"
		builder.add_point(node.world_position + Vector3.UP * 0.6, 1.5, purpose)
		builder.add_text(
			node.world_position + Vector3.UP * 3.0,
			"%s\n%s\ndegree %d" % [node.node_kind, node.stable_id, node.incident_edge_ids.size()],
			purpose
		)


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
