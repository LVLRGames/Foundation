class_name FoundationDefaultDebugProvider
extends FoundationDebugProvider

## Phase 1 world/region/chunk/grid/record providers behind one stable interface.


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	match provider_id:
		&"world_bounds":
			_append_world_bounds(world, builder)
		&"regions":
			_append_regions(world, builder)
		&"chunks":
			_append_chunks(world, builder, context)
		&"terrain_grid":
			_append_grid(world, builder, context)
		&"records":
			_append_records(world, builder, context)
		&"anchors":
			_append_anchors(world, builder, context)
		&"relationships":
			_append_relationships(world, builder, context)


func _append_world_bounds(world: FoundationWorldData, builder: FoundationDebugGeometryBuilder) -> void:
	builder.add_rect(world.metadata.world_bounds, 0.1, &"world_bounds")
	builder.add_text(_rect_center(world.metadata.world_bounds, 2.0), "FoundationWorld", &"world_bounds")


func _append_regions(world: FoundationWorldData, builder: FoundationDebugGeometryBuilder) -> void:
	for region in world.get_sorted_regions():
		builder.add_rect(region.world_bounds, 0.15, &"region_bounds")
		builder.add_text(
			_rect_center(region.world_bounds, 1.5),
			"%s\n(%d, %d)" % [region.stable_id, region.coordinate.x, region.coordinate.y],
			&"region_bounds"
		)


func _append_chunks(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	var selected_chunk: Vector2i = context.get("selected_chunk", Vector2i(2147483647, 2147483647))
	for chunk in world.get_sorted_chunks():
		var purpose: StringName = &"chunk_dirty" if not chunk.get_dirty_layers().is_empty() else &"chunk_clean"
		if chunk.coordinate == selected_chunk:
			purpose = &"selected"
		builder.add_rect(chunk.world_bounds, 0.2, purpose)
		if not chunk.get_dirty_layers().is_empty():
			builder.add_filled_rect(chunk.world_bounds, 0.025, &"chunk_dirty")
		builder.add_text(
			_rect_center(chunk.world_bounds, 1.0),
			"chunk %d, %d" % [chunk.coordinate.x, chunk.coordinate.y],
			purpose
		)


func _append_grid(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	var bounds := world.metadata.world_bounds
	var step := world.coordinate_system.cell_size
	var start_x: float = floor(bounds.position.x / step) * step
	var start_y: float = floor(bounds.position.y / step) * step
	var x := start_x
	while x <= bounds.end.x + 0.0001:
		builder.add_line(
			Vector3(x, 0.03, bounds.position.y),
			Vector3(x, 0.03, bounds.end.y),
			&"terrain_grid"
		)
		x += step
	var y := start_y
	while y <= bounds.end.y + 0.0001:
		builder.add_line(
			Vector3(bounds.position.x, 0.03, y),
			Vector3(bounds.end.x, 0.03, y),
			&"terrain_grid"
		)
		y += step
	var selected_chunk: Vector2i = context.get("selected_chunk", Vector2i(2147483647, 2147483647))
	if selected_chunk != Vector2i(2147483647, 2147483647):
		var chunk_bounds := world.coordinate_system.chunk_to_world_bounds(selected_chunk)
		var cell_origin := world.coordinate_system.chunk_to_terrain_cell_origin(selected_chunk)
		for local_vertex in [Vector2i.ZERO, Vector2i(world.coordinate_system.chunk_cells.x, 0), Vector2i(0, world.coordinate_system.chunk_cells.y), world.coordinate_system.chunk_cells]:
			var vertex := world.coordinate_system.chunk_local_vertex_to_terrain_vertex(selected_chunk, local_vertex)
			var position := world.coordinate_system.terrain_vertex_to_world(vertex, 1.0)
			builder.add_text(position, "vertex %d, %d" % [vertex.x, vertex.y], &"terrain_grid")
		builder.add_text(_rect_center(chunk_bounds, 1.0), "cell origin %d, %d" % [cell_origin.x, cell_origin.y], &"terrain_grid")
	var selected_id := StringName(context.get("selected_record_id", ""))
	var selected_record := world.get_record(selected_id)
	if selected_record != null:
		var center := selected_record.world_bounds.get_center()
		var cell := world.coordinate_system.world_to_terrain_cell(Vector3(center.x, 0.0, center.y))
		var vertex := world.coordinate_system.world_to_terrain_vertex(Vector3(center.x, 0.0, center.y))
		builder.add_text(Vector3(center.x, 1.0, center.y), "cell %d, %d | vertex %d, %d" % [cell.x, cell.y, vertex.x, vertex.y], &"terrain_grid")


func _append_records(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	var selected_id := StringName(context.get("selected_record_id", ""))
	for record in world.spatial_index.get_all_records():
		if record is FoundationCityAnchor:
			continue
		var purpose := _record_purpose(record)
		if record.stable_id == selected_id:
			purpose = &"selected"
		builder.add_rect(record.world_bounds, 0.45, purpose)
		builder.add_text(
			_rect_center(record.world_bounds, 2.5),
			"%s\n[%s]" % [record.stable_id, record.layer_type],
			purpose
		)


func _append_anchors(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	var selected_id := StringName(context.get("selected_record_id", ""))
	for anchor in world.get_anchors():
		var purpose := _anchor_purpose(anchor)
		if anchor.stable_id == selected_id:
			purpose = &"selected"
		var marker_position := anchor.world_position + Vector3.UP * 1.5
		builder.add_point(marker_position, 2.5, purpose)
		if anchor.has_influence():
			builder.add_rect(anchor.world_bounds, 0.35, &"anchor_influence")
		builder.add_text(
			marker_position + Vector3.UP * 2.0,
			"%s\n%s\npriority %.2f" % [
				anchor.anchor_category,
				anchor.stable_id,
				anchor.priority_weight,
			],
			purpose
		)


func _append_relationships(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	var selected_id := StringName(context.get("selected_record_id", ""))
	var selected := world.get_record(selected_id)
	if selected == null:
		return
	var selected_center := _rect_center(selected.world_bounds, 1.0)
	var parent := world.get_record(selected.parent_id)
	if parent != null:
		builder.add_arrow(selected_center, _rect_center(parent.world_bounds, 1.0), &"relationship")
	for child_id in selected.child_ids:
		var child := world.get_record(child_id)
		if child != null:
			builder.add_arrow(selected_center, _rect_center(child.world_bounds, 1.0), &"relationship")


func _record_purpose(record: FoundationSpatialRecord) -> StringName:
	match record.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"record_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"record_overridden"
		_:
			return &"record_generated"


func _anchor_purpose(anchor: FoundationCityAnchor) -> StringName:
	match anchor.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"anchor_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"anchor_overridden"
		_:
			return &"anchor_generated"


func _rect_center(bounds: Rect2, elevation: float) -> Vector3:
	return Vector3(bounds.get_center().x, elevation, bounds.get_center().y)
