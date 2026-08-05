class_name FoundationSeed
extends RefCounted

## Named deterministic seed derivation for independent Foundation subsystems.

const GENERATOR_VERSION := 1
const _FNV_OFFSET_BASIS := 2166136261
const _FNV_PRIME := 16777619


static func derive(world_seed: int, stream_name: StringName) -> int:
	var bytes := (str(world_seed) + ":" + String(stream_name)).to_utf8_buffer()
	var hash_value: int = _FNV_OFFSET_BASIS
	for byte in bytes:
		hash_value = ((hash_value ^ int(byte)) * _FNV_PRIME) & 0xffffffff

	# Final avalanche keeps nearby world seeds from producing nearby FastNoise seeds.
	hash_value = (hash_value ^ (hash_value >> 16)) & 0xffffffff
	hash_value = (hash_value * 0x7feb352d) & 0xffffffff
	hash_value = (hash_value ^ (hash_value >> 15)) & 0xffffffff
	return hash_value & 0x7fffffff
