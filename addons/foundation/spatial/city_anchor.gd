class_name FoundationCityAnchor
extends FoundationSpatialRecord

## Abstract point of city-planning intent. Anchors carry no connectivity or road topology.

const ANCHOR_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"city_anchor"
const ENTITY_TYPE: StringName = &"city_anchor"
const LAYER_TYPE: StringName = &"city_anchors"

const CATEGORY_CITY_CENTER: StringName = &"city_center"
const CATEGORY_CIVIC_CENTER: StringName = &"civic_center"
const CATEGORY_HIGHWAY_ENTRANCE: StringName = &"highway_entrance"
const CATEGORY_MAP_EXIT: StringName = &"map_exit"
const CATEGORY_INDUSTRIAL_CENTER: StringName = &"industrial_center"
const CATEGORY_COMMERCIAL_CENTER: StringName = &"commercial_center"
const CATEGORY_WATERFRONT_CROSSING: StringName = &"waterfront_crossing"
const CATEGORY_BRIDGE_CANDIDATE: StringName = &"bridge_candidate"
const CATEGORY_TRANSIT_NODE: StringName = &"transit_node"
const CATEGORY_LANDMARK: StringName = &"landmark"
const CATEGORY_PUBLIC_SQUARE: StringName = &"public_square"
const CATEGORY_DISTRICT_SEED: StringName = &"district_seed"
const CATEGORY_EXTERNAL_DESTINATION: StringName = &"external_destination"

var anchor_category: StringName
var world_position := Vector3.ZERO
var influence_radius := 0.0
var influence_bounds := Rect2()
var has_explicit_influence_bounds := false
var priority_weight := 1.0


func _init(
	p_stable_id: StringName = &"",
	p_anchor_category: StringName = CATEGORY_CITY_CENTER,
	p_world_position := Vector3.ZERO,
	p_influence_radius := 0.0,
	p_priority_weight := 1.0,
	p_influence_bounds: Variant = null,
	p_parent_id: StringName = &""
) -> void:
	super(
		p_stable_id,
		ENTITY_TYPE,
		LAYER_TYPE,
		_make_world_bounds(p_world_position, p_influence_radius, p_influence_bounds),
		p_parent_id
	)
	assert(not String(p_anchor_category).is_empty(), "City anchors require an extensible category.")
	assert(p_influence_radius >= 0.0, "City-anchor influence radius cannot be negative.")
	assert(p_priority_weight >= 0.0, "City-anchor priority weight cannot be negative.")
	anchor_category = p_anchor_category
	world_position = p_world_position
	influence_radius = p_influence_radius
	priority_weight = p_priority_weight
	has_explicit_influence_bounds = p_influence_bounds is Rect2
	if has_explicit_influence_bounds:
		influence_bounds = p_influence_bounds as Rect2


func has_influence() -> bool:
	return has_explicit_influence_bounds or influence_radius > 0.0


func refresh_world_bounds() -> void:
	var explicit_bounds: Variant = influence_bounds if has_explicit_influence_bounds else null
	world_bounds = _make_world_bounds(world_position, influence_radius, explicit_bounds)


func set_world_position(value: Vector3) -> void:
	world_position = value
	refresh_world_bounds()


func set_influence_radius(value: float) -> void:
	assert(value >= 0.0, "City-anchor influence radius cannot be negative.")
	influence_radius = value
	refresh_world_bounds()


func set_influence_bounds(value: Rect2) -> void:
	influence_bounds = value
	has_explicit_influence_bounds = true
	refresh_world_bounds()


func clear_influence_bounds() -> void:
	has_explicit_influence_bounds = false
	influence_bounds = Rect2()
	refresh_world_bounds()


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["record_kind"] = String(RECORD_KIND)
	data["anchor_format_version"] = ANCHOR_FORMAT_VERSION
	data["anchor_category"] = String(anchor_category)
	data["world_position"] = {
		"x": world_position.x,
		"y": world_position.y,
		"z": world_position.z,
	}
	data["influence_radius"] = influence_radius
	data["has_explicit_influence_bounds"] = has_explicit_influence_bounds
	data["influence_bounds"] = _rect_to_dict(influence_bounds)
	data["priority_weight"] = priority_weight
	return data


static func from_dict(data: Dictionary) -> FoundationCityAnchor:
	var position_data: Dictionary = data.get("world_position", {})
	var position := Vector3(
		float(position_data.get("x", 0.0)),
		float(position_data.get("y", 0.0)),
		float(position_data.get("z", 0.0))
	)
	var explicit_bounds: Variant = null
	if bool(data.get("has_explicit_influence_bounds", false)):
		explicit_bounds = _rect_from_dict(data.get("influence_bounds", {}))
	var anchor := FoundationCityAnchor.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("anchor_category", String(CATEGORY_CITY_CENTER))),
		position,
		float(data.get("influence_radius", 0.0)),
		float(data.get("priority_weight", 1.0)),
		explicit_bounds,
		StringName(data.get("parent_id", ""))
	)
	FoundationSpatialRecord.apply_serialized_fields(anchor, data)
	anchor.entity_type = ENTITY_TYPE
	anchor.layer_type = LAYER_TYPE
	return anchor


static func create(
	world_metadata: FoundationWorldMetadata,
	category: StringName,
	position: Vector3,
	semantic_key: String,
	radius := 0.0,
	weight := 1.0,
	explicit_bounds: Variant = null,
	parent_id: StringName = &""
) -> FoundationCityAnchor:
	var stable_id := FoundationSpatialId.make(
		world_metadata.seed,
		world_metadata.generator_version,
		world_metadata.content_pack_version,
		ENTITY_TYPE,
		parent_id,
		"%s|%s" % [category, semantic_key]
	)
	return FoundationCityAnchor.new(
		stable_id,
		category,
		position,
		radius,
		weight,
		explicit_bounds,
		parent_id
	)


static func get_builtin_categories() -> Array[StringName]:
	return [
		CATEGORY_CITY_CENTER,
		CATEGORY_CIVIC_CENTER,
		CATEGORY_HIGHWAY_ENTRANCE,
		CATEGORY_MAP_EXIT,
		CATEGORY_INDUSTRIAL_CENTER,
		CATEGORY_COMMERCIAL_CENTER,
		CATEGORY_WATERFRONT_CROSSING,
		CATEGORY_BRIDGE_CANDIDATE,
		CATEGORY_TRANSIT_NODE,
		CATEGORY_LANDMARK,
		CATEGORY_PUBLIC_SQUARE,
		CATEGORY_DISTRICT_SEED,
		CATEGORY_EXTERNAL_DESTINATION,
	]


static func _make_world_bounds(
	position: Vector3,
	radius: float,
	explicit_bounds: Variant
) -> Rect2:
	if explicit_bounds is Rect2:
		return explicit_bounds as Rect2
	if radius > 0.0:
		return Rect2(
			Vector2(position.x - radius, position.z - radius),
			Vector2(radius * 2.0, radius * 2.0)
		)
	return Rect2(Vector2(position.x, position.z), Vector2.ZERO)
