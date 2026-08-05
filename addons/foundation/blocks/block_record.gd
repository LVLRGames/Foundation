class_name FoundationBlockRecord
extends FoundationSpatialRecord

## Canonical abstract centerline-bounded city block. It owns no parcel or building data.

const BLOCK_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"block"
const ENTITY_TYPE: StringName = &"block"
const LAYER_TYPE: StringName = &"blocks"
const VALID: StringName = &"valid"
const INVALID: StringName = &"invalid"

var outer_boundary := PackedVector2Array()
var boundary_references: Array[FoundationBlockBoundaryReference] = []
var boundary_road_ids: Array[StringName] = []
var frontage_by_road: Dictionary = {}
var area := 0.0
var perimeter := 0.0
var centroid := Vector2.ZERO
var label_point := Vector2.ZERO
var validation_state: StringName = VALID
var validation_messages := PackedStringArray()


func _init(
	p_stable_id: StringName = &"",
	p_outer_boundary := PackedVector2Array(),
	p_boundary_references: Array[FoundationBlockBoundaryReference] = []
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, _bounds_for_boundary(p_outer_boundary))
	outer_boundary = p_outer_boundary.duplicate()
	boundary_references = p_boundary_references.duplicate()
	refresh_metrics()
	refresh_provenance()


func set_outer_boundary(value: PackedVector2Array) -> void:
	outer_boundary = value.duplicate()
	refresh_metrics()


func set_boundary_references(value: Array[FoundationBlockBoundaryReference]) -> void:
	boundary_references = value.duplicate()
	refresh_provenance()


func refresh_metrics() -> void:
	world_bounds = _bounds_for_boundary(outer_boundary)
	area = absf(_signed_area(outer_boundary))
	perimeter = 0.0
	for index in range(outer_boundary.size()):
		perimeter += outer_boundary[index].distance_to(outer_boundary[(index + 1) % outer_boundary.size()])
	centroid = _polygon_centroid(outer_boundary)
	label_point = _stable_interior_point(outer_boundary, centroid)


func refresh_provenance() -> void:
	boundary_references.sort_custom(FoundationBlockBoundaryReference.less)
	var road_ids: Dictionary = {}
	frontage_by_road.clear()
	for reference in boundary_references:
		road_ids[reference.road_edge_id] = true
		frontage_by_road[reference.road_edge_id] = (
			float(frontage_by_road.get(reference.road_edge_id, 0.0))
			+ reference.frontage_length
		)
	boundary_road_ids.clear()
	for road_id: StringName in road_ids:
		boundary_road_ids.append(road_id)
	boundary_road_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_boundary: Array[Dictionary] = []
	for point in outer_boundary:
		serialized_boundary.append({"x": point.x, "y": point.y})
	var serialized_references: Array[Dictionary] = []
	for reference in boundary_references:
		serialized_references.append(reference.to_dict())
	var serialized_road_ids: Array[String] = []
	var serialized_frontage: Array[Dictionary] = []
	for road_id in boundary_road_ids:
		serialized_road_ids.append(String(road_id))
		serialized_frontage.append({
			"road_edge_id": String(road_id),
			"length": float(frontage_by_road.get(road_id, 0.0)),
		})
	data["record_kind"] = String(RECORD_KIND)
	data["block_format_version"] = BLOCK_FORMAT_VERSION
	data["outer_boundary"] = serialized_boundary
	data["boundary_references"] = serialized_references
	data["boundary_road_ids"] = serialized_road_ids
	data["frontage_by_road"] = serialized_frontage
	data["area"] = area
	data["perimeter"] = perimeter
	data["centroid"] = {"x": centroid.x, "y": centroid.y}
	data["label_point"] = {"x": label_point.x, "y": label_point.y}
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationBlockRecord:
	var boundary := PackedVector2Array()
	for point_data: Dictionary in data.get("outer_boundary", []):
		boundary.append(Vector2(
			float(point_data.get("x", 0.0)),
			float(point_data.get("y", 0.0))
		))
	var references: Array[FoundationBlockBoundaryReference] = []
	for reference_data: Dictionary in data.get("boundary_references", []):
		references.append(FoundationBlockBoundaryReference.from_dict(reference_data))
	var block := FoundationBlockRecord.new(
		StringName(data.get("stable_id", "")),
		boundary,
		references
	)
	FoundationSpatialRecord.apply_serialized_fields(block, data)
	block.entity_type = ENTITY_TYPE
	block.layer_type = LAYER_TYPE
	block.area = float(data.get("area", block.area))
	block.perimeter = float(data.get("perimeter", block.perimeter))
	var centroid_data: Dictionary = data.get("centroid", {})
	block.centroid = Vector2(
		float(centroid_data.get("x", block.centroid.x)),
		float(centroid_data.get("y", block.centroid.y))
	)
	var label_data: Dictionary = data.get("label_point", {})
	block.label_point = Vector2(
		float(label_data.get("x", block.label_point.x)),
		float(label_data.get("y", block.label_point.y))
	)
	block.validation_state = StringName(data.get("validation_state", String(VALID)))
	block.validation_messages = PackedStringArray(data.get("validation_messages", []))
	block.refresh_provenance()
	return block


static func _signed_area(points: PackedVector2Array) -> float:
	var twice_area := 0.0
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		twice_area += current.x * next.y - next.x * current.y
	return twice_area * 0.5


static func _polygon_centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var twice_area := 0.0
	var weighted := Vector2.ZERO
	for index in range(points.size()):
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		var cross := current.x * next.y - next.x * current.y
		twice_area += cross
		weighted += (current + next) * cross
	if absf(twice_area) <= 0.000001:
		var average := Vector2.ZERO
		for point in points:
			average += point
		return average / float(points.size())
	return weighted / (3.0 * twice_area)


static func _stable_interior_point(points: PackedVector2Array, preferred: Vector2) -> Vector2:
	if points.size() < 3:
		return preferred
	if Geometry2D.is_point_in_polygon(preferred, points):
		return preferred
	var indices := Geometry2D.triangulate_polygon(points)
	var best := points[0]
	var best_area := -1.0
	for index in range(0, indices.size(), 3):
		var a := points[indices[index]]
		var b := points[indices[index + 1]]
		var c := points[indices[index + 2]]
		var triangle_area := absf((b - a).cross(c - a)) * 0.5
		var candidate := (a + b + c) / 3.0
		if triangle_area > best_area + 0.000001 or (
			is_equal_approx(triangle_area, best_area)
			and (candidate.x < best.x or (is_equal_approx(candidate.x, best.x) and candidate.y < best.y))
		):
			best_area = triangle_area
			best = candidate
	return best


static func _bounds_for_boundary(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)
