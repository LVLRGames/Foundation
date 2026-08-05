class_name FoundationWorldMetadata
extends RefCounted

## Versioned reproducibility and bounds metadata, free of Node references.

const FORMAT_VERSION := 1

var seed := 0
var generator_version := FoundationSeed.GENERATOR_VERSION
var content_pack_version: StringName = &"phase-1"
var world_bounds := Rect2(-256.0, -256.0, 512.0, 512.0)
var generation_metadata: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"seed": seed,
		"generator_version": generator_version,
		"content_pack_version": String(content_pack_version),
		"world_bounds": FoundationSpatialRecord._rect_to_dict(world_bounds),
		"generation_metadata": generation_metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> FoundationWorldMetadata:
	var metadata := FoundationWorldMetadata.new()
	metadata.seed = int(data.get("seed", 0))
	metadata.generator_version = int(data.get("generator_version", FoundationSeed.GENERATOR_VERSION))
	metadata.content_pack_version = StringName(data.get("content_pack_version", "phase-1"))
	metadata.world_bounds = FoundationSpatialRecord._rect_from_dict(data.get("world_bounds", {}))
	metadata.generation_metadata = data.get("generation_metadata", {}).duplicate(true)
	return metadata
