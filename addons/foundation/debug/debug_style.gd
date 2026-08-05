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
@export var anchor_generated := Color("26c6da")
@export var anchor_locked := Color("ffee58")
@export var anchor_overridden := Color("ab47bc")
@export var anchor_influence := Color(0.15, 0.78, 0.85, 0.55)
@export var road_node_generated := Color("fff59d")
@export var road_node_locked := Color("ffb300")
@export var road_node_overridden := Color("ec407a")
@export var road_edge_generated := Color("80cbc4")
@export var road_edge_locked := Color("ffca28")
@export var road_edge_overridden := Color("ce93d8")
@export var block_generated := Color("66bb6a")
@export var block_locked := Color("fdd835")
@export var block_overridden := Color("ab47bc")
@export var block_invalid := Color("ef5350")
@export var block_fill_generated := Color(0.40, 0.73, 0.42, 0.16)
@export var block_fill_locked := Color(0.99, 0.85, 0.21, 0.18)
@export var block_fill_overridden := Color(0.67, 0.28, 0.74, 0.18)
@export var block_fill_invalid := Color(0.94, 0.33, 0.31, 0.20)
@export var block_fill_selected := Color(1.0, 1.0, 1.0, 0.24)
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
		&"anchor_generated":
			return anchor_generated
		&"anchor_locked":
			return anchor_locked
		&"anchor_overridden":
			return anchor_overridden
		&"anchor_influence":
			return anchor_influence
		&"road_node_generated":
			return road_node_generated
		&"road_node_locked":
			return road_node_locked
		&"road_node_overridden":
			return road_node_overridden
		&"road_edge_generated":
			return road_edge_generated
		&"road_edge_locked":
			return road_edge_locked
		&"road_edge_overridden":
			return road_edge_overridden
		&"block_generated":
			return block_generated
		&"block_locked":
			return block_locked
		&"block_overridden":
			return block_overridden
		&"block_invalid":
			return block_invalid
		&"block_fill_generated":
			return block_fill_generated
		&"block_fill_locked":
			return block_fill_locked
		&"block_fill_overridden":
			return block_fill_overridden
		&"block_fill_invalid":
			return block_fill_invalid
		&"block_fill_selected":
			return block_fill_selected
		&"selected":
			return selected
		&"relationship":
			return relationship
		&"label":
			return label
		_:
			return chunk_clean
