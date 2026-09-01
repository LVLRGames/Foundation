class_name FoundationInteriorValidator
extends RefCounted

## Deterministic, read-only validation of selective interior geometry and topology.


static func validate(
	world: FoundationWorldData,
	profile: FoundationInteriorGenerationProfile = null,
	apply_state := false
) -> Array[FoundationInteriorValidationIssue]:
	var issues: Array[FoundationInteriorValidationIssue] = []
	if world == null:
		issues.append(FoundationInteriorValidationIssue.new(
			&"missing_world", FoundationInteriorValidationIssue.SEVERITY_ERROR, &"", &"",
			"Interior validation requires FoundationWorldData."
		))
		return issues
	var active := profile if profile != null else FoundationInteriorGenerationProfile.new()
	for interior in world.get_interiors():
		var start := issues.size()
		_validate_interior(world, interior, active, issues)
		if apply_state:
			_apply_state(interior, issues.slice(start))
	issues.sort_custom(FoundationInteriorValidationIssue.less)
	return issues


static func _validate_interior(
	world: FoundationWorldData,
	interior: FoundationInteriorRecord,
	profile: FoundationInteriorGenerationProfile,
	issues: Array[FoundationInteriorValidationIssue]
) -> void:
	var building := world.get_record(interior.parent_id) as FoundationBuildingRecord
	if building == null:
		_add(issues, &"missing_parent_building", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Interior parent building does not exist.")
		return
	if interior.parent_parcel_id != building.parent_id or interior.parent_block_id != building.parent_block_id:
		_add(issues, &"lineage_mismatch", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Interior parcel/block lineage does not match its building.")
	if interior.source_floor_count != building.floor_count or absf(interior.source_floor_height - building.floor_height) > profile.geometric_epsilon:
		_add(issues, &"massing_drift", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Interior floor massing does not match its source building.")
	if interior.source_building_fingerprint != FoundationSpatialRecordCodec.fingerprint(building.to_dict()):
		_add(issues, &"building_source_drift", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Source building changed after interior generation.")
	if interior.floors.is_empty() or interior.floors.size() > profile.maximum_floors_per_building:
		_add(issues, &"invalid_floor_count", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Interior has no floors or exceeds its configured floor cap.")
	var floor_indices: Dictionary = {}
	var room_total := 0
	var portal_total := 0
	for floor in interior.floors:
		if floor_indices.has(floor.floor_index) or floor.floor_index < 0 or floor.floor_index >= building.floor_count:
			_add(issues, &"invalid_floor_index", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Interior floor indices must be unique and within source massing.", {"floor_index": floor.floor_index})
		floor_indices[floor.floor_index] = true
		_validate_floor(interior, floor, profile, issues)
		room_total += floor.rooms.size()
		portal_total += floor.portals.size()
	_validate_connectors(interior, floor_indices, profile, issues)
	if room_total != interior.room_count or portal_total != interior.portal_count:
		_add(issues, &"interior_accounting_mismatch", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Stored room or portal counts do not match nested data.")
	var expected_chunks := world.coordinate_system.world_bounds_to_chunks(interior.world_bounds)
	if expected_chunks != interior.owning_chunks:
		_add(issues, &"chunk_ownership_mismatch", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Interior chunk ownership does not match its building footprint.")


static func _validate_floor(
	interior: FoundationInteriorRecord,
	floor: FoundationInteriorFloor,
	profile: FoundationInteriorGenerationProfile,
	issues: Array[FoundationInteriorValidationIssue]
) -> void:
	if floor.rooms.is_empty() or floor.rooms.size() > profile.maximum_rooms_per_floor:
		_add(issues, &"invalid_room_count", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Floor has no rooms or exceeds its room cap.", {"floor_index": floor.floor_index})
	var derived_usable := 0.0
	for component in floor.usable_components:
		derived_usable += absf(FoundationBlockRecord._signed_area(component))
		for point in component:
			if not _inside(point, interior.source_footprint, profile.geometric_epsilon):
				_add(issues, &"usable_area_outside_building", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Usable floor geometry lies outside the building footprint.", {"floor_index": floor.floor_index})
				break
	if absf(derived_usable - floor.usable_area) > profile.geometric_epsilon:
		_add(issues, &"usable_area_mismatch", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Stored usable area does not match floor geometry.", {"floor_index": floor.floor_index})
	var ids: Dictionary = {}
	var room_area := 0.0
	for room in floor.rooms:
		if String(room.room_id).is_empty() or ids.has(room.room_id):
			_add(issues, &"duplicate_room_id", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Room identities must be non-empty and unique.", {"floor_index": floor.floor_index})
		ids[room.room_id] = true
		if room.floor_index != floor.floor_index or room.boundary.size() < 3 or room.area <= profile.geometric_epsilon:
			_add(issues, &"invalid_room_geometry", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Room floor identity or geometry is invalid.", {"room_id": String(room.room_id)})
		for point in room.boundary:
			if not _inside_components(point, floor.usable_components, profile.geometric_epsilon):
				_add(issues, &"room_outside_usable_area", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Room lies outside usable floor geometry.", {"room_id": String(room.room_id)})
				break
		room_area += room.area
	if absf(room_area - floor.usable_area) > maxf(profile.geometric_epsilon, floor.usable_area * 0.001):
		_add(issues, &"room_coverage_mismatch", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Rooms do not completely cover the usable floor area.", {"floor_index": floor.floor_index})
	if not ids.has(floor.circulation_room_id):
		_add(issues, &"missing_circulation_room", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Floor circulation room is missing.", {"floor_index": floor.floor_index})
	_validate_portals(interior, floor, ids, profile, issues)


static func _validate_portals(
	interior: FoundationInteriorRecord,
	floor: FoundationInteriorFloor,
	room_ids: Dictionary,
	profile: FoundationInteriorGenerationProfile,
	issues: Array[FoundationInteriorValidationIssue]
) -> void:
	if floor.portals.size() > profile.maximum_portals_per_floor:
		_add(issues, &"portal_cap_exceeded", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Floor exceeds its portal cap.", {"floor_index": floor.floor_index})
	var portal_ids: Dictionary = {}
	var exterior_count := 0
	var adjacency: Dictionary = {}
	for room_id in room_ids:
		adjacency[room_id] = []
	for portal in floor.portals:
		if String(portal.portal_id).is_empty() or portal_ids.has(portal.portal_id):
			_add(issues, &"duplicate_portal_id", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Portal identities must be non-empty and unique.", {"floor_index": floor.floor_index})
		portal_ids[portal.portal_id] = true
		if portal.floor_index != floor.floor_index or not room_ids.has(portal.room_a_id) or portal.width <= profile.geometric_epsilon:
			_add(issues, &"invalid_portal", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Portal floor, room endpoint, or width is invalid.", {"portal_id": String(portal.portal_id)})
		if portal.portal_kind == FoundationInteriorPortal.KIND_EXTERIOR:
			exterior_count += 1
			if floor.floor_index != 0 or not String(portal.room_b_id).is_empty():
				_add(issues, &"invalid_exterior_portal", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Exterior entrances are ground-floor one-sided portals.", {"portal_id": String(portal.portal_id)})
		elif portal.portal_kind == FoundationInteriorPortal.KIND_INTERIOR:
			if not room_ids.has(portal.room_b_id) or portal.room_a_id == portal.room_b_id:
				_add(issues, &"invalid_interior_portal", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Interior portal endpoints must reference two different rooms.", {"portal_id": String(portal.portal_id)})
			else:
				adjacency[portal.room_a_id].append(portal.room_b_id)
				adjacency[portal.room_b_id].append(portal.room_a_id)
		else:
			_add(issues, &"unsupported_portal_kind", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Portal kind is unsupported.", {"portal_id": String(portal.portal_id)})
	if (floor.floor_index == 0 and exterior_count != 1) or (floor.floor_index != 0 and exterior_count != 0):
		_add(issues, &"exterior_portal_count", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Only the generated ground floor must contain exactly one exterior entrance.", {"floor_index": floor.floor_index, "count": exterior_count})
	var start := floor.circulation_room_id
	if floor.floor_index == 0:
		for portal in floor.portals:
			if portal.portal_kind == FoundationInteriorPortal.KIND_EXTERIOR:
				start = portal.room_a_id
				break
	var reached: Dictionary = {}
	var pending: Array[StringName] = [start]
	while not pending.is_empty():
		var current := pending.pop_front()
		if reached.has(current):
			continue
		reached[current] = true
		for neighbor: StringName in adjacency.get(current, []):
			if not reached.has(neighbor):
				pending.append(neighbor)
	if reached.size() != room_ids.size():
		_add(issues, &"disconnected_room_graph", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Every room must be reachable through portals.", {"floor_index": floor.floor_index})


static func _validate_connectors(
	interior: FoundationInteriorRecord,
	floor_indices: Dictionary,
	profile: FoundationInteriorGenerationProfile,
	issues: Array[FoundationInteriorValidationIssue]
) -> void:
	if interior.vertical_connectors.size() > profile.maximum_vertical_connectors:
		_add(issues, &"connector_cap_exceeded", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Interior exceeds its vertical-connector cap.")
	var ids: Dictionary = {}
	for connector in interior.vertical_connectors:
		var lower := interior.get_floor(connector.lower_floor_index)
		var upper := interior.get_floor(connector.upper_floor_index)
		if String(connector.connector_id).is_empty() or ids.has(connector.connector_id):
			_add(issues, &"duplicate_connector_id", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Vertical connector identities must be non-empty and unique.")
		ids[connector.connector_id] = true
		if lower == null or upper == null or connector.upper_floor_index != connector.lower_floor_index + 1:
			_add(issues, &"invalid_vertical_connector", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Vertical connectors must join consecutive generated floors.")
		elif lower.get_room(connector.lower_room_id) == null or upper.get_room(connector.upper_room_id) == null:
			_add(issues, &"connector_room_missing", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Vertical connector room endpoints do not exist.")
	var sorted_indices: Array = floor_indices.keys()
	sorted_indices.sort()
	var required := 0
	for index in range(1, sorted_indices.size()):
		if int(sorted_indices[index]) == int(sorted_indices[index - 1]) + 1:
			required += 1
	if interior.vertical_connectors.size() != required:
		_add(issues, &"vertical_connectivity_mismatch", FoundationInteriorValidationIssue.SEVERITY_ERROR, interior, "Every consecutive selected floor pair must have one connector.")


static func _inside(point: Vector2, polygon: PackedVector2Array, epsilon: float) -> bool:
	if Geometry2D.is_point_in_polygon(point, polygon):
		return true
	for index in range(polygon.size()):
		if Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()]).distance_to(point) <= epsilon:
			return true
	return false


static func _inside_components(point: Vector2, components: Array[PackedVector2Array], epsilon: float) -> bool:
	for component in components:
		if _inside(point, component, epsilon):
			return true
	return false


static func _apply_state(interior: FoundationInteriorRecord, interior_issues: Array) -> void:
	interior.validation_state = FoundationInteriorRecord.VALID
	interior.validation_messages.clear()
	for issue: FoundationInteriorValidationIssue in interior_issues:
		interior.validation_messages.append(issue.message)
		if issue.severity == FoundationInteriorValidationIssue.SEVERITY_ERROR:
			interior.validation_state = FoundationInteriorRecord.INVALID
		elif interior.validation_state == FoundationInteriorRecord.VALID:
			interior.validation_state = FoundationInteriorRecord.WARNING


static func _add(
	issues: Array[FoundationInteriorValidationIssue], kind: StringName, severity: StringName,
	interior: FoundationInteriorRecord, message: String, details: Dictionary = {}
) -> void:
	issues.append(FoundationInteriorValidationIssue.new(kind, severity, interior.stable_id, interior.parent_id, message, details))
