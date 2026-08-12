class_name FoundationParcelDebugProvider
extends FoundationDebugProvider

## Disposable Phase 4 parcel fills, frontage lines, labels, and validation markers.


func _init() -> void:
	super(&"parcels")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	var layer := world.get_layer(FoundationWorldData.PARCEL_LAYER)
	var profile_data: Dictionary = layer.metadata.get("profile", {}) if layer != null else {}
	var elevation := float(profile_data.get("debug_elevation_offset", 0.24))
	for parcel in world.get_parcels():
		var outline_purpose := _outline_purpose(parcel)
		var fill_purpose := _fill_purpose(parcel)
		if parcel.stable_id == selected_id:
			outline_purpose = &"selected"
			fill_purpose = &"parcel_fill_selected"
		var points := PackedVector3Array()
		for point in parcel.boundary:
			points.append(Vector3(point.x, elevation, point.y))
		builder.add_polygon_outline(points, outline_purpose)
		builder.add_filled_polygon(points, fill_purpose)
		for reference in parcel.frontage_references:
			if reference.parcel_boundary_segment_index < 0 or reference.parcel_boundary_segment_index >= parcel.boundary.size():
				continue
			var first := parcel.boundary[reference.parcel_boundary_segment_index]
			var second := parcel.boundary[(reference.parcel_boundary_segment_index + 1) % parcel.boundary.size()]
			var purpose: StringName = &"parcel_frontage_primary" if reference.frontage_classification == FoundationParcelFrontageReference.CLASS_PRIMARY else &"parcel_frontage_secondary"
			builder.add_line(Vector3(first.x, elevation + 0.05, first.y), Vector3(second.x, elevation + 0.05, second.y), purpose)
		builder.add_text(
			Vector3(parcel.label_point.x, elevation + 1.6, parcel.label_point.y),
			"%s\n%s | A %.1f\nF %.1f D %.1f R %.2f\nRow %d | %s" % [
				parcel.stable_id, parcel.parcel_kind, parcel.area,
				parcel.approximate_frontage_width, parcel.approximate_depth, parcel.approximate_aspect_ratio,
				parcel.frontage_row_index,
				parcel.access_state,
			],
			outline_purpose
		)
	if layer == null:
		return
	for diagnostic: Dictionary in layer.metadata.get("diagnostics", []):
		var details: Dictionary = diagnostic.get("details", {})
		var point_data: Dictionary = diagnostic.get("point", details.get("point", {}))
		if point_data.is_empty():
			continue
		var point := Vector3(float(point_data.get("x", 0.0)), elevation + 0.8, float(point_data.get("y", 0.0)))
		builder.add_point(point, 0.7, &"parcel_invalid")
		builder.add_text(point + Vector3.UP, String(diagnostic.get("kind", "parcel diagnostic")), &"parcel_invalid")


func _outline_purpose(parcel: FoundationParcelRecord) -> StringName:
	if parcel.validation_state == FoundationParcelRecord.INVALID:
		return &"parcel_invalid"
	match parcel.parcel_kind:
		FoundationParcelRecord.KIND_CORNER:
			return &"parcel_corner"
		FoundationParcelRecord.KIND_FLAG_ACCESS, FoundationParcelRecord.KIND_REMAINDER:
			return &"parcel_remainder"
	match parcel.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"parcel_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"parcel_overridden"
		_:
			return &"parcel_generated"


func _fill_purpose(parcel: FoundationParcelRecord) -> StringName:
	if parcel.validation_state == FoundationParcelRecord.INVALID:
		return &"parcel_fill_invalid"
	match parcel.parcel_kind:
		FoundationParcelRecord.KIND_CORNER:
			return &"parcel_fill_corner"
		FoundationParcelRecord.KIND_FLAG_ACCESS, FoundationParcelRecord.KIND_REMAINDER:
			return &"parcel_fill_remainder"
		_:
			return &"parcel_fill_generated"
