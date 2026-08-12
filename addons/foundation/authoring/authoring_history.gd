class_name FoundationAuthoringHistory
extends RefCounted

## Bounded deterministic cursor history. It does not mutate a world by itself.

const FORMAT_VERSION := 1

var maximum_commands := 128
var cursor := 0
var next_sequence := 1
var commands: Array[FoundationAuthoringCommand] = []


func _init(p_maximum_commands := 128) -> void:
	maximum_commands = maxi(1, p_maximum_commands)


func push(command: FoundationAuthoringCommand) -> void:
	while commands.size() > cursor:
		commands.pop_back()
	command.sequence = next_sequence
	command.command_id = StringName("authoring_command_%06d" % next_sequence)
	next_sequence += 1
	commands.append(command)
	cursor = commands.size()
	while commands.size() > maximum_commands:
		commands.pop_front()
		cursor -= 1


func can_undo() -> bool:
	return cursor > 0


func can_redo() -> bool:
	return cursor < commands.size()


func peek_undo() -> FoundationAuthoringCommand:
	return commands[cursor - 1] if can_undo() else null


func peek_redo() -> FoundationAuthoringCommand:
	return commands[cursor] if can_redo() else null


func mark_undone() -> void:
	if can_undo():
		cursor -= 1


func mark_redone() -> void:
	if can_redo():
		cursor += 1


func to_dict() -> Dictionary:
	var serialized: Array[Dictionary] = []
	for command in commands:
		serialized.append(command.to_dict())
	return {
		"format_version": FORMAT_VERSION,
		"maximum_commands": maximum_commands,
		"cursor": cursor,
		"next_sequence": next_sequence,
		"commands": serialized,
	}


static func from_dict(data: Dictionary) -> FoundationAuthoringHistory:
	var history := FoundationAuthoringHistory.new(int(data.get("maximum_commands", 128)))
	history.commands.clear()
	var minimum_next_sequence := 1
	for command_data: Dictionary in data.get("commands", []):
		var command := FoundationAuthoringCommand.from_dict(command_data)
		history.commands.append(command)
		minimum_next_sequence = maxi(minimum_next_sequence, command.sequence + 1)
	history.cursor = clampi(int(data.get("cursor", history.commands.size())), 0, history.commands.size())
	history.next_sequence = maxi(int(data.get("next_sequence", minimum_next_sequence)), minimum_next_sequence)
	return history
