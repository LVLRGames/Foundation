class_name FoundationSpatialRecord
extends RefCounted

## Lightweight shared contract for future spatial entities.

const FORMAT_VERSION := 1

enum AuthorshipState {
	GENERATED,
	LOCKED,
	OVERRIDDEN,
}

var stable_id: StringName
var entity_type: StringName
var layer_type: StringName
var world_bounds: Rect2
var owning_chunks: Array[Vector2i] = []
var owning_regions: Array[Vector2i] = []
var parent_id: StringName
var child_ids: Array[StringName] = []
var tags := PackedStringArray()
var authorship_state := AuthorshipState.GENERATED
var source_pass: StringName
var source_version := 1
var metadata: Dictionary = {}


func _init(
	p_stable_id: StringName = &"",
	p_entity_type: StringName = &"record",
	p_layer_type: StringName = &"feature",
	p_world_bounds := Rect2(),
	p_parent_id: StringName = &""
) -> void:
	stable_id = p_stable_id
	entity_type = p_entity_type
	layer_type = p_layer_type
	world_bounds = p_world_bounds
	parent_id = p_parent_id


func intersects(bounds: Rect2) -> bool:
	return world_bounds.intersects(bounds, true)


func set_owning_chunks(chunks: Array[Vector2i]) -> void:
	owning_chunks = chunks.duplicate()
	owning_chunks.sort_custom(_sort_vector2i)


func set_owning_regions(regions: Array[Vector2i]) -> void:
	owning_regions = regions.duplicate()
	owning_regions.sort_custom(_sort_vector2i)


func add_child(child_id: StringName) -> void:
	if child_id not in child_ids:
		child_ids.append(child_id)
		child_ids.sort_custom(func(a: StringName, b: StringName) -> bool:
			return String(a) < String(b)
		)


func to_dict() -> Dictionary:
	var serialized_chunks: Array[Dictionary] = []
	for chunk in owning_chunks:
		serialized_chunks.append({"x": chunk.x, "y": chunk.y})
	var serialized_children: Array[String] = []
	for child_id in child_ids:
		serialized_children.append(String(child_id))
	var serialized_regions: Array[Dictionary] = []
	for region in owning_regions:
		serialized_regions.append({"x": region.x, "y": region.y})
	return {
		"format_version": FORMAT_VERSION,
		"record_kind": "spatial_record",
		"stable_id": String(stable_id),
		"entity_type": String(entity_type),
		"layer_type": String(layer_type),
		"world_bounds": _rect_to_dict(world_bounds),
		"owning_chunks": serialized_chunks,
		"owning_regions": serialized_regions,
		"parent_id": String(parent_id),
		"child_ids": serialized_children,
		"tags": Array(tags),
		"authorship_state": authorship_state,
		"source_pass": String(source_pass),
		"source_version": source_version,
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> FoundationSpatialRecord:
	var record := FoundationSpatialRecord.new(
		StringName(data.get("stable_id", "")),
		StringName(data.get("entity_type", "record")),
		StringName(data.get("layer_type", "feature")),
		_rect_from_dict(data.get("world_bounds", {})),
		StringName(data.get("parent_id", ""))
	)
	apply_serialized_fields(record, data)
	return record


static func apply_serialized_fields(record: FoundationSpatialRecord, data: Dictionary) -> void:
	record.stable_id = StringName(data.get("stable_id", ""))
	record.entity_type = StringName(data.get("entity_type", "record"))
	record.layer_type = StringName(data.get("layer_type", "feature"))
	record.world_bounds = _rect_from_dict(data.get("world_bounds", {}))
	record.parent_id = StringName(data.get("parent_id", ""))
	var chunks: Array[Vector2i] = []
	for chunk_data: Dictionary in data.get("owning_chunks", []):
		chunks.append(Vector2i(int(chunk_data.get("x", 0)), int(chunk_data.get("y", 0))))
	record.set_owning_chunks(chunks)
	var regions: Array[Vector2i] = []
	for region_data: Dictionary in data.get("owning_regions", []):
		regions.append(Vector2i(int(region_data.get("x", 0)), int(region_data.get("y", 0))))
	record.set_owning_regions(regions)
	record.child_ids.clear()
	for child_id: String in data.get("child_ids", []):
		record.child_ids.append(StringName(child_id))
	record.tags = PackedStringArray(data.get("tags", []))
	record.authorship_state = int(data.get("authorship_state", AuthorshipState.GENERATED)) as AuthorshipState
	record.source_pass = StringName(data.get("source_pass", ""))
	record.source_version = int(data.get("source_version", 1))
	record.metadata = data.get("metadata", {}).duplicate(true)


static func _rect_to_dict(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}


static func _rect_from_dict(data: Dictionary) -> Rect2:
	return Rect2(
		float(data.get("x", 0.0)),
		float(data.get("y", 0.0)),
		float(data.get("width", 0.0)),
		float(data.get("height", 0.0))
	)


static func _sort_vector2i(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
