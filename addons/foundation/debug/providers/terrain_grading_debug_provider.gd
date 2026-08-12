class_name FoundationTerrainGradingDebugProvider
extends FoundationDebugProvider

## Disposable Phase 9 visualization sourced only from the current grading plan.


func _init() -> void:
	provider_id = &"terrain_grading"


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	_context: Dictionary
) -> void:
	invocation_count += 1
	if world == null or world.terrain_grading_plan == null:
		return
	var plan := world.terrain_grading_plan
	var elevation := plan.profile.debug_elevation_offset
	for operation in plan.operations:
		var source := world.get_record(operation.source_record_id)
		match operation.operation_kind:
			FoundationTerrainGradingOperation.KIND_ROAD_CORRIDOR:
				_append_road_segments(builder, source as FoundationRoadEdge, operation, elevation, &"grading_road")
			FoundationTerrainGradingOperation.KIND_BRIDGE_APPROACH:
				_append_road_segments(builder, source as FoundationRoadEdge, operation, elevation + 0.1, &"grading_bridge_approach")
			FoundationTerrainGradingOperation.KIND_BUILDING_PAD:
				var polygon := PackedVector3Array()
				for point_data: Dictionary in operation.metadata.get("footprint", []):
					polygon.append(Vector3(float(point_data.get("x", 0.0)), float(operation.metadata.get("target_elevation", operation.target_elevation_min)) + elevation, float(point_data.get("y", 0.0))))
				builder.add_polygon_outline(polygon, &"grading_pad")
				builder.add_filled_polygon(polygon, &"grading_pad_fill")
			FoundationTerrainGradingOperation.KIND_BRIDGE_SPAN:
				var start := _dict_to_vector3(operation.metadata.get("start_point", {})) + Vector3.UP * elevation
				var end := _dict_to_vector3(operation.metadata.get("end_point", {})) + Vector3.UP * elevation
				builder.add_line(start, end, &"grading_bridge")
				builder.add_point(start, 0.8, &"grading_bridge")
				builder.add_point(end, 0.8, &"grading_bridge")
		builder.add_text(
			Vector3(operation.world_bounds.get_center().x, operation.target_elevation_max + elevation + 1.0, operation.world_bounds.get_center().y),
			"%s\n%s | %d edits" % [operation.stable_id, operation.operation_kind, operation.edit_keys.size()],
			&"grading_label"
		)
	for edit in plan.edits:
		var world_xz := Vector2(edit.grid_vertex + plan.terrain_origin_cell) * plan.terrain_cell_size
		var purpose: StringName = &"grading_cut" if edit.target_height < edit.original_height else &"grading_fill"
		builder.add_line(
			Vector3(world_xz.x, edit.original_height + elevation, world_xz.y),
			Vector3(world_xz.x, edit.target_height + elevation, world_xz.y),
			purpose
		)
	for diagnostic in plan.diagnostics:
		var vertex_data: Dictionary = diagnostic.get("grid_vertex", {})
		var vertex := Vector2i(int(vertex_data.get("x", -1)), int(vertex_data.get("y", -1)))
		if vertex.x < 0 or vertex.y < 0:
			continue
		var world_xz := Vector2(vertex + plan.terrain_origin_cell) * plan.terrain_cell_size
		var purpose: StringName = &"grading_error" if diagnostic.get("severity", "") == "error" else &"grading_warning"
		builder.add_point(Vector3(world_xz.x, elevation + 2.0, world_xz.y), 0.8, purpose)


func _append_road_segments(
	builder: FoundationDebugGeometryBuilder,
	edge: FoundationRoadEdge,
	operation: FoundationTerrainGradingOperation,
	elevation: float,
	purpose: StringName
) -> void:
	if edge == null:
		return
	for segment_index in operation.metadata.get("segment_indices", []):
		var index := int(segment_index)
		if index < 0 or index + 1 >= edge.route_points.size():
			continue
		var from := _desired_point(edge, index) + Vector3.UP * elevation
		var to := _desired_point(edge, index + 1) + Vector3.UP * elevation
		builder.add_line(from, to, purpose)


func _desired_point(edge: FoundationRoadEdge, index: int) -> Vector3:
	var point := edge.route_points[index]
	if index < edge.desired_elevation_samples.size():
		point.y = edge.desired_elevation_samples[index].desired_elevation
	return point


func _dict_to_vector3(data: Dictionary) -> Vector3:
	return Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
