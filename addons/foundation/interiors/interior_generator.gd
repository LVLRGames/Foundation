class_name FoundationInteriorGenerator
extends RefCounted

## Bounded deterministic generation for explicitly selected buildings and floors.

const SOURCE_PASS: StringName = &"phase_12_selective_interiors"


static func generate(
	world: FoundationWorldData,
	request: FoundationInteriorGenerationRequest,
	profile: FoundationInteriorGenerationProfile = null
) -> FoundationInteriorGenerationResult:
	var result := FoundationInteriorGenerationResult.new()
	if world == null or request == null:
		return result.fail("Interior generation requires world data and an explicit selection request.")
	var active_profile := profile if profile != null else FoundationInteriorGenerationProfile.new()
	var errors := active_profile.validation_errors()
	errors.append_array(request.validation_errors(active_profile))
	if not errors.is_empty():
		return result.fail("Invalid interior generation input: %s" % "; ".join(errors))
	world.register_layer_type(FoundationWorldData.INTERIOR_LAYER)
	var selected_ids := request.normalized_building_ids()
	if selected_ids.is_empty():
		result.add_diagnostic(&"empty_selection", FoundationInteriorValidationIssue.SEVERITY_INFO, {
			"message": "No buildings were explicitly selected; no interiors were generated.",
		})
		result.success = true
		_set_layer_metadata(world, request, active_profile, result)
		return result
	result.preserved_interior_count = _remove_replaceable_for_buildings(world, selected_ids)
	for building_id in selected_ids:
		_generate_for_building(world, building_id, request, active_profile, result)
		if result.generation_operation_count > active_profile.maximum_generation_operations:
			clear_generated(world, selected_ids)
			return result.fail("Interior generation exceeded its configured operation cap.")
	var issues := FoundationInteriorValidator.validate(world, active_profile, true)
	for issue in issues:
		result.diagnostics.append(issue.to_dict())
	result.diagnostics.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JSON.stringify(a) < JSON.stringify(b)
	)
	result.success = true
	_set_layer_metadata(world, request, active_profile, result)
	return result


static func clear_generated(
	world: FoundationWorldData,
	building_ids: Array[StringName] = []
) -> int:
	var selected: Dictionary = {}
	for building_id in building_ids:
		selected[building_id] = true
	var removed := 0
	for interior in world.get_interiors():
		if interior.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
			continue
		if not selected.is_empty() and not selected.has(interior.parent_id):
			continue
		world.unregister_record(interior.stable_id)
		removed += 1
	return removed


static func _remove_replaceable_for_buildings(
	world: FoundationWorldData,
	building_ids: Array[StringName]
) -> int:
	var selected: Dictionary = {}
	for building_id in building_ids:
		selected[building_id] = true
	var preserved := 0
	var retained: Array[FoundationInteriorRecord] = []
	for interior in world.get_interiors():
		if not selected.has(interior.parent_id):
			continue
		if interior.authorship_state == FoundationSpatialRecord.AuthorshipState.GENERATED:
			world.unregister_record(interior.stable_id)
		else:
			retained.append(interior)
			preserved += 1
	for interior in retained:
		world.register_record(interior)
	return preserved


static func _generate_for_building(
	world: FoundationWorldData,
	building_id: StringName,
	request: FoundationInteriorGenerationRequest,
	profile: FoundationInteriorGenerationProfile,
	result: FoundationInteriorGenerationResult
) -> void:
	var building := world.get_record(building_id) as FoundationBuildingRecord
	if building == null:
		_skip(result, building_id, &"missing_selected_building", "Selected building does not exist.", Vector2.ZERO)
		return
	if building.validation_state == FoundationBuildingRecord.INVALID or building.footprint.size() < 3:
		_skip(result, building_id, &"invalid_selected_building", "Selected building is not geometrically valid.", building.label_point)
		return
	if building.floor_count <= 0 or building.floor_height <= profile.geometric_epsilon:
		_skip(result, building_id, &"invalid_floor_massing", "Selected building has no usable floor massing.", building.label_point)
		return
	var authored := world.get_interior_for_building(building_id)
	if authored != null and authored.authorship_state != FoundationSpatialRecord.AuthorshipState.GENERATED:
		return
	var floor_indices := request.floor_indices_for(building_id, building.floor_count)
	var valid_indices: Array[int] = []
	for floor_index in floor_indices:
		if floor_index < 0 or floor_index >= building.floor_count:
			result.add_diagnostic(&"selected_floor_out_of_range", FoundationInteriorValidationIssue.SEVERITY_WARNING, {
				"parent_building_id": String(building_id), "floor_index": floor_index,
				"point": _point_dict(building.label_point),
			})
			continue
		if floor_index >= profile.maximum_floors_per_building:
			result.add_diagnostic(&"selected_floor_exceeds_cap", FoundationInteriorValidationIssue.SEVERITY_WARNING, {
				"parent_building_id": String(building_id), "floor_index": floor_index,
				"point": _point_dict(building.label_point),
			})
			continue
		valid_indices.append(floor_index)
	if valid_indices.is_empty():
		_skip(result, building_id, &"no_valid_selected_floors", "No selected floors pass the building/profile limits.", building.label_point)
		return
	var expected_id := _interior_id(world, building_id, profile)
	var preserved := world.get_record(expected_id) as FoundationInteriorRecord
	if preserved != null and preserved.parent_id == building_id:
		return
	var stable_id := expected_id
	if world.get_record(stable_id) != null:
		stable_id = _repair_interior_id(world, building_id, profile)
	var interior := FoundationInteriorRecord.new(stable_id, building_id, building.footprint)
	interior.parent_parcel_id = building.parent_id
	interior.parent_block_id = building.parent_block_id
	interior.source_floor_count = building.floor_count
	interior.source_floor_height = building.floor_height
	interior.source_base_elevation = building.base_elevation
	interior.source_building_fingerprint = FoundationSpatialRecordCodec.fingerprint(building.to_dict())
	var district := world.get_district_for_building(building_id)
	if district != null:
		interior.district_id = district.stable_id
	interior.primary_use = _building_use(world, building, district)
	var usable_components := _usable_components(building.footprint, profile, result)
	if usable_components.is_empty():
		_skip(result, building_id, &"interior_inset_exhausted", "Exterior-wall inset leaves no usable interior floor area.", building.label_point)
		return
	for floor_index in valid_indices:
		var floor := _create_floor(world, interior, building, floor_index, usable_components, profile, result)
		if floor == null or floor.rooms.is_empty():
			result.add_diagnostic(&"floor_layout_exhausted", FoundationInteriorValidationIssue.SEVERITY_WARNING, {
				"parent_building_id": String(building_id), "floor_index": floor_index,
				"point": _point_dict(building.label_point),
			})
			continue
		interior.floors.append(floor)
	if interior.floors.is_empty():
		_skip(result, building_id, &"interior_layout_exhausted", "No selected floor produced a valid interior layout.", building.label_point)
		return
	_add_vertical_connectors(world, interior, profile, result)
	interior.refresh_metrics()
	interior.source_pass = SOURCE_PASS
	interior.source_version = profile.generator_version
	interior.tags = PackedStringArray(["phase_12", "selective_interior", String(interior.primary_use)])
	interior.metadata = {
		"request_id": String(request.request_id),
		"selected_floor_indices": _floor_indices(interior),
		"selection_mode": "all_floors" if request.include_all_floors else "explicit",
	}
	interior.set_owning_chunks(world.coordinate_system.world_bounds_to_chunks(interior.world_bounds))
	var region_set: Dictionary = {}
	for chunk_coordinate in interior.owning_chunks:
		region_set[world.coordinate_system.chunk_to_region(chunk_coordinate)] = true
	var owning_regions: Array[Vector2i] = []
	for region_coordinate: Vector2i in region_set:
		owning_regions.append(region_coordinate)
	interior.set_owning_regions(owning_regions)
	world.register_record(interior)
	result.generated_interior_count += 1
	result.generated_floor_count += interior.floors.size()
	result.generated_room_count += interior.room_count
	result.generated_portal_count += interior.portal_count
	result.generated_vertical_connector_count += interior.vertical_connectors.size()


static func _create_floor(
	world: FoundationWorldData,
	interior: FoundationInteriorRecord,
	building: FoundationBuildingRecord,
	floor_index: int,
	usable_components: Array[PackedVector2Array],
	profile: FoundationInteriorGenerationProfile,
	result: FoundationInteriorGenerationResult
) -> FoundationInteriorFloor:
	var floor := FoundationInteriorFloor.new()
	floor.floor_index = floor_index
	floor.elevation = building.base_elevation + float(floor_index) * building.floor_height
	floor.clear_height = building.floor_height
	for component in usable_components:
		floor.usable_components.append(component.duplicate())
	var tangent := Vector2.from_angle(deg_to_rad(building.orientation_degrees)).normalized()
	if tangent == Vector2.ZERO:
		tangent = Vector2.RIGHT
	var inward := Vector2(-tangent.y, tangent.x)
	var limits := _projection_limits(usable_components, tangent, inward)
	var seed := FoundationSeed.derive(world.metadata.seed, StringName("%s:%s:%d" % [
		profile.STREAM_GRID_VARIATION, building.stable_id, floor_index,
	]))
	var span_factor := 0.90 + float(seed % 2001) / 10000.0
	var depth_factor := 0.90 + float((seed / 2001) % 2001) / 10000.0
	var columns := maxi(1, ceili(float(limits["span"]) / (profile.preferred_room_span * span_factor)))
	var rows := maxi(1, ceili(float(limits["depth"]) / (profile.preferred_room_depth * depth_factor)))
	while columns * rows > profile.maximum_rooms_per_floor:
		if columns >= rows and columns > 1:
			columns -= 1
		elif rows > 1:
			rows -= 1
		else:
			break
	var candidates: Array[PackedVector2Array] = []
	for row_index in range(rows):
		var v0 := lerpf(float(limits["min_v"]), float(limits["max_v"]), float(row_index) / float(rows))
		var v1 := lerpf(float(limits["min_v"]), float(limits["max_v"]), float(row_index + 1) / float(rows))
		for column_index in range(columns):
			var u0 := lerpf(float(limits["min_u"]), float(limits["max_u"]), float(column_index) / float(columns))
			var u1 := lerpf(float(limits["min_u"]), float(limits["max_u"]), float(column_index + 1) / float(columns))
			var cell := PackedVector2Array([
				tangent * u0 + inward * v0, tangent * u1 + inward * v0,
				tangent * u1 + inward * v1, tangent * u0 + inward * v1,
			])
			for component in usable_components:
				result.generation_operation_count += 1
				for raw in Geometry2D.intersect_polygons(component, cell):
					candidates.append_array(_split_repeated_vertex_components(raw, profile))
	candidates.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		return boundary_key(a, profile) < boundary_key(b, profile)
	)
	if candidates.size() > profile.maximum_rooms_per_floor:
		return null
	for boundary in candidates:
		var area := absf(FoundationBlockRecord._signed_area(boundary))
		var room_id := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			&"interior_room", interior.stable_id, "%d:%s" % [floor_index, boundary_key(boundary, profile)]
		)
		var kind := FoundationInteriorRoom.KIND_SERVICE if area < profile.service_room_area_threshold else FoundationInteriorRoom.KIND_STANDARD
		floor.rooms.append(FoundationInteriorRoom.new(room_id, floor_index, boundary, kind))
	if floor.rooms.is_empty():
		return null
	var usable_centroid := _components_centroid(usable_components)
	var circulation := floor.rooms[0]
	var best_distance := INF
	for room in floor.rooms:
		var penalty := 1000000.0 if room.room_kind == FoundationInteriorRoom.KIND_SERVICE else 0.0
		var distance := room.label_point.distance_squared_to(usable_centroid) + penalty
		if distance < best_distance:
			best_distance = distance
			circulation = room
	circulation.room_kind = FoundationInteriorRoom.KIND_CIRCULATION
	floor.circulation_room_id = circulation.room_id
	_add_interior_portals(world, interior, floor, profile, result)
	if floor_index == 0:
		_add_exterior_portal(world, building, floor, profile, result)
	floor.refresh_metrics()
	return floor


static func _add_interior_portals(
	world: FoundationWorldData,
	interior: FoundationInteriorRecord,
	floor: FoundationInteriorFloor,
	profile: FoundationInteriorGenerationProfile,
	result: FoundationInteriorGenerationResult
) -> void:
	for first_index in range(floor.rooms.size()):
		for second_index in range(first_index + 1, floor.rooms.size()):
			result.generation_operation_count += 1
			if floor.portals.size() >= profile.maximum_portals_per_floor:
				return
			var first := floor.rooms[first_index]
			var second := floor.rooms[second_index]
			# Clipping points are quantized for stable identity. Use that same scale when
			# recovering shared walls so rotated grids do not lose valid adjacency.
			var overlap := _shared_boundary_overlap(first.boundary, second.boundary, maxf(profile.geometric_epsilon, profile.point_quantization * 2.0))
			var length := float(overlap.get("length", 0.0))
			var required_shared := profile.minimum_shared_boundary
			if first.room_kind == FoundationInteriorRoom.KIND_SERVICE or second.room_kind == FoundationInteriorRoom.KIND_SERVICE:
				required_shared = profile.portal_end_margin * 2.0 + profile.geometric_epsilon
			if length < required_shared:
				continue
			var width := minf(profile.interior_door_width, length - profile.portal_end_margin * 2.0)
			if width <= profile.geometric_epsilon:
				continue
			var overlap_start: Vector2 = overlap["start"]
			var overlap_end: Vector2 = overlap["end"]
			var direction := (overlap_end - overlap_start).normalized()
			var center := (overlap_start + overlap_end) * 0.5
			var portal_id := FoundationSpatialId.make(
				world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
				&"interior_portal", interior.stable_id,
				"%d:%s:%s" % [floor.floor_index, first.room_id, second.room_id]
			)
			var portal := FoundationInteriorPortal.new(
				portal_id, floor.floor_index, first.room_id, second.room_id,
				center - direction * width * 0.5, center + direction * width * 0.5
			)
			portal.provenance = &"service_fragment_access" if width < profile.interior_door_width else &"shared_room_boundary"
			floor.portals.append(portal)


static func _add_exterior_portal(
	world: FoundationWorldData,
	building: FoundationBuildingRecord,
	floor: FoundationInteriorFloor,
	profile: FoundationInteriorGenerationProfile,
	result: FoundationInteriorGenerationResult
) -> void:
	var context := _entrance_context(world, building)
	var entrance_point: Vector2 = context["point"]
	var room := floor.rooms[0]
	var best_distance := INF
	for candidate in floor.rooms:
		var distance := candidate.label_point.distance_squared_to(entrance_point)
		if distance < best_distance:
			best_distance = distance
			room = candidate
	var direction: Vector2 = context["direction"]
	var width := profile.exterior_door_width
	var portal_id := FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		&"interior_portal", floor.circulation_room_id,
		"exterior:%s:%s" % [context["facade_id"], context["module_id"]]
	)
	var portal := FoundationInteriorPortal.new(
		portal_id, floor.floor_index, room.room_id, &"",
		entrance_point - direction * width * 0.5,
		entrance_point + direction * width * 0.5,
		FoundationInteriorPortal.KIND_EXTERIOR
	)
	portal.source_facade_id = context["facade_id"]
	portal.source_module_id = context["module_id"]
	portal.provenance = context["provenance"]
	floor.portals.append(portal)
	result.generation_operation_count += 1


static func _entrance_context(world: FoundationWorldData, building: FoundationBuildingRecord) -> Dictionary:
	var primary: FoundationFacadeRecord
	for facade in world.get_facades():
		if facade.parent_id == building.stable_id and facade.facade_role == FoundationFacadeRecord.ROLE_PRIMARY:
			primary = facade
			break
	if primary != null:
		var direction := (primary.end - primary.start).normalized()
		var entrance := primary.get_module(primary.entrance_module_id)
		if entrance != null:
			var offset := (entrance.horizontal_start + entrance.horizontal_end) * 0.5
			return {
				"point": primary.start + direction * offset,
				"direction": direction,
				"facade_id": primary.stable_id,
				"module_id": entrance.module_id,
				"provenance": &"primary_facade_entrance_module",
			}
		return {
			"point": (primary.start + primary.end) * 0.5,
			"direction": direction,
			"facade_id": primary.stable_id,
			"module_id": &"",
			"provenance": &"primary_facade_midpoint",
		}
	var first := building.footprint[0]
	var second := building.footprint[1]
	return {
		"point": (first + second) * 0.5,
		"direction": (second - first).normalized(),
		"facade_id": &"",
		"module_id": &"",
		"provenance": &"building_edge_fallback",
	}


static func _add_vertical_connectors(
	world: FoundationWorldData,
	interior: FoundationInteriorRecord,
	profile: FoundationInteriorGenerationProfile,
	result: FoundationInteriorGenerationResult
) -> void:
	interior.floors.sort_custom(FoundationInteriorFloor.less)
	for index in range(interior.floors.size() - 1):
		if interior.vertical_connectors.size() >= profile.maximum_vertical_connectors:
			return
		var lower := interior.floors[index]
		var upper := interior.floors[index + 1]
		if upper.floor_index != lower.floor_index + 1:
			continue
		var lower_room := lower.get_room(lower.circulation_room_id)
		var upper_room := upper.get_room(upper.circulation_room_id)
		if lower_room == null or upper_room == null:
			continue
		var connector := FoundationInteriorVerticalConnector.new()
		connector.connector_id = FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			&"interior_vertical_connector", interior.stable_id,
			"%d:%d" % [lower.floor_index, upper.floor_index]
		)
		connector.lower_floor_index = lower.floor_index
		connector.upper_floor_index = upper.floor_index
		connector.lower_room_id = lower_room.room_id
		connector.upper_room_id = upper_room.room_id
		connector.center = (lower_room.label_point + upper_room.label_point) * 0.5
		var half := profile.connector_size * 0.5
		connector.footprint = PackedVector2Array([
			connector.center - half,
			connector.center + Vector2(half.x, -half.y),
			connector.center + half,
			connector.center + Vector2(-half.x, half.y),
		])
		interior.vertical_connectors.append(connector)
		result.generation_operation_count += 1


static func _usable_components(
	boundary: PackedVector2Array,
	profile: FoundationInteriorGenerationProfile,
	result: FoundationInteriorGenerationResult
) -> Array[PackedVector2Array]:
	result.generation_operation_count += 1
	var raw_components: Array[PackedVector2Array]
	if profile.exterior_wall_inset <= profile.geometric_epsilon:
		raw_components = [boundary]
	else:
		raw_components = Geometry2D.offset_polygon(boundary, -profile.exterior_wall_inset)
	var components: Array[PackedVector2Array] = []
	for raw in raw_components:
		components.append_array(_split_repeated_vertex_components(raw, profile))
	components.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		return boundary_key(a, profile) < boundary_key(b, profile)
	)
	return components


static func _projection_limits(
	components: Array[PackedVector2Array],
	tangent: Vector2,
	inward: Vector2
) -> Dictionary:
	var min_u := INF
	var max_u := -INF
	var min_v := INF
	var max_v := -INF
	for component in components:
		for point in component:
			var u := point.dot(tangent)
			var v := point.dot(inward)
			min_u = minf(min_u, u)
			max_u = maxf(max_u, u)
			min_v = minf(min_v, v)
			max_v = maxf(max_v, v)
	return {"min_u": min_u, "max_u": max_u, "min_v": min_v, "max_v": max_v, "span": max_u - min_u, "depth": max_v - min_v}


static func _components_centroid(components: Array[PackedVector2Array]) -> Vector2:
	var weighted := Vector2.ZERO
	var total_area := 0.0
	for component in components:
		var area := absf(FoundationBlockRecord._signed_area(component))
		weighted += FoundationBlockRecord._polygon_centroid(component) * area
		total_area += area
	return weighted / total_area if total_area > 0.000001 else Vector2.ZERO


static func _shared_boundary_overlap(
	first: PackedVector2Array,
	second: PackedVector2Array,
	epsilon: float
) -> Dictionary:
	var best := {"length": 0.0, "start": Vector2.ZERO, "end": Vector2.ZERO}
	for first_index in range(first.size()):
		var a := first[first_index]
		var b := first[(first_index + 1) % first.size()]
		for second_index in range(second.size()):
			var c := second[second_index]
			var d := second[(second_index + 1) % second.size()]
			var overlap := _collinear_overlap_segment(a, b, c, d, epsilon)
			if float(overlap["length"]) > float(best["length"]):
				best = overlap
	return best


static func _collinear_overlap_segment(
	a: Vector2, b: Vector2, c: Vector2, d: Vector2, epsilon: float
) -> Dictionary:
	var source := b - a
	var length := source.length()
	if length <= epsilon:
		return {"length": 0.0, "start": Vector2.ZERO, "end": Vector2.ZERO}
	var direction := source / length
	if absf(direction.cross(d - c)) > epsilon * maxf(1.0, (d - c).length()):
		return {"length": 0.0, "start": Vector2.ZERO, "end": Vector2.ZERO}
	if absf(direction.cross(c - a)) > epsilon:
		return {"length": 0.0, "start": Vector2.ZERO, "end": Vector2.ZERO}
	var first_t := (c - a).dot(direction)
	var second_t := (d - a).dot(direction)
	var start_t := maxf(0.0, minf(first_t, second_t))
	var end_t := minf(length, maxf(first_t, second_t))
	if end_t - start_t <= epsilon:
		return {"length": 0.0, "start": Vector2.ZERO, "end": Vector2.ZERO}
	return {"length": end_t - start_t, "start": a + direction * start_t, "end": a + direction * end_t}


static func canonicalize_boundary(
	points: PackedVector2Array,
	profile: FoundationInteriorGenerationProfile
) -> PackedVector2Array:
	var normalized := PackedVector2Array()
	for point in points:
		var quantized := Vector2(
			round(point.x / profile.point_quantization) * profile.point_quantization,
			round(point.y / profile.point_quantization) * profile.point_quantization
		)
		if normalized.is_empty() or normalized[normalized.size() - 1].distance_to(quantized) > profile.geometric_epsilon:
			normalized.append(quantized)
	if normalized.size() > 1 and normalized[0].distance_to(normalized[normalized.size() - 1]) <= profile.geometric_epsilon:
		normalized.remove_at(normalized.size() - 1)
	var changed := true
	while changed and normalized.size() >= 3:
		changed = false
		for index in range(normalized.size()):
			var previous := normalized[(index - 1 + normalized.size()) % normalized.size()]
			var current := normalized[index]
			var next := normalized[(index + 1) % normalized.size()]
			if absf((current - previous).cross(next - current)) <= profile.geometric_epsilon and (current - previous).dot(next - current) >= 0.0:
				normalized.remove_at(index)
				changed = true
				break
	if normalized.size() < 3:
		return PackedVector2Array()
	if FoundationBlockRecord._signed_area(normalized) < 0.0:
		normalized.reverse()
	var first_index := 0
	for index in range(1, normalized.size()):
		if normalized[index].x < normalized[first_index].x or (
			is_equal_approx(normalized[index].x, normalized[first_index].x)
			and normalized[index].y < normalized[first_index].y
		):
			first_index = index
	var canonical := PackedVector2Array()
	for offset in range(normalized.size()):
		canonical.append(normalized[(first_index + offset) % normalized.size()])
	return canonical


static func _split_repeated_vertex_components(
	boundary: PackedVector2Array,
	profile: FoundationInteriorGenerationProfile
) -> Array[PackedVector2Array]:
	var canonical := canonicalize_boundary(boundary, profile)
	var components: Array[PackedVector2Array] = []
	if canonical.size() < 3 or absf(FoundationBlockRecord._signed_area(canonical)) <= profile.geometric_epsilon:
		return components
	for first_index in range(canonical.size()):
		for second_index in range(first_index + 2, canonical.size()):
			if first_index == 0 and second_index == canonical.size() - 1:
				continue
			if canonical[first_index].distance_to(canonical[second_index]) > profile.geometric_epsilon:
				continue
			var first_loop := PackedVector2Array()
			for index in range(first_index, second_index):
				first_loop.append(canonical[index])
			var second_loop := PackedVector2Array()
			for index in range(second_index, canonical.size()):
				second_loop.append(canonical[index])
			for index in range(first_index):
				second_loop.append(canonical[index])
			components.append_array(_split_repeated_vertex_components(first_loop, profile))
			components.append_array(_split_repeated_vertex_components(second_loop, profile))
			return components
	components.append(canonical)
	return components


static func boundary_key(
	boundary: PackedVector2Array,
	profile: FoundationInteriorGenerationProfile
) -> String:
	var parts := PackedStringArray()
	for point in boundary:
		parts.append("%d,%d" % [
			roundi(point.x / profile.point_quantization),
			roundi(point.y / profile.point_quantization),
		])
	return ";".join(parts)


static func _building_use(
	world: FoundationWorldData,
	building: FoundationBuildingRecord,
	district: FoundationDistrictRecord
) -> StringName:
	if district == null:
		return &"unspecified"
	var assignment := district.get_assignment(building.parent_block_id)
	if assignment == null:
		return district.primary_use
	if assignment.building_use_overrides.has(String(building.stable_id)):
		return StringName(assignment.building_use_overrides[String(building.stable_id)])
	if assignment.parcel_use_overrides.has(String(building.parent_id)):
		return StringName(assignment.parcel_use_overrides[String(building.parent_id)])
	return assignment.primary_use if not String(assignment.primary_use).is_empty() else district.primary_use


static func _skip(
	result: FoundationInteriorGenerationResult,
	building_id: StringName,
	kind: StringName,
	message: String,
	point: Vector2
) -> void:
	result.skipped_building_count += 1
	result.add_diagnostic(kind, FoundationInteriorValidationIssue.SEVERITY_WARNING, {
		"parent_building_id": String(building_id), "message": message, "point": _point_dict(point),
	})


static func _floor_indices(interior: FoundationInteriorRecord) -> Array[int]:
	var result: Array[int] = []
	for floor in interior.floors:
		result.append(floor.floor_index)
	return result


static func _interior_id(
	world: FoundationWorldData,
	building_id: StringName,
	profile: FoundationInteriorGenerationProfile
) -> StringName:
	return FoundationSpatialId.make(
		world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
		FoundationInteriorRecord.ENTITY_TYPE, building_id, "selective_interior"
	)


static func _repair_interior_id(
	world: FoundationWorldData,
	building_id: StringName,
	profile: FoundationInteriorGenerationProfile
) -> StringName:
	var ordinal := 1
	while true:
		var candidate := FoundationSpatialId.make(
			world.metadata.seed, profile.generator_version, world.metadata.content_pack_version,
			FoundationInteriorRecord.ENTITY_TYPE, building_id,
			"selective_interior|repair:%d" % ordinal
		)
		if world.get_record(candidate) == null:
			return candidate
		ordinal += 1
	return &""


static func _set_layer_metadata(
	world: FoundationWorldData,
	request: FoundationInteriorGenerationRequest,
	profile: FoundationInteriorGenerationProfile,
	result: FoundationInteriorGenerationResult
) -> void:
	world.get_layer(FoundationWorldData.INTERIOR_LAYER).metadata = {
		"format_version": 1,
		"source_pass": String(SOURCE_PASS),
		"generator_version": profile.generator_version,
		"request": request.to_dict(),
		"profile": profile.to_dict(),
		"diagnostics": result.diagnostics.duplicate(true),
		"counts": result.to_dict(),
	}


static func _point_dict(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}
