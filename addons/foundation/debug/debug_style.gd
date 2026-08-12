@tool
class_name FoundationDebugStyle
extends Resource

## Central semantic palette for every Foundation debug provider.

@export var world_bounds := Color("fff176")
@export var region_bounds := Color("ce93d8")
@export var chunk_clean := Color("64b5f6")
@export var chunk_dirty := Color("ef5350")
@export var streaming_unloaded := Color(0.18, 0.21, 0.25, 0.48)
@export var streaming_data := Color(0.35, 0.45, 0.55, 0.52)
@export var streaming_proxy := Color(0.20, 0.67, 0.67, 0.58)
@export var streaming_visual_far := Color(0.25, 0.72, 0.93, 0.62)
@export var streaming_visual_near := Color(0.40, 0.78, 0.45, 0.68)
@export var streaming_physics := Color(1.0, 0.65, 0.24, 0.72)
@export var streaming_gameplay := Color(0.94, 0.38, 0.70, 0.78)
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
@export var parcel_generated := Color("90caf9")
@export var parcel_locked := Color("ffee58")
@export var parcel_overridden := Color("ce93d8")
@export var parcel_corner := Color("4dd0e1")
@export var parcel_remainder := Color("ffb74d")
@export var parcel_invalid := Color("ef5350")
@export var parcel_frontage_primary := Color("ffffff")
@export var parcel_frontage_secondary := Color("26c6da")
@export var parcel_fill_generated := Color(0.56, 0.79, 0.98, 0.13)
@export var parcel_fill_corner := Color(0.30, 0.82, 0.88, 0.18)
@export var parcel_fill_remainder := Color(1.0, 0.72, 0.30, 0.22)
@export var parcel_fill_invalid := Color(0.94, 0.33, 0.31, 0.22)
@export var parcel_fill_selected := Color(1.0, 1.0, 1.0, 0.28)
@export var building_generated := Color("b39ddb")
@export var building_locked := Color("ffee58")
@export var building_overridden := Color("f48fb1")
@export var building_invalid := Color("ef5350")
@export var building_skipped := Color("ffb74d")
@export var building_roof_generated := Color(0.70, 0.62, 0.86, 0.34)
@export var building_roof_locked := Color(1.0, 0.93, 0.35, 0.38)
@export var building_roof_overridden := Color(0.96, 0.56, 0.69, 0.38)
@export var building_roof_invalid := Color(0.94, 0.33, 0.31, 0.40)
@export var building_roof_selected := Color(1.0, 1.0, 1.0, 0.48)
@export var facade_primary := Color("80deea")
@export var facade_side := Color("90caf9")
@export var facade_rear := Color("b0bec5")
@export var facade_grid := Color(0.72, 0.78, 0.82, 0.44)
@export var facade_window := Color("42a5f5")
@export var facade_entrance := Color("ffca28")
@export var facade_locked := Color("ffee58")
@export var facade_overridden := Color("f48fb1")
@export var facade_invalid := Color("ef5350")
@export var facade_skipped := Color("ffb74d")
@export var district_downtown := Color("ef5350")
@export var district_mixed_use := Color("ffb74d")
@export var district_residential := Color("66bb6a")
@export var district_industrial := Color("78909c")
@export var district_civic := Color("ab47bc")
@export var district_suburban := Color("26a69a")
@export var district_rural := Color("8bc34a")
@export var district_locked := Color("ffee58")
@export var district_overridden := Color("f48fb1")
@export var district_invalid := Color("f44336")
@export var district_warning := Color("ffca28")
@export var district_boundary := Color(1.0, 1.0, 1.0, 0.34)
@export var district_seed_link := Color("80deea")
@export var grading_road := Color("ffb74d")
@export var grading_pad := Color("b39ddb")
@export var grading_bridge := Color("4dd0e1")
@export var grading_cut := Color("ef5350")
@export var grading_fill := Color("66bb6a")
@export var grading_warning := Color("ffca28")
@export var grading_error := Color("f44336")
@export var parking_generated := Color("42a5f5")
@export var parking_locked := Color("ffee58")
@export var parking_overridden := Color("f48fb1")
@export var parking_invalid := Color("f44336")
@export var parking_warning := Color("ffb74d")
@export var parking_fill := Color(0.26, 0.65, 0.96, 0.24)
@export var parking_stall := Color("e3f2fd")
@export var parking_accessible := Color("ffee58")
@export var parking_access := Color("80deea")
@export var public_feature_park := Color("66bb6a")
@export var public_feature_plaza := Color("ffca28")
@export var public_feature_transit := Color("26c6da")
@export var public_feature_civic := Color("ab47bc")
@export var public_feature_locked := Color("ffee58")
@export var public_feature_overridden := Color("f48fb1")
@export var public_feature_invalid := Color("f44336")
@export var public_feature_warning := Color("ffb74d")
@export var public_feature_fill := Color(0.40, 0.73, 0.42, 0.26)
@export var public_feature_service := Color(0.40, 0.73, 0.42, 0.22)
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
		&"streaming_unloaded":
			return streaming_unloaded
		&"streaming_data":
			return streaming_data
		&"streaming_proxy":
			return streaming_proxy
		&"streaming_visual_far":
			return streaming_visual_far
		&"streaming_visual_near":
			return streaming_visual_near
		&"streaming_physics":
			return streaming_physics
		&"streaming_gameplay":
			return streaming_gameplay
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
		&"parcel_generated":
			return parcel_generated
		&"parcel_locked":
			return parcel_locked
		&"parcel_overridden":
			return parcel_overridden
		&"parcel_corner":
			return parcel_corner
		&"parcel_remainder":
			return parcel_remainder
		&"parcel_invalid":
			return parcel_invalid
		&"parcel_frontage_primary":
			return parcel_frontage_primary
		&"parcel_frontage_secondary":
			return parcel_frontage_secondary
		&"parcel_fill_generated":
			return parcel_fill_generated
		&"parcel_fill_corner":
			return parcel_fill_corner
		&"parcel_fill_remainder":
			return parcel_fill_remainder
		&"parcel_fill_invalid":
			return parcel_fill_invalid
		&"parcel_fill_selected":
			return parcel_fill_selected
		&"building_generated":
			return building_generated
		&"building_locked":
			return building_locked
		&"building_overridden":
			return building_overridden
		&"building_invalid":
			return building_invalid
		&"building_skipped":
			return building_skipped
		&"building_roof_generated":
			return building_roof_generated
		&"building_roof_locked":
			return building_roof_locked
		&"building_roof_overridden":
			return building_roof_overridden
		&"building_roof_invalid":
			return building_roof_invalid
		&"building_roof_selected":
			return building_roof_selected
		&"facade_primary":
			return facade_primary
		&"facade_side":
			return facade_side
		&"facade_rear":
			return facade_rear
		&"facade_grid":
			return facade_grid
		&"facade_window":
			return facade_window
		&"facade_entrance":
			return facade_entrance
		&"facade_locked":
			return facade_locked
		&"facade_overridden":
			return facade_overridden
		&"facade_invalid":
			return facade_invalid
		&"facade_skipped":
			return facade_skipped
		&"district_downtown_core", &"district_fill_downtown_core":
			return district_downtown
		&"district_mixed_use_center", &"district_fill_mixed_use_center":
			return district_mixed_use
		&"district_residential_neighborhood", &"district_fill_residential_neighborhood":
			return district_residential
		&"district_industrial_employment", &"district_fill_industrial_employment":
			return district_industrial
		&"district_civic_institutional", &"district_fill_civic_institutional":
			return district_civic
		&"district_suburban_neighborhood", &"district_fill_suburban_neighborhood":
			return district_suburban
		&"district_rural_edge", &"district_fill_rural_edge":
			return district_rural
		&"district_locked", &"district_fill_locked":
			return district_locked
		&"district_overridden", &"district_fill_overridden":
			return district_overridden
		&"district_invalid", &"district_fill_invalid":
			return district_invalid
		&"district_warning":
			return district_warning
		&"district_boundary":
			return district_boundary
		&"district_seed_link":
			return district_seed_link
		&"district_fill_selected":
			return selected
		&"grading_road":
			return grading_road
		&"grading_pad", &"grading_pad_fill":
			return grading_pad
		&"grading_bridge", &"grading_bridge_approach":
			return grading_bridge
		&"grading_cut":
			return grading_cut
		&"grading_fill":
			return grading_fill
		&"grading_warning":
			return grading_warning
		&"grading_error":
			return grading_error
		&"grading_label":
			return label
		&"parking_generated":
			return parking_generated
		&"parking_locked":
			return parking_locked
		&"parking_overridden":
			return parking_overridden
		&"parking_invalid":
			return parking_invalid
		&"parking_warning":
			return parking_warning
		&"parking_fill":
			return parking_fill
		&"parking_stall":
			return parking_stall
		&"parking_accessible":
			return parking_accessible
		&"parking_access":
			return parking_access
		&"parking_fill_selected":
			return selected
		&"public_feature_park", &"public_feature_playground":
			return public_feature_park
		&"public_feature_plaza":
			return public_feature_plaza
		&"public_feature_transit_stop":
			return public_feature_transit
		&"public_feature_civic_marker", &"public_feature_landmark_site":
			return public_feature_civic
		&"public_feature_locked":
			return public_feature_locked
		&"public_feature_overridden":
			return public_feature_overridden
		&"public_feature_invalid":
			return public_feature_invalid
		&"public_feature_warning":
			return public_feature_warning
		&"public_feature_fill":
			return public_feature_fill
		&"public_feature_fill_selected":
			return selected
		&"public_feature_service":
			return public_feature_service
		&"public_feature_anchor_link":
			return relationship
		&"selected":
			return selected
		&"relationship":
			return relationship
		&"label":
			return label
		_:
			return chunk_clean
