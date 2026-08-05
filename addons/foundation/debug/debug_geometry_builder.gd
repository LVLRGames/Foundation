class_name FoundationDebugGeometryBuilder
extends RefCounted

## Lightweight primitive buffer. Lines and fills become two batched meshes.

var line_vertices := PackedVector3Array()
var line_purposes: Array[StringName] = []
var triangle_vertices := PackedVector3Array()
var triangle_purposes: Array[StringName] = []
var labels: Array[Dictionary] = []


func add_line(from: Vector3, to: Vector3, purpose: StringName = &"default") -> void:
	line_vertices.append(from)
	line_vertices.append(to)
	line_purposes.append(purpose)
	line_purposes.append(purpose)


func add_polyline(
	points: PackedVector3Array,
	closed := false,
	purpose: StringName = &"default"
) -> void:
	if points.size() < 2:
		return
	for index in range(points.size() - 1):
		add_line(points[index], points[index + 1], purpose)
	if closed:
		add_line(points[points.size() - 1], points[0], purpose)


func add_polygon_outline(points: PackedVector3Array, purpose: StringName = &"default") -> void:
	add_polyline(points, true, purpose)


func add_filled_polygon(points: PackedVector3Array, purpose: StringName = &"default") -> void:
	if points.size() < 3:
		return
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(Vector2(point.x, point.z))
	var indices := Geometry2D.triangulate_polygon(polygon)
	for index in range(0, indices.size(), 3):
		_add_triangle(
			points[indices[index]],
			points[indices[index + 1]],
			points[indices[index + 2]],
			purpose
		)


func add_rect(bounds: Rect2, elevation := 0.05, purpose: StringName = &"default") -> void:
	var points := PackedVector3Array([
		Vector3(bounds.position.x, elevation, bounds.position.y),
		Vector3(bounds.end.x, elevation, bounds.position.y),
		Vector3(bounds.end.x, elevation, bounds.end.y),
		Vector3(bounds.position.x, elevation, bounds.end.y),
	])
	add_polyline(points, true, purpose)


func add_filled_rect(bounds: Rect2, elevation := 0.01, purpose: StringName = &"default") -> void:
	var northwest := Vector3(bounds.position.x, elevation, bounds.position.y)
	var northeast := Vector3(bounds.end.x, elevation, bounds.position.y)
	var southwest := Vector3(bounds.position.x, elevation, bounds.end.y)
	var southeast := Vector3(bounds.end.x, elevation, bounds.end.y)
	_add_triangle(northwest, southwest, southeast, purpose)
	_add_triangle(northwest, southeast, northeast, purpose)


func add_box(bounds: AABB, purpose: StringName = &"default") -> void:
	var minimum := bounds.position
	var maximum := bounds.end
	var corners := PackedVector3Array([
		minimum,
		Vector3(maximum.x, minimum.y, minimum.z),
		Vector3(maximum.x, minimum.y, maximum.z),
		Vector3(minimum.x, minimum.y, maximum.z),
		Vector3(minimum.x, maximum.y, minimum.z),
		Vector3(maximum.x, maximum.y, minimum.z),
		maximum,
		Vector3(minimum.x, maximum.y, maximum.z),
	])
	for edge in [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]:
		add_line(corners[edge.x], corners[edge.y], purpose)


func add_point(position: Vector3, size := 1.0, purpose: StringName = &"default") -> void:
	add_line(position - Vector3.RIGHT * size, position + Vector3.RIGHT * size, purpose)
	add_line(position - Vector3.FORWARD * size, position + Vector3.FORWARD * size, purpose)
	add_line(position - Vector3.UP * size, position + Vector3.UP * size, purpose)


func add_arrow(from: Vector3, to: Vector3, purpose: StringName = &"relationship") -> void:
	add_line(from, to, purpose)
	var direction := (to - from).normalized()
	var side := direction.cross(Vector3.UP).normalized()
	if side == Vector3.ZERO:
		side = Vector3.RIGHT
	var head_length := minf(4.0, from.distance_to(to) * 0.2)
	add_line(to, to - direction * head_length + side * head_length * 0.4, purpose)
	add_line(to, to - direction * head_length - side * head_length * 0.4, purpose)


func add_text(position: Vector3, text: String, purpose: StringName = &"label") -> void:
	labels.append({"position": position, "text": text, "purpose": purpose})


func add_heatmap_cell(bounds: Rect2, purpose: StringName) -> void:
	add_filled_rect(bounds, 0.02, purpose)


func get_primitive_count() -> int:
	return line_vertices.size() / 2 + triangle_vertices.size() / 3 + labels.size()


func _add_triangle(a: Vector3, b: Vector3, c: Vector3, purpose: StringName) -> void:
	triangle_vertices.append(a)
	triangle_vertices.append(b)
	triangle_vertices.append(c)
	triangle_purposes.append(purpose)
	triangle_purposes.append(purpose)
	triangle_purposes.append(purpose)
