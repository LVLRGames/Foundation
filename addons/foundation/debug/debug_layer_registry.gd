class_name FoundationDebugLayerRegistry
extends RefCounted

## Filterable provider registry with a true zero-work disabled path.

var enabled := true
var last_provider_invocations := 0
var _providers: Dictionary = {}
var _layer_enabled: Dictionary = {}


func register_provider(provider: FoundationDebugProvider, layer_enabled := true) -> bool:
	if _providers.has(provider.provider_id):
		return false
	_providers[provider.provider_id] = provider
	_layer_enabled[provider.provider_id] = layer_enabled
	return true


func set_layer_enabled(provider_id: StringName, value: bool) -> void:
	if _providers.has(provider_id):
		_layer_enabled[provider_id] = value


func is_layer_enabled(provider_id: StringName) -> bool:
	return bool(_layer_enabled.get(provider_id, false))


func get_provider(provider_id: StringName) -> FoundationDebugProvider:
	return _providers.get(provider_id) as FoundationDebugProvider


func get_provider_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for provider_id: StringName in _providers:
		result.append(provider_id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return result


func build(world: FoundationWorldData, context: Dictionary = {}) -> FoundationDebugGeometryBuilder:
	var builder := FoundationDebugGeometryBuilder.new()
	last_provider_invocations = 0
	if not enabled:
		return builder
	for provider_id in get_provider_ids():
		if not is_layer_enabled(provider_id):
			continue
		get_provider(provider_id).append_debug(world, builder, context)
		last_provider_invocations += 1
	return builder


func register_phase_1_defaults() -> void:
	for provider_id in [
		&"world_bounds", &"regions", &"chunks", &"terrain_grid", &"records", &"anchors", &"relationships",
	]:
		register_provider(FoundationDefaultDebugProvider.new(provider_id), provider_id != &"relationships")
	register_provider(FoundationRoadTopologyDebugProvider.new())
	register_provider(FoundationRoadTopologyDebugProvider.new(&"road_costs"), false)
	register_provider(FoundationRoadTopologyDebugProvider.new(&"road_candidates"), false)
	register_provider(FoundationRoadTopologyDebugProvider.new(&"road_validation"), false)
	register_provider(FoundationBlockDebugProvider.new())
	register_provider(FoundationParcelDebugProvider.new())
	register_provider(FoundationBuildingDebugProvider.new())
