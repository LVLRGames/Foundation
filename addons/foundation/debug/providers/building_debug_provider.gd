class_name FoundationBuildingDebugProvider
extends FoundationDebugProvider

## Disposable batched Phase 5 footprint, extrusion, roof, label, and diagnostic view.


func _init() -> void:
	super(&"buildings")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	var layer := world.get_layer(FoundationWorldData.BUILDING_LAYER)
	var profile_data: Dictionary = layer.metadata.get("profile", {}) if layer != null else {}
	var debug_lift := float(profile_data.get("debug_elevation_offset", 0.34))
	for building in world.get_buildings():
		var outline_purpose := _outline_purpose(building)
		var roof_purpose := _roof_purpose(building)
		if building.stable_id == selected_id:
			outline_purpose = &"selected"
			roof_purpose = &"building_roof_selected"
		var base_height := building.base_elevation + debug_lift
		var top_height := base_height + building.height
		var base_points := PackedVector3Array()
		var top_points := PackedVector3Array()
		for point in building.footprint:
			base_points.append(Vector3(point.x, base_height, point.y))
			top_points.append(Vector3(point.x, top_height, point.y))
		builder.add_polygon_outline(base_points, outline_purpose)
		builder.add_polygon_outline(top_points, outline_purpose)
		builder.add_filled_polygon(top_points, roof_purpose)
		for index in range(building.footprint.size()):
			builder.add_line(base_points[index], top_points[index], outline_purpose)
		builder.add_text(
			Vector3(building.label_point.x, top_height + 1.2, building.label_point.y),
			"%s\nA %.1f | C %.2f\nS %.1f D %.1f R %.2f\n%d floors | H %.1f" % [
				building.stable_id, building.footprint_area, building.coverage_ratio,
				building.frontage_span, building.footprint_depth, building.footprint_aspect_ratio,
				building.floor_count, building.height,
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
		var point := Vector3(
			float(point_data.get("x", 0.0)), debug_lift + 0.8,
			float(point_data.get("y", 0.0))
		)
		var purpose: StringName = &"building_invalid" if diagnostic.get("severity", "") == String(FoundationBuildingValidationIssue.SEVERITY_ERROR) else &"building_skipped"
		builder.add_point(point, 0.7, purpose)
		builder.add_text(point + Vector3.UP, String(diagnostic.get("kind", "building diagnostic")), purpose)


func _outline_purpose(building: FoundationBuildingRecord) -> StringName:
	if building.validation_state == FoundationBuildingRecord.INVALID:
		return &"building_invalid"
	match building.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"building_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"building_overridden"
		_:
			return &"building_generated"


func _roof_purpose(building: FoundationBuildingRecord) -> StringName:
	if building.validation_state == FoundationBuildingRecord.INVALID:
		return &"building_roof_invalid"
	match building.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"building_roof_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"building_roof_overridden"
		_:
			return &"building_roof_generated"
