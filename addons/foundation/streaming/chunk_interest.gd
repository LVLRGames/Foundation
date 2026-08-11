class_name FoundationChunkInterest
extends RefCounted

## Node-free runtime interest source used by the deterministic streaming planner.

const FORMAT_VERSION := 1

var stable_id: StringName
var world_position := Vector3.ZERO
var priority_weight := 1.0
var enabled := true


func _init(
	p_stable_id: StringName = &"interest",
	p_world_position := Vector3.ZERO,
	p_priority_weight := 1.0
) -> void:
	stable_id = p_stable_id
	world_position = p_world_position
	priority_weight = maxf(0.0, p_priority_weight)


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"stable_id": String(stable_id),
		"world_position": {"x": world_position.x, "y": world_position.y, "z": world_position.z},
		"priority_weight": priority_weight,
		"enabled": enabled,
	}


static func from_dict(data: Dictionary) -> FoundationChunkInterest:
	var position_data: Dictionary = data.get("world_position", {})
	var interest := FoundationChunkInterest.new(
		StringName(data.get("stable_id", "interest")),
		Vector3(
			float(position_data.get("x", 0.0)),
			float(position_data.get("y", 0.0)),
			float(position_data.get("z", 0.0))
		),
		float(data.get("priority_weight", 1.0))
	)
	interest.enabled = bool(data.get("enabled", true))
	return interest
