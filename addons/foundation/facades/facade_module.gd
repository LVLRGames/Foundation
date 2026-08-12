class_name FoundationFacadeModule
extends RefCounted

## Compact Node-free cell in a modular facade grid.

const FORMAT_VERSION := 1
const KIND_WALL: StringName = &"wall"
const KIND_WINDOW: StringName = &"window"
const KIND_ENTRANCE: StringName = &"entrance"

var module_id: StringName
var kind: StringName = KIND_WALL
var floor_index := 0
var bay_index := 0
var horizontal_start := 0.0
var horizontal_end := 0.0
var vertical_start := 0.0
var vertical_end := 0.0


func _init(
	p_module_id: StringName = &"",
	p_kind: StringName = KIND_WALL,
	p_floor_index := 0,
	p_bay_index := 0
) -> void:
	module_id = p_module_id
	kind = p_kind
	floor_index = p_floor_index
	bay_index = p_bay_index


func area() -> float:
	return maxf(0.0, horizontal_end - horizontal_start) * maxf(0.0, vertical_end - vertical_start)


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"module_id": String(module_id),
		"kind": String(kind),
		"floor_index": floor_index,
		"bay_index": bay_index,
		"horizontal_start": horizontal_start,
		"horizontal_end": horizontal_end,
		"vertical_start": vertical_start,
		"vertical_end": vertical_end,
	}


static func from_dict(data: Dictionary) -> FoundationFacadeModule:
	var module := FoundationFacadeModule.new(
		StringName(data.get("module_id", "")),
		StringName(data.get("kind", String(KIND_WALL))),
		int(data.get("floor_index", 0)),
		int(data.get("bay_index", 0))
	)
	module.horizontal_start = float(data.get("horizontal_start", 0.0))
	module.horizontal_end = float(data.get("horizontal_end", 0.0))
	module.vertical_start = float(data.get("vertical_start", 0.0))
	module.vertical_end = float(data.get("vertical_end", 0.0))
	return module
