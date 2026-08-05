@tool
class_name FoundationDebugEditorDock
extends ScrollContainer

## Editor controls affect only disposable debug presentation, never world generation.

var _editor_interface: EditorInterface
var _content: VBoxContainer
var _view: FoundationDebugView
var _status: Label
var _global_toggle: CheckBox
var _follow_selection: CheckBox
var _selection_options: OptionButton
var _selection_details: Label
var _layer_toggles: Dictionary = {}


func initialize(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	if is_node_ready():
		_connect_selection()


func _ready() -> void:
	name = "Foundation Debug"
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
	heading.text = "Foundation Debug View"
	heading.add_theme_font_size_override("font_size", 18)
	_content.add_child(heading)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status)

	_global_toggle = CheckBox.new()
	_global_toggle.text = "Debug rendering enabled"
	_global_toggle.toggled.connect(_global_toggled)
	_content.add_child(_global_toggle)

	for layer_data in [
		[&"world_bounds", "World bounds"],
		[&"regions", "Regions and IDs"],
		[&"chunks", "Chunks and dirty state"],
		[&"terrain_grid", "Terrain cell grid"],
		[&"records", "Spatial records"],
		[&"anchors", "City anchor markers and IDs"],
		[&"relationships", "Parent/child relationships"],
	]:
		var toggle := CheckBox.new()
		toggle.text = layer_data[1]
		toggle.toggled.connect(_layer_toggled.bind(layer_data[0]))
		_layer_toggles[layer_data[0]] = toggle
		_content.add_child(toggle)

	_follow_selection = CheckBox.new()
	_follow_selection.text = "Follow editor selection"
	_follow_selection.button_pressed = true
	_content.add_child(_follow_selection)

	var selection_label := Label.new()
	selection_label.text = "Debug selection"
	_content.add_child(selection_label)
	_selection_options = OptionButton.new()
	_selection_options.item_selected.connect(_debug_selection_changed)
	_content.add_child(_selection_options)

	_selection_details = Label.new()
	_selection_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_selection_details)

	var rebuild_button := Button.new()
	rebuild_button.text = "Rebuild Debug Display"
	rebuild_button.pressed.connect(_rebuild_pressed)
	_content.add_child(rebuild_button)


func _connect_selection() -> void:
	if _editor_interface == null:
		return
	var selection := _editor_interface.get_selection()
	if not selection.selection_changed.is_connected(_editor_selection_changed):
		selection.selection_changed.connect(_editor_selection_changed)


func _editor_selection_changed() -> void:
	if _editor_interface == null or (_follow_selection != null and not _follow_selection.button_pressed):
		return
	_view = null
	for node in _editor_interface.get_selection().get_selected_nodes():
		if node is FoundationDebugView:
			_view = node
			break
		if node is FoundationWorld:
			for child in node.get_children():
				if child is FoundationDebugView:
					_view = child
					break
	if _view == null:
		_status.text = "Select a FoundationWorld or FoundationDebugView node."
		_selection_options.clear()
		return
	_sync_from_view()


func _sync_from_view() -> void:
	_global_toggle.button_pressed = _view.debug_enabled
	_layer_toggles[&"world_bounds"].button_pressed = _view.show_world_bounds
	_layer_toggles[&"regions"].button_pressed = _view.show_regions
	_layer_toggles[&"chunks"].button_pressed = _view.show_chunks
	_layer_toggles[&"terrain_grid"].button_pressed = _view.show_terrain_grid
	_layer_toggles[&"records"].button_pressed = _view.show_records
	_layer_toggles[&"anchors"].button_pressed = _view.show_anchors
	_layer_toggles[&"relationships"].button_pressed = _view.show_relationships
	_status.text = "Editing %s. Visibility changes never regenerate world data." % _view.name
	_populate_selection_options()


func _populate_selection_options() -> void:
	_selection_options.clear()
	var world_node := _view.get_node_or_null(_view.world_path) as FoundationWorld
	if world_node == null:
		return
	if world_node.world_data == null:
		world_node.initialize_world()
	_selection_options.add_item("World")
	_selection_options.set_item_metadata(0, {"kind": "world"})
	for chunk in world_node.world_data.get_sorted_chunks():
		_selection_options.add_item("Chunk %d, %d" % [chunk.coordinate.x, chunk.coordinate.y])
		_selection_options.set_item_metadata(
			_selection_options.item_count - 1,
			{"kind": "chunk", "coordinate": chunk.coordinate}
		)
	for record in world_node.world_data.spatial_index.get_all_records():
		_selection_options.add_item(String(record.stable_id))
		_selection_options.set_item_metadata(
			_selection_options.item_count - 1,
			{"kind": "record", "stable_id": record.stable_id}
		)
	_debug_selection_changed(0)


func _global_toggled(value: bool) -> void:
	if _view != null:
		_view.set_debug_enabled(value)


func _layer_toggled(value: bool, layer_id: StringName) -> void:
	if _view == null:
		return
	match layer_id:
		&"world_bounds": _view.show_world_bounds = value
		&"regions": _view.show_regions = value
		&"chunks": _view.show_chunks = value
		&"terrain_grid": _view.show_terrain_grid = value
		&"records": _view.show_records = value
		&"anchors": _view.show_anchors = value
		&"relationships": _view.show_relationships = value
	_status.text = "Visibility updated. Use Rebuild Debug Display to apply it."


func _debug_selection_changed(index: int) -> void:
	if _view == null or index < 0 or index >= _selection_options.item_count:
		return
	var selection: Dictionary = _selection_options.get_item_metadata(index)
	_view.selected_record_id = &""
	_view.selected_chunk = Vector2i(2147483647, 2147483647)
	var world_node := _view.get_node_or_null(_view.world_path) as FoundationWorld
	match selection.get("kind", "world"):
		"chunk":
			_view.selected_chunk = selection["coordinate"]
			var chunk := world_node.world_data.get_chunk(_view.selected_chunk)
			_selection_details.text = "%s\nBounds: %s\nDirty: %s" % [
				chunk.stable_id, chunk.world_bounds, chunk.get_dirty_layers(),
			]
		"record":
			_view.selected_record_id = selection["stable_id"]
			var record := world_node.world_data.get_record(_view.selected_record_id)
			if record is FoundationCityAnchor:
				var anchor := record as FoundationCityAnchor
				_selection_details.text = "%s\nCategory: %s\nPosition: %s\nInfluence: %s\nPriority: %.2f\nChunks: %s\nRegions: %s" % [
					anchor.stable_id,
					anchor.anchor_category,
					anchor.world_position,
					anchor.world_bounds,
					anchor.priority_weight,
					anchor.owning_chunks,
					anchor.owning_regions,
				]
			else:
				_selection_details.text = "%s\nBounds: %s\nParent: %s\nLayer: %s" % [
					record.stable_id, record.world_bounds, record.parent_id, record.layer_type,
				]
		_:
			_selection_details.text = "World bounds: %s" % world_node.world_data.metadata.world_bounds


func _rebuild_pressed() -> void:
	if _view == null:
		return
	var primitive_count := _view.rebuild()
	_status.text = "Rebuilt %d disposable debug primitive(s)." % primitive_count
