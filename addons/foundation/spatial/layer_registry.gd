class_name FoundationLayerRegistry
extends RefCounted

## Stable registry for renderer-independent spatial layers.

var _layers: Dictionary = {}


func register_layer(layer: FoundationSpatialLayer) -> bool:
	if String(layer.layer_type).is_empty() or _layers.has(layer.layer_type):
		return false
	_layers[layer.layer_type] = layer
	return true


func unregister_layer(layer_type: StringName) -> bool:
	return _layers.erase(layer_type)


func get_layer(layer_type: StringName) -> FoundationSpatialLayer:
	return _layers.get(layer_type) as FoundationSpatialLayer


func has_layer(layer_type: StringName) -> bool:
	return _layers.has(layer_type)


func get_layer_types() -> Array[StringName]:
	var result: Array[StringName] = []
	for layer_type: StringName in _layers:
		result.append(layer_type)
	result.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return result


func get_layers() -> Array[FoundationSpatialLayer]:
	var result: Array[FoundationSpatialLayer] = []
	for layer_type in get_layer_types():
		result.append(get_layer(layer_type))
	return result


func clear() -> void:
	_layers.clear()
