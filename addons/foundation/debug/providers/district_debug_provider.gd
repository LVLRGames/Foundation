class_name FoundationDistrictDebugProvider
extends FoundationDebugProvider

## Disposable batched district coverage, policy, seed-link, label, and diagnostic view.


func _init() -> void:
	super(&"districts")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	var layer := world.get_layer(FoundationWorldData.DISTRICT_LAYER)
	var profile_data: Dictionary = layer.metadata.get("profile", {}) if layer != null else {}
	var elevation := float(profile_data.get("debug_elevation_offset", 0.46))
	for district in world.get_districts():
		var outline_purpose := _outline_purpose(district)
		var fill_purpose := _fill_purpose(district)
		if district.stable_id == selected_id:
			outline_purpose = &"selected"
			fill_purpose = &"district_fill_selected"
		for component in district.boundary_components:
			var points := PackedVector3Array()
			for point in component:
				points.append(Vector3(point.x, elevation, point.y))
			builder.add_filled_polygon(points, fill_purpose)
			builder.add_polygon_outline(points, outline_purpose)
			builder.add_polygon_outline(points, &"district_boundary")
		if not String(district.source_anchor_id).is_empty():
			var anchor := world.get_record(district.source_anchor_id) as FoundationCityAnchor
			if anchor != null:
				builder.add_arrow(
					Vector3(anchor.world_position.x, elevation + 0.2, anchor.world_position.z),
					Vector3(district.label_point.x, elevation + 0.2, district.label_point.y),
					&"district_seed_link"
				)
		builder.add_text(
			Vector3(district.label_point.x, elevation + 1.1, district.label_point.y),
			"%s\n%s | %s\n%d blocks | A %.0f | D %.2f" % [
				district.stable_id, district.character_key, district.primary_use,
				district.member_block_ids.size(), district.total_area, district.target_density,
			],
			outline_purpose
		)
	if layer == null:
		return
	for diagnostic: Dictionary in layer.metadata.get("diagnostics", []):
		var point_data: Dictionary = diagnostic.get("point", diagnostic.get("details", {}).get("point", {}))
		if point_data.is_empty():
			continue
		var point := Vector3(float(point_data.get("x", 0.0)), elevation + 0.8, float(point_data.get("y", 0.0)))
		var purpose: StringName = &"district_invalid" if diagnostic.get("severity", "") == String(FoundationDistrictValidationIssue.SEVERITY_ERROR) else &"district_warning"
		builder.add_point(point, 0.8, purpose)
		builder.add_text(point + Vector3.UP, String(diagnostic.get("kind", "district diagnostic")), purpose)


func _outline_purpose(district: FoundationDistrictRecord) -> StringName:
	if district.validation_state == FoundationDistrictRecord.INVALID:
		return &"district_invalid"
	match district.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"district_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"district_overridden"
		_:
			return StringName("district_%s" % district.character_key)


func _fill_purpose(district: FoundationDistrictRecord) -> StringName:
	if district.validation_state == FoundationDistrictRecord.INVALID:
		return &"district_fill_invalid"
	match district.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"district_fill_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"district_fill_overridden"
		_:
			return StringName("district_fill_%s" % district.character_key)
