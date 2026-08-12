class_name FoundationInteriorDebugProvider
extends FoundationDebugProvider

## Disposable floor-plan, portal, connector, lineage, and validation debug view.


func _init() -> void:
	super(&"interiors")


func append_debug(world: FoundationWorldData, builder: FoundationDebugGeometryBuilder, context: Dictionary) -> void:
	invocation_count += 1
	var selected := StringName(context.get("selected_record_id", ""))
	var requested_floor := int(context.get("interior_floor_index", 0))
	for interior in world.get_interiors():
		var floor := interior.get_floor(requested_floor)
		if floor == null and not interior.floors.is_empty():
			floor = interior.floors[0]
		if floor == null:
			continue
		var lift := floor.elevation + 0.82
		for room in floor.rooms:
			var purpose: StringName = &"interior_room_service" if room.room_kind == FoundationInteriorRoom.KIND_SERVICE else &"interior_room"
			if room.room_kind == FoundationInteriorRoom.KIND_CIRCULATION:
				purpose = &"interior_room_circulation"
			if interior.stable_id == selected:
				purpose = &"selected"
			var points := PackedVector3Array()
			for point in room.boundary:
				points.append(Vector3(point.x, lift, point.y))
			builder.add_filled_polygon(points, purpose)
			builder.add_polygon_outline(points, purpose)
		for portal in floor.portals:
			var purpose: StringName = &"interior_entrance" if portal.portal_kind == FoundationInteriorPortal.KIND_EXTERIOR else &"interior_portal"
			builder.add_line(Vector3(portal.start.x, lift + 0.08, portal.start.y), Vector3(portal.end.x, lift + 0.08, portal.end.y), purpose)
		for connector in interior.vertical_connectors:
			if connector.lower_floor_index == floor.floor_index or connector.upper_floor_index == floor.floor_index:
				builder.add_point(Vector3(connector.center.x, lift + 0.16, connector.center.y), 0.55, &"interior_connector")
		builder.add_text(Vector3(interior.source_footprint[0].x, lift + 0.7, interior.source_footprint[0].y), "%s\nfloor %d | %d rooms | %d portals" % [interior.stable_id, floor.floor_index, floor.rooms.size(), floor.portals.size()], &"interior_invalid" if interior.validation_state == FoundationInteriorRecord.INVALID else &"label")
