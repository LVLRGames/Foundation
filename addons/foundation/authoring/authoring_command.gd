class_name FoundationAuthoringCommand
extends RefCounted

## Serializable before/after snapshots for one atomic authoring operation.

const FORMAT_VERSION := 1

var command_id: StringName
var sequence := 0
var action: StringName
var target_record_id: StringName
var summary := ""
var before_target_data: Dictionary = {}
var after_target_data: Dictionary = {}
var before_override_data: Dictionary = {}
var after_override_data: Dictionary = {}
var affected_layers: Array[StringName] = []


func to_dict() -> Dictionary:
	var layers: Array[String] = []
	for layer in affected_layers:
		layers.append(String(layer))
	return {
		"format_version": FORMAT_VERSION,
		"command_id": String(command_id),
		"sequence": sequence,
		"action": String(action),
		"target_record_id": String(target_record_id),
		"summary": summary,
		"before_target_data": before_target_data.duplicate(true),
		"after_target_data": after_target_data.duplicate(true),
		"before_override_data": before_override_data.duplicate(true),
		"after_override_data": after_override_data.duplicate(true),
		"affected_layers": layers,
	}


static func from_dict(data: Dictionary) -> FoundationAuthoringCommand:
	var command := FoundationAuthoringCommand.new()
	command.command_id = StringName(data.get("command_id", ""))
	command.sequence = int(data.get("sequence", 0))
	command.action = StringName(data.get("action", ""))
	command.target_record_id = StringName(data.get("target_record_id", ""))
	command.summary = String(data.get("summary", ""))
	command.before_target_data = data.get("before_target_data", {}).duplicate(true)
	command.after_target_data = data.get("after_target_data", {}).duplicate(true)
	command.before_override_data = data.get("before_override_data", {}).duplicate(true)
	command.after_override_data = data.get("after_override_data", {}).duplicate(true)
	for layer: String in data.get("affected_layers", []):
		command.affected_layers.append(StringName(layer))
	return command
