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
@export var road_class_highway := Color("ef5350")
@export var road_class_arterial := Color("ff8a65")
@export var road_class_collector := Color("ffd54f")
@export var road_class_local := Color("80cbc4")
@export var road_class_alley := Color("b0bec5")
@export var road_class_dirt := Color("a1887f")
@export var road_pattern_grid := Color("42a5f5")
@export var road_pattern_suburban := Color("ab47bc")
@export var road_pattern_rural := Color("8bc34a")
@export var road_candidate_accepted := Color(0.20, 0.85, 0.45, 0.45)
@export var road_candidate_rejected := Color(0.90, 0.30, 0.30, 0.18)
@export var road_intersection := Color("ffffff")
@export var road_dead_end := Color("ffcc80")
@export var road_cul_de_sac := Color("f48fb1")
@export var road_grading_warning := Color("ff7043")
@export var road_validation_warning := Color("ffca28")
@export var road_validation_error := Color("f44336")
@export var road_desired_elevation := Color("e1bee7")
@export var road_cost_low := Color(0.25, 0.80, 0.38, 0.16)
@export var road_cost_medium := Color(1.0, 0.76, 0.18, 0.20)
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
		&"road_class_highway":
			return road_class_highway
		&"road_class_arterial":
			return road_class_arterial
		&"road_class_collector":
			return road_class_collector
		&"road_class_local":
			return road_class_local
		&"road_class_alley":
			return road_class_alley
		&"road_class_dirt":
			return road_class_dirt
		&"road_pattern_grid":
			return road_pattern_grid
		&"road_pattern_suburban":
			return road_pattern_suburban
		&"road_pattern_rural":
			return road_pattern_rural
		&"road_pattern_other":
			return relationship
		&"road_candidate_accepted":
			return road_candidate_accepted
		&"road_candidate_rejected":
			return road_candidate_rejected
		&"road_intersection":
			return road_intersection
		&"road_dead_end":
			return road_dead_end
		&"road_cul_de_sac":
			return road_cul_de_sac
		&"road_grading_warning", &"road_cost_high":
			return road_grading_warning
		&"road_cost_low":
			return road_cost_low
		&"road_cost_medium":
			return road_cost_medium
		&"road_validation_warning":
			return road_validation_warning
		&"road_validation_error":
			return road_validation_error
		&"road_desired_elevation":
			return road_desired_elevation
		&"road_anchor_priority":
			return anchor_generated
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
