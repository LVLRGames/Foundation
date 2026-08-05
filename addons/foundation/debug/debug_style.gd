@tool
class_name FoundationDebugStyle
extends Resource

## Central semantic palette for every Foundation debug provider.

@export var world_bounds := Color("fff176")
@export var region_bounds := Color("ce93d8")
@export var chunk_clean := Color("64b5f6")
@export var chunk_dirty := Color("ef5350")
@export var terrain_grid := Color(0.45, 0.55, 0.62, 0.35)
@export var record_generated := Color("81c784")
@export var record_locked := Color("ffb74d")
@export var record_overridden := Color("f06292")
@export var selected := Color("ffffff")
@export var relationship := Color("4dd0e1")
@export var label := Color("f5f5f5")
@export var fill_alpha := 0.12


func color_for(purpose: StringName) -> Color:
	match purpose:
		&"world_bounds":
			return world_bounds
		&"region_bounds":
			return region_bounds
		&"chunk_dirty":
			return chunk_dirty
		&"terrain_grid":
			return terrain_grid
		&"record_generated":
			return record_generated
		&"record_locked":
			return record_locked
		&"record_overridden":
			return record_overridden
		&"selected":
			return selected
		&"relationship":
			return relationship
		&"label":
			return label
		_:
			return chunk_clean
