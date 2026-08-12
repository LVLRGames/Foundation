class_name FoundationDistrictRecord
extends FoundationSpatialRecord

## Node-free district membership, character, and land-use policy data.

const DISTRICT_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"district"
const ENTITY_TYPE: StringName = &"district"
const LAYER_TYPE: StringName = &"districts"

const CHARACTER_DOWNTOWN: StringName = &"downtown_core"
const CHARACTER_MIXED_USE: StringName = &"mixed_use_center"
const CHARACTER_RESIDENTIAL: StringName = &"residential_neighborhood"
const CHARACTER_INDUSTRIAL: StringName = &"industrial_employment"
const CHARACTER_CIVIC: StringName = &"civic_institutional"
const CHARACTER_SUBURBAN: StringName = &"suburban_neighborhood"
const CHARACTER_RURAL: StringName = &"rural_edge"

const USE_RESIDENTIAL: StringName = &"residential"
const USE_COMMERCIAL: StringName = &"commercial"
const USE_MIXED: StringName = &"mixed_use"
const USE_INDUSTRIAL: StringName = &"industrial"
const USE_CIVIC: StringName = &"civic"
const USE_INSTITUTIONAL: StringName = &"institutional"
const USE_OPEN_SPACE: StringName = &"open_space"
const USE_AGRICULTURAL: StringName = &"agricultural"
const USE_UNDEVELOPED: StringName = &"undeveloped"

const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var member_block_ids: Array[StringName] = []
var boundary_components: Array[PackedVector2Array] = []
var allows_disconnected_components := false
var total_area := 0.0
var centroid := Vector2.ZERO
var label_point := Vector2.ZERO
var character_key: StringName = CHARACTER_RESIDENTIAL
var primary_use: StringName = USE_RESIDENTIAL
var allowed_uses: Array[StringName] = []
var source_anchor_id: StringName
var source_pattern_ids: Array[StringName] = []
var style_policy_key: StringName = &"default_district_style"
var content_policy_key: StringName = &"default_district_content"
var target_density := 0.0
var minimum_height := 0.0
var maximum_height := 0.0
var target_intensity := 0.0
var open_space_target := 0.0
var mixed_use_ratio := 0.0
var road_class_exposure: Dictionary = {}
var access_score := 0.0
var assignments: Array[FoundationDistrictMemberAssignment] = []
var validation_state: StringName = VALID
var validation_messages := PackedStringArray()


func _init(
	p_stable_id: StringName = &"",
	p_member_block_ids: Array[StringName] = [],
	p_boundary_components: Array[PackedVector2Array] = []
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE)
	member_block_ids = p_member_block_ids.duplicate()
	boundary_components = _duplicate_components(p_boundary_components)
	refresh_metrics()


func refresh_metrics() -> void:
	member_block_ids.sort_custom(_string_name_less)
	boundary_components.sort_custom(_component_less)
	world_bounds = _bounds_for_components(boundary_components)
	total_area = 0.0
	var weighted_centroid := Vector2.ZERO
	for component in boundary_components:
		var component_area := absf(FoundationBlockRecord._signed_area(component))
		total_area += component_area
		weighted_centroid += FoundationBlockRecord._polygon_centroid(component) * component_area
	centroid = weighted_centroid / total_area if total_area > 0.000001 else world_bounds.get_center()
	label_point = centroid
	if not boundary_components.is_empty():
		var containing_component := -1
		for index in range(boundary_components.size()):
			if Geometry2D.is_point_in_polygon(centroid, boundary_components[index]):
				containing_component = index
				break
		var label_component := boundary_components[containing_component] if containing_component >= 0 else _largest_component(boundary_components)
		label_point = FoundationBlockRecord._stable_interior_point(label_component, centroid)
	assignments.sort_custom(FoundationDistrictMemberAssignment.less)
	allowed_uses.sort_custom(_string_name_less)
	source_pattern_ids.sort_custom(_string_name_less)


func get_assignment(block_id: StringName) -> FoundationDistrictMemberAssignment:
	for assignment in assignments:
		if assignment.block_id == block_id:
			return assignment
	return null


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_blocks: Array[String] = []
	for block_id in member_block_ids:
		serialized_blocks.append(String(block_id))
	var serialized_components: Array[Array] = []
	for component in boundary_components:
		var points: Array[Dictionary] = []
		for point in component:
			points.append({"x": point.x, "y": point.y})
		serialized_components.append(points)
	var serialized_uses: Array[String] = []
	for use_key in allowed_uses:
		serialized_uses.append(String(use_key))
	var serialized_patterns: Array[String] = []
	for pattern_id in source_pattern_ids:
		serialized_patterns.append(String(pattern_id))
	var serialized_assignments: Array[Dictionary] = []
	for assignment in assignments:
		serialized_assignments.append(assignment.to_dict())
	data["record_kind"] = String(RECORD_KIND)
	data["district_format_version"] = DISTRICT_FORMAT_VERSION
	data["member_block_ids"] = serialized_blocks
	data["boundary_components"] = serialized_components
	data["allows_disconnected_components"] = allows_disconnected_components
	data["total_area"] = total_area
	data["centroid"] = {"x": centroid.x, "y": centroid.y}
	data["label_point"] = {"x": label_point.x, "y": label_point.y}
	data["character_key"] = String(character_key)
	data["primary_use"] = String(primary_use)
	data["allowed_uses"] = serialized_uses
	data["source_anchor_id"] = String(source_anchor_id)
	data["source_pattern_ids"] = serialized_patterns
	data["style_policy_key"] = String(style_policy_key)
	data["content_policy_key"] = String(content_policy_key)
	data["target_density"] = target_density
	data["minimum_height"] = minimum_height
	data["maximum_height"] = maximum_height
	data["target_intensity"] = target_intensity
	data["open_space_target"] = open_space_target
	data["mixed_use_ratio"] = mixed_use_ratio
	data["road_class_exposure"] = road_class_exposure.duplicate(true)
	data["access_score"] = access_score
	data["assignments"] = serialized_assignments
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationDistrictRecord:
	var block_ids: Array[StringName] = []
	for block_value: String in data.get("member_block_ids", []):
		block_ids.append(StringName(block_value))
	var components: Array[PackedVector2Array] = []
	for component_data: Array in data.get("boundary_components", []):
		var component := PackedVector2Array()
		for point_data: Dictionary in component_data:
			component.append(Vector2(float(point_data.get("x", 0.0)), float(point_data.get("y", 0.0))))
		components.append(component)
	var district := FoundationDistrictRecord.new(StringName(data.get("stable_id", "")), block_ids, components)
	FoundationSpatialRecord.apply_serialized_fields(district, data)
	district.entity_type = ENTITY_TYPE
	district.layer_type = LAYER_TYPE
	district.character_key = StringName(data.get("character_key", String(CHARACTER_RESIDENTIAL)))
	district.allows_disconnected_components = bool(data.get("allows_disconnected_components", false))
	district.primary_use = StringName(data.get("primary_use", String(USE_RESIDENTIAL)))
	district.allowed_uses.clear()
	for use_value: String in data.get("allowed_uses", []):
		district.allowed_uses.append(StringName(use_value))
	district.source_anchor_id = StringName(data.get("source_anchor_id", ""))
	district.source_pattern_ids.clear()
	for pattern_value: String in data.get("source_pattern_ids", []):
		district.source_pattern_ids.append(StringName(pattern_value))
	district.style_policy_key = StringName(data.get("style_policy_key", "default_district_style"))
	district.content_policy_key = StringName(data.get("content_policy_key", "default_district_content"))
	district.target_density = float(data.get("target_density", 0.0))
	district.minimum_height = float(data.get("minimum_height", 0.0))
	district.maximum_height = float(data.get("maximum_height", 0.0))
	district.target_intensity = float(data.get("target_intensity", 0.0))
	district.open_space_target = float(data.get("open_space_target", 0.0))
	district.mixed_use_ratio = float(data.get("mixed_use_ratio", 0.0))
	district.road_class_exposure = data.get("road_class_exposure", {}).duplicate(true)
	district.access_score = float(data.get("access_score", 0.0))
	district.assignments.clear()
	for assignment_data: Dictionary in data.get("assignments", []):
		district.assignments.append(FoundationDistrictMemberAssignment.from_dict(assignment_data))
	district.validation_state = StringName(data.get("validation_state", String(VALID)))
	district.validation_messages = PackedStringArray(data.get("validation_messages", []))
	district.refresh_metrics()
	return district


static func builtin_characters() -> Array[StringName]:
	return [CHARACTER_DOWNTOWN, CHARACTER_MIXED_USE, CHARACTER_RESIDENTIAL, CHARACTER_INDUSTRIAL, CHARACTER_CIVIC, CHARACTER_SUBURBAN, CHARACTER_RURAL]


static func builtin_uses() -> Array[StringName]:
	return [USE_RESIDENTIAL, USE_COMMERCIAL, USE_MIXED, USE_INDUSTRIAL, USE_CIVIC, USE_INSTITUTIONAL, USE_OPEN_SPACE, USE_AGRICULTURAL, USE_UNDEVELOPED]


static func _duplicate_components(values: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for value in values:
		result.append(value.duplicate())
	return result


static func _bounds_for_components(components: Array[PackedVector2Array]) -> Rect2:
	var initialized := false
	var result := Rect2()
	for component in components:
		if component.is_empty():
			continue
		var bounds := FoundationBlockRecord._bounds_for_boundary(component)
		if not initialized:
			result = bounds
			initialized = true
		else:
			result = result.merge(bounds)
	return result


static func _largest_component(components: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := components[0]
	var best_area := absf(FoundationBlockRecord._signed_area(best))
	for index in range(1, components.size()):
		var area := absf(FoundationBlockRecord._signed_area(components[index]))
		if area > best_area + 0.000001 or (is_equal_approx(area, best_area) and _component_less(components[index], best)):
			best = components[index]
			best_area = area
	return best


static func _component_less(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var a_bounds := FoundationBlockRecord._bounds_for_boundary(a)
	var b_bounds := FoundationBlockRecord._bounds_for_boundary(b)
	if not is_equal_approx(a_bounds.position.y, b_bounds.position.y):
		return a_bounds.position.y < b_bounds.position.y
	if not is_equal_approx(a_bounds.position.x, b_bounds.position.x):
		return a_bounds.position.x < b_bounds.position.x
	return JSON.stringify(Array(a)) < JSON.stringify(Array(b))


static func _string_name_less(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
