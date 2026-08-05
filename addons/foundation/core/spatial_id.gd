class_name FoundationSpatialId
extends RefCounted

## Stable IDs derived only from explicit deterministic context.


static func make(
	world_seed: int,
	generator_version: int,
	content_pack_version: StringName,
	entity_type: StringName,
	parent_id: StringName,
	semantic_key: String
) -> StringName:
	assert(not String(entity_type).is_empty(), "Spatial IDs require an entity type.")
	assert(not semantic_key.is_empty(), "Spatial IDs require a deterministic semantic key.")
	var payload := "%d|%d|%s|%s|%s|%s" % [
		world_seed,
		generator_version,
		String(content_pack_version),
		String(entity_type),
		String(parent_id),
		semantic_key,
	]
	var prefix := String(entity_type).to_snake_case()
	return StringName("%s_%s" % [prefix, payload.sha256_text().substr(0, 16)])


static func for_chunk(chunk: Vector2i) -> StringName:
	return StringName("chunk_%d_%d" % [chunk.x, chunk.y])


static func for_region(region: Vector2i) -> StringName:
	return StringName("region_%d_%d" % [region.x, region.y])
