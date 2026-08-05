@tool
class_name FoundationTerrainEditorDock
extends ScrollContainer

## Deliberately explicit editor actions; profile changes never trigger large rebuilds.

var _editor_interface: EditorInterface
var _content: VBoxContainer
var _terrain: FoundationTerrain
var _status_label: Label
var _seed_input: SpinBox
var _width_input: SpinBox
var _depth_input: SpinBox
var _cell_size_input: SpinBox
var _height_step_input: SpinBox
var _frequency_input: SpinBox
var _amplitude_input: SpinBox


func initialize(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	if is_node_ready():
		_connect_selection()


func _ready() -> void:
	name = "Foundation Terrain"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
	_build_interface()
	_connect_selection()
	_selection_changed()


func shutdown() -> void:
	if _editor_interface == null:
		return
	var selection := _editor_interface.get_selection()
	if selection.selection_changed.is_connected(_selection_changed):
		selection.selection_changed.disconnect(_selection_changed)


func _build_interface() -> void:
	var heading := Label.new()
	heading.text = "Foundation Phase 0"
	heading.add_theme_font_size_override("font_size", 18)
	_content.add_child(heading)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_status_label)

	_seed_input = _add_spinbox("Seed", -2147483648.0, 2147483647.0, 1.0)
	_width_input = _add_spinbox("Width (cells)", 1.0, 4096.0, 1.0)
	_depth_input = _add_spinbox("Depth (cells)", 1.0, 4096.0, 1.0)
	_cell_size_input = _add_spinbox("Cell size (m)", 0.01, 1024.0, 0.25)
	_height_step_input = _add_spinbox("Height step (m)", 0.01, 1024.0, 0.25)
	_frequency_input = _add_spinbox("Noise frequency", 0.00001, 1.0, 0.001)
	_amplitude_input = _add_spinbox("Amplitude (m)", 0.0, 10000.0, 0.5)

	var generate_button := Button.new()
	generate_button.text = "Generate Terrain"
	generate_button.pressed.connect(_generate_pressed)
	_content.add_child(generate_button)

	var rebuild_button := Button.new()
	rebuild_button.text = "Rebuild Dirty Chunks"
	rebuild_button.pressed.connect(_rebuild_pressed)
	_content.add_child(rebuild_button)


func _add_spinbox(label_text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.allow_greater = true
	input.allow_lesser = minimum < 0.0
	input.custom_arrow_step = step
	row.add_child(input)
	_content.add_child(row)
	return input


func _connect_selection() -> void:
	if _editor_interface == null:
		return
	var selection := _editor_interface.get_selection()
	if not selection.selection_changed.is_connected(_selection_changed):
		selection.selection_changed.connect(_selection_changed)


func _selection_changed() -> void:
	_terrain = null
	if _editor_interface != null:
		for node in _editor_interface.get_selection().get_selected_nodes():
			if node is FoundationTerrain:
				_terrain = node
				break
	if _terrain == null:
		_status_label.text = "Select a FoundationTerrain node to edit its explicit generation profile."
		_set_controls_enabled(false)
		return
	if _terrain.profile == null:
		_terrain.profile = FoundationTerrainProfile.new()
	_status_label.text = "Editing %s" % _terrain.name
	_seed_input.value = _terrain.profile.seed
	_width_input.value = _terrain.profile.grid_cells.x
	_depth_input.value = _terrain.profile.grid_cells.y
	_cell_size_input.value = _terrain.profile.cell_size
	_height_step_input.value = _terrain.profile.height_step
	_frequency_input.value = _terrain.profile.noise_frequency
	_amplitude_input.value = _terrain.profile.height_amplitude
	_set_controls_enabled(true)


func _set_controls_enabled(enabled: bool) -> void:
	for control in [
		_seed_input, _width_input, _depth_input, _cell_size_input,
		_height_step_input, _frequency_input, _amplitude_input,
	]:
		control.editable = enabled


func _apply_profile_inputs() -> void:
	var terrain_profile := _terrain.profile
	terrain_profile.seed = int(_seed_input.value)
	terrain_profile.grid_cells = Vector2i(int(_width_input.value), int(_depth_input.value))
	terrain_profile.cell_size = _cell_size_input.value
	terrain_profile.height_step = _height_step_input.value
	terrain_profile.noise_frequency = _frequency_input.value
	terrain_profile.height_amplitude = _amplitude_input.value


func _generate_pressed() -> void:
	if _terrain == null:
		return
	_apply_profile_inputs()
	if _terrain.generate_terrain():
		_status_label.text = "Generated seed %d into %d chunks." % [
			_terrain.profile.seed,
			_terrain.get_loaded_chunk_coordinates().size(),
		]


func _rebuild_pressed() -> void:
	if _terrain == null:
		return
	var rebuilt := _terrain.rebuild_dirty_chunks()
	_status_label.text = "Rebuilt %d dirty chunk(s)." % rebuilt
