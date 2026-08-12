class_name FoundationSpatialRecordCodec
extends RefCounted

## Shared typed record restoration and canonical JSON helpers for Phase 11.


static func record_from_dict(data: Dictionary) -> FoundationSpatialRecord:
	var record_kind := StringName(data.get("record_kind", "spatial_record"))
	match record_kind:
		FoundationCityAnchor.RECORD_KIND:
			return FoundationCityAnchor.from_dict(data)
		FoundationRoadNode.RECORD_KIND:
			return FoundationRoadNode.from_dict(data)
		FoundationRoadEdge.RECORD_KIND:
			return FoundationRoadEdge.from_dict(data)
		FoundationRoadPatternArea.RECORD_KIND:
			return FoundationRoadPatternArea.from_dict(data)
		FoundationLogicalRoad.RECORD_KIND:
			return FoundationLogicalRoad.from_dict(data)
		FoundationIntersectionRecord.RECORD_KIND:
			return FoundationIntersectionRecord.from_dict(data)
		FoundationBlockRecord.RECORD_KIND:
			return FoundationBlockRecord.from_dict(data)
		FoundationParcelRecord.RECORD_KIND:
			return FoundationParcelRecord.from_dict(data)
		FoundationBuildingRecord.RECORD_KIND:
			return FoundationBuildingRecord.from_dict(data)
		FoundationFacadeRecord.RECORD_KIND:
			return FoundationFacadeRecord.from_dict(data)
		FoundationDistrictRecord.RECORD_KIND:
			return FoundationDistrictRecord.from_dict(data)
		FoundationParkingFacilityRecord.RECORD_KIND:
			return FoundationParkingFacilityRecord.from_dict(data)
		FoundationPublicFeatureRecord.RECORD_KIND:
			return FoundationPublicFeatureRecord.from_dict(data)
		FoundationOverrideRecord.RECORD_KIND:
			return FoundationOverrideRecord.from_dict(data)
		_:
			return FoundationSpatialRecord.from_dict(data)


static func canonical_json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


static func fingerprint(data: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical_json(data).to_utf8_buffer())
	return context.finish().hex_encode()


static func is_json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for child in value:
				if not is_json_safe(child):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not is_json_safe(value[key]):
					return false
			return true
	return false


static func changed_field_paths(before: Dictionary, after: Dictionary) -> PackedStringArray:
	var paths := PackedStringArray()
	_collect_changed_paths(before, after, "", paths)
	paths.sort()
	return paths


static func translate_record_data(data: Dictionary, delta: Vector2) -> Dictionary:
	var result := data.duplicate(true)
	_shift_rect(result, "world_bounds", delta)
	match StringName(result.get("record_kind", "")):
		FoundationCityAnchor.RECORD_KIND:
			_shift_point3(result, "world_position", delta)
			_shift_rect(result, "influence_bounds", delta)
		FoundationRoadNode.RECORD_KIND:
			_shift_point3(result, "world_position", delta)
		FoundationRoadEdge.RECORD_KIND:
			_shift_point3_array(result, "route_points", delta)
		FoundationBlockRecord.RECORD_KIND:
			_shift_point2_array(result, "outer_boundary", delta)
			_shift_point2(result, "centroid", delta)
			_shift_point2(result, "label_point", delta)
		FoundationParcelRecord.RECORD_KIND:
			_shift_point2_array(result, "boundary", delta)
			_shift_point2(result, "centroid", delta)
			_shift_point2(result, "label_point", delta)
		FoundationBuildingRecord.RECORD_KIND:
			_shift_point2_array(result, "footprint", delta)
			_shift_point2(result, "centroid", delta)
			_shift_point2(result, "label_point", delta)
		FoundationFacadeRecord.RECORD_KIND:
			_shift_point2(result, "start", delta)
			_shift_point2(result, "end", delta)
		FoundationDistrictRecord.RECORD_KIND:
			_shift_nested_point2_arrays(result, "boundary_components", delta)
			_shift_point2(result, "centroid", delta)
			_shift_point2(result, "label_point", delta)
		FoundationParkingFacilityRecord.RECORD_KIND:
			_shift_point2_array(result, "footprint", delta)
			_shift_point2(result, "centroid", delta)
			_shift_point2(result, "label_point", delta)
			for space: Dictionary in result.get("spaces", []):
				_shift_point2(space, "position", delta)
			for path: Dictionary in result.get("access_paths", []):
				_shift_point2_array(path, "points", delta)
		FoundationPublicFeatureRecord.RECORD_KIND:
			_shift_point2_array(result, "footprint", delta)
			_shift_point2(result, "position", delta)
	return result


static func _collect_changed_paths(before: Variant, after: Variant, prefix: String, paths: PackedStringArray) -> void:
	if typeof(before) == TYPE_DICTIONARY and typeof(after) == TYPE_DICTIONARY:
		var keys: Array[String] = []
		for key in before:
			keys.append(String(key))
		for key in after:
			if String(key) not in keys:
				keys.append(String(key))
		keys.sort()
		for key in keys:
			var path := key if prefix.is_empty() else "%s.%s" % [prefix, key]
			if not before.has(key) or not after.has(key):
				paths.append(path)
			else:
				_collect_changed_paths(before[key], after[key], path, paths)
		return
	if canonical_json(before) != canonical_json(after):
		paths.append(prefix)


static func _shift_point2(container: Dictionary, key: String, delta: Vector2) -> void:
	var point: Dictionary = container.get(key, {})
	if point.is_empty():
		return
	point["x"] = float(point.get("x", 0.0)) + delta.x
	point["y"] = float(point.get("y", 0.0)) + delta.y
	container[key] = point


static func _shift_point3(container: Dictionary, key: String, delta: Vector2) -> void:
	var point: Dictionary = container.get(key, {})
	if point.is_empty():
		return
	point["x"] = float(point.get("x", 0.0)) + delta.x
	point["z"] = float(point.get("z", 0.0)) + delta.y
	container[key] = point


static func _shift_rect(container: Dictionary, key: String, delta: Vector2) -> void:
	var rect: Dictionary = container.get(key, {})
	if rect.is_empty():
		return
	rect["x"] = float(rect.get("x", 0.0)) + delta.x
	rect["y"] = float(rect.get("y", 0.0)) + delta.y
	container[key] = rect


static func _shift_point2_array(container: Dictionary, key: String, delta: Vector2) -> void:
	var shifted: Array[Dictionary] = []
	for point: Dictionary in container.get(key, []):
		var copy := point.duplicate(true)
		copy["x"] = float(copy.get("x", 0.0)) + delta.x
		copy["y"] = float(copy.get("y", 0.0)) + delta.y
		shifted.append(copy)
	container[key] = shifted


static func _shift_point3_array(container: Dictionary, key: String, delta: Vector2) -> void:
	var shifted: Array[Dictionary] = []
	for point: Dictionary in container.get(key, []):
		var copy := point.duplicate(true)
		copy["x"] = float(copy.get("x", 0.0)) + delta.x
		copy["z"] = float(copy.get("z", 0.0)) + delta.y
		shifted.append(copy)
	container[key] = shifted


static func _shift_nested_point2_arrays(container: Dictionary, key: String, delta: Vector2) -> void:
	var components: Array = []
	for component in container.get(key, []):
		var shifted: Array[Dictionary] = []
		for point: Dictionary in component:
			var copy := point.duplicate(true)
			copy["x"] = float(copy.get("x", 0.0)) + delta.x
			copy["y"] = float(copy.get("y", 0.0)) + delta.y
			shifted.append(copy)
		components.append(shifted)
	container[key] = components
