class_name FoundationInteriorFloor
extends RefCounted

## One selectively generated floor plan nested beneath an interior record.

const FORMAT_VERSION := 1

var floor_index := 0
var elevation := 0.0
var clear_height := 0.0
var usable_components: Array[PackedVector2Array] = []
var usable_area := 0.0
var rooms: Array[FoundationInteriorRoom] = []
var portals: Array[FoundationInteriorPortal] = []
var circulation_room_id: StringName


func refresh_metrics() -> void:
	usable_area = 0.0
	for component in usable_components:
		usable_area += absf(FoundationBlockRecord._signed_area(component))
	rooms.sort_custom(FoundationInteriorRoom.less)
	portals.sort_custom(FoundationInteriorPortal.less)


func get_room(room_id: StringName) -> FoundationInteriorRoom:
	for room in rooms:
		if room.room_id == room_id:
			return room
	return null


func to_dict() -> Dictionary:
	var serialized_components: Array[Array] = []
	for component in usable_components:
		var points: Array[Dictionary] = []
		for point in component:
			points.append({"x": point.x, "y": point.y})
		serialized_components.append(points)
	var serialized_rooms: Array[Dictionary] = []
	for room in rooms:
		serialized_rooms.append(room.to_dict())
	var serialized_portals: Array[Dictionary] = []
	for portal in portals:
		serialized_portals.append(portal.to_dict())
	return {
		"format_version": FORMAT_VERSION,
		"floor_index": floor_index,
		"elevation": elevation,
		"clear_height": clear_height,
		"usable_components": serialized_components,
		"usable_area": usable_area,
		"rooms": serialized_rooms,
		"portals": serialized_portals,
		"circulation_room_id": String(circulation_room_id),
	}


static func from_dict(data: Dictionary) -> FoundationInteriorFloor:
	var floor := FoundationInteriorFloor.new()
	floor.floor_index = int(data.get("floor_index", 0))
	floor.elevation = float(data.get("elevation", 0.0))
	floor.clear_height = float(data.get("clear_height", 0.0))
	for component_data: Array in data.get("usable_components", []):
		var component := PackedVector2Array()
		for point_data: Dictionary in component_data:
			component.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
		floor.usable_components.append(component)
	for room_data: Dictionary in data.get("rooms", []):
		floor.rooms.append(FoundationInteriorRoom.from_dict(room_data))
	for portal_data: Dictionary in data.get("portals", []):
		floor.portals.append(FoundationInteriorPortal.from_dict(portal_data))
	floor.circulation_room_id = StringName(data.get("circulation_room_id", ""))
	floor.refresh_metrics()
	floor.usable_area = float(data.get("usable_area", floor.usable_area))
	return floor


static func less(a: FoundationInteriorFloor, b: FoundationInteriorFloor) -> bool:
	return a.floor_index < b.floor_index
