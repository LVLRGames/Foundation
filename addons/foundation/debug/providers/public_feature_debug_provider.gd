class_name FoundationPublicFeatureDebugProvider
extends FoundationDebugProvider

## Disposable batched Phase 10 public-site, service-radius, anchor-link, and label view.


func _init() -> void:
	super(&"public_features")


func append_debug(
	world: FoundationWorldData,
	builder: FoundationDebugGeometryBuilder,
	context: Dictionary
) -> void:
	invocation_count += 1
	var selected_id := StringName(context.get("selected_record_id", ""))
	var layer := world.get_layer(FoundationWorldData.PUBLIC_FEATURE_LAYER)
	var profile_data: Dictionary = layer.metadata.get("profile", {}) if layer != null else {}
	var lift := float(profile_data.get("debug_elevation_offset", 0.58)) + 0.06
	for feature in world.get_public_features():
		var purpose := _purpose(feature)
		var fill_purpose: StringName = &"public_feature_fill"
		if feature.stable_id == selected_id:
			purpose = &"selected"
			fill_purpose = &"public_feature_fill_selected"
		var elevation := feature.base_elevation + lift
		var points := PackedVector3Array()
		for point in feature.footprint:
			points.append(Vector3(point.x, elevation, point.y))
		builder.add_filled_polygon(points, fill_purpose)
		builder.add_polygon_outline(points, purpose)
		builder.add_point(Vector3(feature.position.x, elevation + 0.12, feature.position.y), 0.9, purpose)
		_append_service_radius(builder, feature, elevation)
		if not String(feature.source_anchor_id).is_empty():
			var anchor := world.get_record(feature.source_anchor_id) as FoundationCityAnchor
			if anchor != null:
				builder.add_arrow(
					Vector3(anchor.world_position.x, elevation + 0.18, anchor.world_position.z),
					Vector3(feature.position.x, elevation + 0.18, feature.position.y),
					&"public_feature_anchor_link"
				)
		builder.add_text(
			Vector3(feature.position.x, elevation + 1.0, feature.position.y),
			"%s\n%s | cap %d | score %.2f" % [feature.stable_id, feature.feature_kind, feature.capacity, feature.suitability_score],
			purpose
		)
	_append_diagnostics(layer, builder, lift)


func _append_diagnostics(layer: FoundationSpatialLayer, builder: FoundationDebugGeometryBuilder, lift: float) -> void:
	if layer == null:
		return
	for diagnostic: Dictionary in layer.metadata.get("diagnostics", []):
		if not String(diagnostic.get("kind", "")).begins_with("public_feature"):
			continue
		var point_data: Dictionary = diagnostic.get("point", diagnostic.get("details", {}).get("point", {}))
		if point_data.is_empty():
			continue
		var point := Vector3(float(point_data.get("x", 0.0)), lift + 0.8, float(point_data.get("y", 0.0)))
		var purpose: StringName = &"public_feature_invalid" if diagnostic.get("severity", "") == String(FoundationSiteFeatureValidationIssue.SEVERITY_ERROR) else &"public_feature_warning"
		builder.add_point(point, 0.7, purpose)
		builder.add_text(point + Vector3.UP, String(diagnostic.get("kind", "public-feature diagnostic")), purpose)


func _append_service_radius(builder: FoundationDebugGeometryBuilder, feature: FoundationPublicFeatureRecord, elevation: float) -> void:
	if feature.service_radius <= 0.0:
		return
	var points := PackedVector3Array()
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		points.append(Vector3(
			feature.position.x + cos(angle) * feature.service_radius,
			elevation,
			feature.position.y + sin(angle) * feature.service_radius
		))
	builder.add_polyline(points, true, &"public_feature_service")


func _purpose(feature: FoundationPublicFeatureRecord) -> StringName:
	if feature.validation_state == FoundationPublicFeatureRecord.INVALID:
		return &"public_feature_invalid"
	match feature.authorship_state:
		FoundationSpatialRecord.AuthorshipState.LOCKED:
			return &"public_feature_locked"
		FoundationSpatialRecord.AuthorshipState.OVERRIDDEN:
			return &"public_feature_overridden"
		_:
			return StringName("public_feature_%s" % feature.feature_kind)
