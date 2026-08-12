class_name FoundationParkingDebugProvider
extends FoundationDebugProvider

## Disposable batched Phase 10 parking footprint, stall, access, and demand view.


func _init() -> void:
	super(&"parking_facilities")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	var layer := world.get_layer(FoundationWorldData.PARKING_FACILITY_LAYER)
	var profile_data: Dictionary = layer.metadata.get("profile", {}) if layer != null else {}
	var lift := float(profile_data.get("debug_elevation_offset", 0.58))
	for parking in world.get_parking_facilities():
		var purpose := _purpose(parking)
		var fill_purpose: StringName = &"parking_fill"
		if parking.stable_id == selected_id:
			purpose = &"selected"
			fill_purpose = &"parking_fill_selected"
		var elevation := parking.base_elevation + lift
		var points := PackedVector3Array()
		for point in parking.footprint:
			points.append(Vector3(point.x, elevation, point.y))
		builder.add_filled_polygon(points, fill_purpose)
		builder.add_polygon_outline(points, purpose)
		for space in parking.spaces:
			builder.add_polygon_outline(
				_space_points(space, elevation + 0.04),
				&"parking_accessible" if space.accessible else &"parking_stall"
			)
		for path in parking.access_paths:
			var path_points := PackedVector3Array()
			for point in path.points:
				path_points.append(Vector3(point.x, elevation + 0.08, point.y))
			builder.add_polyline(path_points, false, &"parking_access")
		builder.add_text(
			Vector3(parking.label_point.x, elevation + 1.0, parking.label_point.y),
			"%s\n%s | %d/%d | unmet %d" % [parking.stable_id, parking.facility_kind, parking.supplied_spaces, parking.demand_spaces, parking.unmet_demand],
			purpose
		)
		if parking.stable_id == selected_id:
			var lineage_record := world.get_record(parking.parent_building_id) if not String(parking.parent_building_id).is_empty() else world.get_record(parking.parent_id)
			var lineage_point := Vector2.ZERO
			if lineage_record is FoundationBuildingRecord:
				lineage_point = (lineage_record as FoundationBuildingRecord).label_point
			elif lineage_record is FoundationParcelRecord:
				lineage_point = (lineage_record as FoundationParcelRecord).label_point
			if lineage_record != null:
				builder.add_arrow(
					Vector3(parking.label_point.x, elevation + 0.18, parking.label_point.y),
					Vector3(lineage_point.x, elevation + 0.18, lineage_point.y),
					&"relationship"
				)
	_append_diagnostics(layer, builder, lift)


func _append_diagnostics(layer: FoundationSpatialLayer, builder: FoundationDebugGeometryBuilder, lift: float) -> void:
	if layer == null:
		return
	for diagnostic: Dictionary in layer.metadata.get("diagnostics", []):
		if not String(diagnostic.get("kind", "")).begins_with("parking"):
			continue
		var point_data: Dictionary = diagnostic.get("point", diagnostic.get("details", {}).get("point", {}))
		if point_data.is_empty():
			continue
		var point := Vector3(float(point_data.get("x", 0.0)), lift + 0.8, float(point_data.get("y", 0.0)))
		var purpose: StringName = &"parking_invalid" if diagnostic.get("severity", "") == String(FoundationSiteFeatureValidationIssue.SEVERITY_ERROR) else &"parking_warning"
		builder.add_point(point, 0.7, purpose)
		builder.add_text(point + Vector3.UP, String(diagnostic.get("kind", "parking diagnostic")), purpose)


func _purpose(parking: FoundationParkingFacilityRecord) -> StringName:
	if parking.validation_state == FoundationParkingFacilityRecord.INVALID:
		return &"parking_invalid"
	match parking.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"parking_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"parking_overridden"
		_:
			return &"parking_generated"


func _space_points(space: FoundationParkingSpace, elevation: float) -> PackedVector3Array:
	var angle := deg_to_rad(space.orientation_degrees)
	var run := Vector2(cos(angle), sin(angle))
	var depth := Vector2(-run.y, run.x)
	var half_run := run * space.width * 0.5
	var half_depth := depth * space.length * 0.5
	var points := PackedVector3Array()
	for point in [
		space.position - half_run - half_depth,
		space.position + half_run - half_depth,
		space.position + half_run + half_depth,
		space.position - half_run + half_depth,
	]:
		points.append(Vector3(point.x, elevation, point.y))
	return points
