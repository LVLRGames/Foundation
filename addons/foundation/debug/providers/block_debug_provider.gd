class_name FoundationBlockDebugProvider
extends FoundationDebugProvider

## Disposable Phase 3 outlines, concave-safe fills, labels, and diagnostics.


func _init() -> void:
	super(&"blocks")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	var layer := world.get_layer(FoundationWorldData.BLOCK_LAYER)
	var profile_data: Dictionary = layer.metadata.get("profile", {}) if layer != null else {}
	var elevation := float(profile_data.get("debug_elevation_offset", 0.18))
	for block in world.get_blocks():
		var outline_purpose := _outline_purpose(block)
		var fill_purpose := _fill_purpose(block)
		if block.stable_id == selected_id:
			outline_purpose = &"selected"
			fill_purpose = &"block_fill_selected"
		var points := PackedVector3Array()
		for point in block.outer_boundary:
			points.append(Vector3(point.x, elevation, point.y))
		builder.add_polygon_outline(points, outline_purpose)
		builder.add_filled_polygon(points, fill_purpose)
		builder.add_text(
			Vector3(block.label_point.x, elevation + 2.2, block.label_point.y),
			"%s\nA %.1f | %d roads\n%s" % [
				block.stable_id,
				block.area,
				block.boundary_road_ids.size(),
				block.validation_state,
			],
			outline_purpose
		)
	if layer == null:
		return
	for diagnostic: Dictionary in layer.metadata.get("diagnostics", []):
		var point_data: Dictionary = diagnostic.get("point", {})
		if point_data.is_empty():
			continue
		var point := Vector3(
			float(point_data.get("x", 0.0)),
			elevation + 1.0,
			float(point_data.get("y", 0.0))
		)
		builder.add_point(point, 0.8, &"block_invalid")
		builder.add_text(point + Vector3.UP, String(diagnostic.get("kind", "diagnostic")), &"block_invalid")


func _outline_purpose(block: FoundationBlockRecord) -> StringName:
	if block.validation_state != FoundationBlockRecord.VALID:
		return &"block_invalid"
	match block.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"block_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"block_overridden"
		_:
			return &"block_generated"


func _fill_purpose(block: FoundationBlockRecord) -> StringName:
	if block.validation_state != FoundationBlockRecord.VALID:
		return &"block_fill_invalid"
	match block.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"block_fill_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"block_fill_overridden"
		_:
			return &"block_fill_generated"
