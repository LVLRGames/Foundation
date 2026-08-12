class_name FoundationFacadeRecord
extends FoundationSpatialRecord

## Deterministic modular grammar projected onto one building-footprint edge.

const FACADE_FORMAT_VERSION := 1
const RECORD_KIND: StringName = &"facade"
const ENTITY_TYPE: StringName = &"facade"
const LAYER_TYPE: StringName = &"facades"

const ROLE_PRIMARY: StringName = &"primary"
const ROLE_SIDE: StringName = &"side"
const ROLE_REAR: StringName = &"rear"

const VALID: StringName = &"valid"
const WARNING: StringName = &"warning"
const INVALID: StringName = &"invalid"

var parent_parcel_id: StringName
var parent_block_id: StringName
var source_segment_index := -1
var start := Vector2.ZERO
var end := Vector2.ZERO
var outward_normal := Vector2.ZERO
var facade_role: StringName = ROLE_SIDE
var grammar_id: StringName = &"modular_facade_v1"
var base_elevation := 0.0
var facade_length := 0.0
var height := 0.0
var floor_count := 0
var floor_height := 0.0
var bay_count := 0
var bay_width := 0.0
var pattern_phase := 0
var modules: Array[FoundationFacadeModule] = []
var entrance_module_id: StringName
var glazing_ratio := 0.0
var validation_state: StringName = VALID
var validation_messages := PackedStringArray()


func _init(
	p_stable_id: StringName = &"",
	p_parent_building_id: StringName = &"",
	p_source_segment_index := -1,
	p_start := Vector2.ZERO,
	p_end := Vector2.ZERO
) -> void:
	super(p_stable_id, ENTITY_TYPE, LAYER_TYPE, _bounds_for_segment(p_start, p_end), p_parent_building_id)
	source_segment_index = p_source_segment_index
	start = p_start
	end = p_end
	refresh_metrics()


func set_segment(p_start: Vector2, p_end: Vector2) -> void:
	start = p_start
	end = p_end
	refresh_metrics()


func refresh_metrics() -> void:
	facade_length = start.distance_to(end)
	world_bounds = _bounds_for_segment(start, end)
	var direction := (end - start).normalized()
	outward_normal = Vector2(direction.y, -direction.x) if direction != Vector2.ZERO else Vector2.ZERO
	bay_width = facade_length / float(bay_count) if bay_count > 0 else 0.0
	var glazed_area := 0.0
	for module in modules:
		if module.kind == FoundationFacadeModule.KIND_WINDOW:
			glazed_area += module.area()
	glazing_ratio = glazed_area / (facade_length * height) if facade_length > 0.0 and height > 0.0 else 0.0


func get_module(module_id: StringName) -> FoundationFacadeModule:
	for module in modules:
		if module.module_id == module_id:
			return module
	return null


func to_dict() -> Dictionary:
	var data := super.to_dict()
	var serialized_modules: Array[Dictionary] = []
	for module in modules:
		serialized_modules.append(module.to_dict())
	data["record_kind"] = String(RECORD_KIND)
	data["facade_format_version"] = FACADE_FORMAT_VERSION
	data["parent_parcel_id"] = String(parent_parcel_id)
	data["parent_block_id"] = String(parent_block_id)
	data["source_segment_index"] = source_segment_index
	data["start"] = {"x": start.x, "y": start.y}
	data["end"] = {"x": end.x, "y": end.y}
	data["outward_normal"] = {"x": outward_normal.x, "y": outward_normal.y}
	data["facade_role"] = String(facade_role)
	data["grammar_id"] = String(grammar_id)
	data["base_elevation"] = base_elevation
	data["facade_length"] = facade_length
	data["height"] = height
	data["floor_count"] = floor_count
	data["floor_height"] = floor_height
	data["bay_count"] = bay_count
	data["bay_width"] = bay_width
	data["pattern_phase"] = pattern_phase
	data["modules"] = serialized_modules
	data["entrance_module_id"] = String(entrance_module_id)
	data["glazing_ratio"] = glazing_ratio
	data["validation_state"] = String(validation_state)
	data["validation_messages"] = Array(validation_messages)
	return data


static func from_dict(data: Dictionary) -> FoundationFacadeRecord:
	var start_data: Dictionary = data.get("start", {})
	var end_data: Dictionary = data.get("end", {})
	var facade := FoundationFacadeRecord.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("parent_id", "")),
		int(data.get("source_segment_index", -1)),
		Vector2(float(start_data.get("x", 0.0)), float(start_data.get("y", 0.0))),
		Vector2(float(end_data.get("x", 0.0)), float(end_data.get("y", 0.0)))
	)
	FoundationSpatialRecord.apply_serialized_fields(facade, data)
	facade.entity_type = ENTITY_TYPE
	facade.layer_type = LAYER_TYPE
	facade.parent_parcel_id = StringName(data.get("parent_parcel_id", ""))
	facade.parent_block_id = StringName(data.get("parent_block_id", ""))
	var normal_data: Dictionary = data.get("outward_normal", {})
	facade.outward_normal = Vector2(float(normal_data.get("x", facade.outward_normal.x)), float(normal_data.get("y", facade.outward_normal.y)))
	facade.facade_role = StringName(data.get("facade_role", String(ROLE_SIDE)))
	facade.grammar_id = StringName(data.get("grammar_id", "modular_facade_v1"))
	facade.base_elevation = float(data.get("base_elevation", 0.0))
	facade.facade_length = float(data.get("facade_length", facade.facade_length))
	facade.height = float(data.get("height", 0.0))
	facade.floor_count = int(data.get("floor_count", 0))
	facade.floor_height = float(data.get("floor_height", 0.0))
	facade.bay_count = int(data.get("bay_count", 0))
	facade.bay_width = float(data.get("bay_width", 0.0))
	facade.pattern_phase = int(data.get("pattern_phase", 0))
	facade.modules.clear()
	for module_data: Dictionary in data.get("modules", []):
		facade.modules.append(FoundationFacadeModule.from_dict(module_data))
	facade.entrance_module_id = StringName(data.get("entrance_module_id", ""))
	facade.glazing_ratio = float(data.get("glazing_ratio", 0.0))
	facade.validation_state = StringName(data.get("validation_state", String(VALID)))
	facade.validation_messages = PackedStringArray(data.get("validation_messages", []))
	return facade


static func _bounds_for_segment(first: Vector2, second: Vector2) -> Rect2:
	var minimum := Vector2(minf(first.x, second.x), minf(first.y, second.y))
	var maximum := Vector2(maxf(first.x, second.x), maxf(first.y, second.y))
	return Rect2(minimum, maximum - minimum).grow(0.001)
