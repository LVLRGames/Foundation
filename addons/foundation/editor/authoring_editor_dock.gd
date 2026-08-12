@tool
class_name FoundationAuthoringEditorDock
extends ScrollContainer

## Phase 11 typed JSON authoring controls over FoundationAuthoringSession.

var _editor_interface: EditorInterface
var _content: VBoxContainer
var _world: FoundationWorld
var _view: FoundationDebugView
var _status: Label
var _follow_selection: CheckBox
var _record_options: OptionButton
var _snapshot_editor: CodeEdit
var _translate_x: SpinBox
var _translate_z: SpinBox
var _session := FoundationAuthoringSession.new()


func initialize(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	if is_node_ready():
		_connect_selection()


func _ready() -> void:
	name = "Foundation Authoring"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
	_build_interface()
	_connect_selection()
	_editor_selection_changed()


func shutdown() -> void:
	if _editor_interface == null:
		return
	var selection := _editor_interface.get_selection()
	if selection.selection_changed.is_connected(_editor_selection_changed):
		selection.selection_changed.disconnect(_editor_selection_changed)


func _build_interface() -> void:
	var heading := Label.new()
	heading.text = "Foundation Phase 11 Authoring"
	heading.add_theme_font_size_override("font_size", 18)
	_content.add_child(heading)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)
	_follow_selection = CheckBox.new()
	_follow_selection.text = "Follow editor selection"
	_follow_selection.button_pressed = true
	_content.add_child(_follow_selection)
	var refresh := Button.new()
	refresh.text = "Refresh Authorable Records"
	refresh.pressed.connect(_populate_records)
	_content.add_child(refresh)
	_record_options = OptionButton.new()
	_record_options.item_selected.connect(_record_selected)
	_content.add_child(_record_options)
	_snapshot_editor = CodeEdit.new()
	_snapshot_editor.custom_minimum_size = Vector2(360.0, 320.0)
	_snapshot_editor.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_content.add_child(_snapshot_editor)
	_add_button("Lock Selected", _lock_selected)
	_add_button("Unlock Selected", _unlock_selected)
	_add_button("Apply / Update Override from JSON", _apply_override)
	_add_button("Create Authored Record from JSON", _create_authored)
	_add_button("Delete Selected with Tombstone", _delete_selected)
	_add_button("Revert Selected Override", _revert_selected)
	var translate_row := HBoxContainer.new()
	_translate_x = SpinBox.new()
	_translate_x.prefix = "X "
	_translate_x.min_value = -100000.0
	_translate_x.max_value = 100000.0
	_translate_x.step = 0.25
	translate_row.add_child(_translate_x)
	_translate_z = SpinBox.new()
	_translate_z.prefix = "Z "
	_translate_z.min_value = -100000.0
	_translate_z.max_value = 100000.0
	_translate_z.step = 0.25
	translate_row.add_child(_translate_z)
	var translate := Button.new()
	translate.text = "Translate Selected"
	translate.pressed.connect(_translate_selected)
	translate_row.add_child(translate)
	_content.add_child(translate_row)
	_add_button("Undo Authoring Operation", _undo)
	_add_button("Redo Authoring Operation", _redo)
	_add_button("Reapply Active Overrides", _reapply)
	_add_button("Validate Overrides + History", _validate)


func _add_button(text: String, callable: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callable)
	_content.add_child(button)


func _connect_selection() -> void:
	if _editor_interface == null:
		return
	var selection := _editor_interface.get_selection()
	if not selection.selection_changed.is_connected(_editor_selection_changed):
		selection.selection_changed.connect(_editor_selection_changed)


func _editor_selection_changed() -> void:
	if _editor_interface == null or (_follow_selection != null and not _follow_selection.button_pressed):
		return
	_world = null
	_view = null
	for node in _editor_interface.get_selection().get_selected_nodes():
		if node is FoundationWorld:
			_world = node
			_view = _find_debug_view(_world)
			break
		if node is FoundationDebugView:
			_view = node
			_world = node.get_node_or_null(node.world_path) as FoundationWorld
			break
	if _world == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node."
		_record_options.clear()
		return
	if _world.world_data == null:
		_world.initialize_world()
	_populate_records()


func _find_debug_view(world: FoundationWorld) -> FoundationDebugView:
	for child in world.get_children():
		if child is FoundationDebugView:
			return child
	return null


func _populate_records(preferred_id: StringName = &"") -> void:
	if _world == null or _world.world_data == null:
		return
	if String(preferred_id).is_empty() and _record_options.item_count > 0:
		preferred_id = _selected_id()
	_record_options.clear()
	var selected_index := 0
	for record in _world.world_data.spatial_index.get_all_records():
		if record.layer_type not in _session.policy.supported_layers() and not (record is FoundationOverrideRecord):
			continue
		var label := "[%s] %s" % [record.layer_type, record.stable_id]
		if record is FoundationOverrideRecord:
			label = "[override:%s] %s -> %s" % [record.operation_kind, record.stable_id, record.target_record_id]
		_record_options.add_item(label)
		_record_options.set_item_metadata(_record_options.item_count - 1, record.stable_id)
		if record.stable_id == preferred_id:
			selected_index = _record_options.item_count - 1
	if _record_options.item_count == 0:
		_snapshot_editor.text = ""
		_status.text = "No authorable records are available."
		return
	_record_options.select(selected_index)
	_record_selected(selected_index)


func _record_selected(index: int) -> void:
	if _world == null or index < 0 or index >= _record_options.item_count:
		return
	var record := _world.world_data.get_record(_selected_id())
	if record == null:
		return
	_snapshot_editor.text = JSON.stringify(record.to_dict(), "\t", true, true)
	if _view != null:
		_view.selected_record_id = record.stable_id
		_view.rebuild()
	var override_record := record as FoundationOverrideRecord
	_status.text = "%s | history %d/%d%s" % [
		record.stable_id, _session.history.cursor, _session.history.commands.size(),
		" | target %s | revision %d | %s" % [override_record.target_record_id, override_record.revision, override_record.conflict_state] if override_record != null else "",
	]


func _selected_id() -> StringName:
	if _record_options.item_count == 0 or _record_options.selected < 0:
		return &""
	return StringName(_record_options.get_item_metadata(_record_options.selected))


func _target_id() -> StringName:
	var selected := _world.world_data.get_record(_selected_id()) if _world != null else null
	return (selected as FoundationOverrideRecord).target_record_id if selected is FoundationOverrideRecord else _selected_id()


func _parse_snapshot() -> Dictionary:
	var parsed := JSON.parse_string(_snapshot_editor.text)
	if not (parsed is Dictionary):
		_status.text = "Snapshot JSON must parse to an object; no data changed."
		return {}
	return parsed as Dictionary


func _lock_selected() -> void:
	var world_data := _require_world_data()
	if world_data != null:
		_finish(_session.lock_record(world_data, _target_id()))


func _unlock_selected() -> void:
	var world_data := _require_world_data()
	if world_data != null:
		_finish(_session.unlock_record(world_data, _target_id()))


func _apply_override() -> void:
	var world_data := _require_world_data()
	if world_data == null:
		return
	var snapshot := _parse_snapshot()
	if snapshot.is_empty():
		return
	_finish(_session.apply_override(world_data, _target_id(), snapshot, "Editor JSON override"))


func _create_authored() -> void:
	var world_data := _require_world_data()
	if world_data == null:
		return
	var snapshot := _parse_snapshot()
	if snapshot.is_empty():
		return
	_finish(_session.create_authored_record(world_data, snapshot, "Editor authored creation"))


func _delete_selected() -> void:
	var world_data := _require_world_data()
	if world_data != null:
		_finish(_session.delete_record(world_data, _target_id(), "Editor deletion tombstone"))


func _revert_selected() -> void:
	var world_data := _require_world_data()
	if world_data != null:
		_finish(_session.revert_override(world_data, _target_id()))


func _translate_selected() -> void:
	var world_data := _require_world_data()
	if world_data != null:
		_finish(_session.translate_record(world_data, _target_id(), Vector2(_translate_x.value, _translate_z.value)))


func _undo() -> void:
	var world_data := _require_world_data()
	if world_data != null:
		_finish(_session.undo(world_data))


func _redo() -> void:
	var world_data := _require_world_data()
	if world_data != null:
		_finish(_session.redo(world_data))


func _reapply() -> void:
	var world_data := _require_world_data()
	if world_data != null:
		_finish(_session.reapply_all(world_data))


func _validate() -> void:
	var world_data := _require_world_data()
	if world_data == null:
		return
	var issues := FoundationAuthoringValidator.validate(world_data, _session.policy, _session.history)
	var errors := 0
	var warnings := 0
	var serialized: Array[Dictionary] = []
	for issue in issues:
		serialized.append(issue.to_dict())
		if issue.severity == FoundationAuthoringValidationIssue.SEVERITY_ERROR:
			errors += 1
		elif issue.severity == FoundationAuthoringValidationIssue.SEVERITY_WARNING:
			warnings += 1
	world_data.get_layer(FoundationWorldData.OVERRIDE_LAYER).metadata["diagnostics"] = serialized
	_status.text = "Authoring validation: %d errors, %d warnings, %d total diagnostics." % [errors, warnings, issues.size()]
	_rebuild_debug()


func _finish(result: FoundationAuthoringResult) -> void:
	if result == null:
		return
	var impact := ""
	if not result.affected_layers.is_empty():
		var names := PackedStringArray()
		for layer in result.affected_layers:
			names.append(String(layer))
		impact = " Impact: %s. No generators ran." % ", ".join(names)
	var outcome := "%s%s%s" % ["OK: " if result.success else "ERROR: ", result.message, impact]
	var preferred := result.override_record_id if not String(result.override_record_id).is_empty() else result.target_record_id
	_populate_records(preferred)
	_rebuild_debug()
	_status.text = outcome


func _require_world_data() -> FoundationWorldData:
	if _world == null or _world.world_data == null:
		_status.text = "Select an initialized FoundationWorld or FoundationDebugView node; no data changed."
		return null
	return _world.world_data


func _rebuild_debug() -> void:
	if _view != null:
		_view.rebuild()
