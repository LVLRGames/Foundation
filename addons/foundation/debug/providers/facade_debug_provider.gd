class_name FoundationFacadeDebugProvider
extends FoundationDebugProvider

## Disposable batched Phase 7 facade grid, opening, label, and diagnostic view.


func _init() -> void:
	super(&"facades")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	var layer := world.get_layer(FoundationWorldData.FACADE_LAYER)
	var profile_data: Dictionary = layer.metadata.get("profile", {}) if layer != null else {}
	var surface_offset := float(profile_data.get("debug_surface_offset", 0.05))
	for facade in world.get_facades():
		var purpose := _facade_purpose(facade)
		if facade.stable_id == selected_id:
			purpose = &"selected"
		var tangent := (facade.end - facade.start).normalized()
		var offset := facade.outward_normal * surface_offset
		var base_start := _point(facade, tangent, offset, 0.0, 0.0)
		var base_end := _point(facade, tangent, offset, facade.facade_length, 0.0)
		var top_start := _point(facade, tangent, offset, 0.0, facade.height)
		var top_end := _point(facade, tangent, offset, facade.facade_length, facade.height)
		builder.add_line(base_start, base_end, purpose)
		builder.add_line(base_end, top_end, purpose)
		builder.add_line(top_end, top_start, purpose)
		builder.add_line(top_start, base_start, purpose)
		for floor_index in range(1, facade.floor_count):
			var elevation := float(floor_index) * facade.floor_height
			builder.add_line(
				_point(facade, tangent, offset, 0.0, elevation),
				_point(facade, tangent, offset, facade.facade_length, elevation),
				&"facade_grid"
			)
		for bay_index in range(1, facade.bay_count):
			var horizontal := float(bay_index) * facade.bay_width
			builder.add_line(
				_point(facade, tangent, offset, horizontal, 0.0),
				_point(facade, tangent, offset, horizontal, facade.height),
				&"facade_grid"
			)
		for module in facade.modules:
			if module.kind == FoundationFacadeModule.KIND_WINDOW:
				_append_module_outline(builder, facade, module, tangent, offset, &"facade_window")
			elif module.kind == FoundationFacadeModule.KIND_ENTRANCE:
				_append_module_outline(builder, facade, module, tangent, offset, &"facade_entrance")
		var midpoint := (facade.start + facade.end) * 0.5 + offset
		builder.add_text(
			Vector3(midpoint.x, facade.base_elevation + facade.height + 0.8, midpoint.y),
			"%s\n%s | %d bays | %.0f%% glass" % [
				facade.stable_id, facade.facade_role, facade.bay_count, facade.glazing_ratio * 100.0,
			],
			purpose
		)
	if layer == null:
		return
	for diagnostic: Dictionary in layer.metadata.get("diagnostics", []):
		var point_data: Dictionary = diagnostic.get("point", {})
		if point_data.is_empty():
			continue
		var point := Vector3(float(point_data.get("x", 0.0)), 1.0, float(point_data.get("y", 0.0)))
		var purpose: StringName = &"facade_invalid" if diagnostic.get("severity", "") == String(FoundationFacadeValidationIssue.SEVERITY_ERROR) else &"facade_skipped"
		builder.add_point(point, 0.7, purpose)
		builder.add_text(point + Vector3.UP, String(diagnostic.get("kind", "facade diagnostic")), purpose)


func _append_module_outline(
	builder: FoundationDebugGeometryBuilder,
	facade: FoundationFacadeRecord,
	module: FoundationFacadeModule,
	tangent: Vector2,
	offset: Vector2,
	purpose: StringName
) -> void:
	var lower_left := _point(facade, tangent, offset, module.horizontal_start, module.vertical_start)
	var lower_right := _point(facade, tangent, offset, module.horizontal_end, module.vertical_start)
	var upper_right := _point(facade, tangent, offset, module.horizontal_end, module.vertical_end)
	var upper_left := _point(facade, tangent, offset, module.horizontal_start, module.vertical_end)
	builder.add_line(lower_left, lower_right, purpose)
	builder.add_line(lower_right, upper_right, purpose)
	builder.add_line(upper_right, upper_left, purpose)
	builder.add_line(upper_left, lower_left, purpose)


func _point(
	facade: FoundationFacadeRecord,
	tangent: Vector2,
	offset: Vector2,
	horizontal: float,
	vertical: float
) -> Vector3:
	var position := facade.start + tangent * horizontal + offset
	return Vector3(position.x, facade.base_elevation + vertical, position.y)


func _facade_purpose(facade: FoundationFacadeRecord) -> StringName:
	if facade.validation_state == FoundationFacadeRecord.INVALID:
		return &"facade_invalid"
	match facade.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"facade_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"facade_overridden"
	match facade.facade_role:
		FoundationFacadeRecord.ROLE_PRIMARY:
			return &"facade_primary"
		FoundationFacadeRecord.ROLE_REAR:
			return &"facade_rear"
		_:
			return &"facade_side"
