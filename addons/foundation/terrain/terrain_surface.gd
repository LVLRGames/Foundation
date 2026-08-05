class_name FoundationTerrainSurface
extends RefCounted

## Stable surface identifiers stored in TerrainData, never inferred by the renderer.

enum Type {
	GRASS,
	DIRT,
	SAND,
	ROCK,
	MUD,
	ASPHALT,
	CONCRETE,
	GRAVEL,
	FARMLAND,
	WATERBED,
	WETLAND,
	SNOW,
	DECORATIVE_GROUND,
}

const COUNT := 13
const NAMES: PackedStringArray = [
	"Grass", "Dirt", "Sand", "Rock", "Mud", "Asphalt", "Concrete",
	"Gravel", "Farmland", "Waterbed", "Wetland", "Snow", "Decorative Ground",
]
const COLORS: PackedColorArray = [
	Color("6f9b45"), Color("8a633f"), Color("d7bd78"), Color("70757a"),
	Color("554b3f"), Color("2d3035"), Color("a7a7a2"), Color("8d8170"),
	Color("9e8b45"), Color("455366"), Color("667d54"), Color("e3e7e8"),
	Color("a45c82"),
]


static func is_valid(surface_id: int) -> bool:
	return surface_id >= 0 and surface_id < COUNT


static func display_name(surface_id: int) -> String:
	return NAMES[surface_id] if is_valid(surface_id) else "Unknown"


static func color(surface_id: int) -> Color:
	return COLORS[surface_id] if is_valid(surface_id) else Color.MAGENTA
