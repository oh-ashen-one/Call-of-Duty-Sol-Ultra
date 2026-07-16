class_name BreakwaterContent
extends RefCounted

const BOT_NAMES := [
	"NORTHSTAR",
	"KITE",
	"MARLIN",
	"HARBOR",
	"RIPTIDE",
	"ECHO",
	"SABLE",
]

const LOADOUTS: Array[Dictionary] = [
	{
		"id": &"vanguard",
		"name": "Vanguard",
		"role": "Balanced assault",
		"primary": &"vx4_carbine",
		"secondary": &"sparrow_pistol",
		"lethal": &"frag",
		"tactical": &"flash",
	},
	{
		"id": &"riptide",
		"name": "Riptide",
		"role": "Close-quarters pressure",
		"primary": &"kestrel_smg",
		"secondary": &"breaker_12",
		"lethal": &"frag",
		"tactical": &"concussion",
	},
	{
		"id": &"overwatch",
		"name": "Overwatch",
		"role": "Precision and control",
		"primary": &"helix_dmr",
		"secondary": &"sparrow_pistol",
		"lethal": &"frag",
		"tactical": &"flash",
	},
	{
		"id": &"anchor",
		"name": "Anchor",
		"role": "Sustained lane denial",
		"primary": &"atlas_lmg",
		"secondary": &"sparrow_pistol",
		"lethal": &"frag",
		"tactical": &"concussion",
	},
]

const OPERATOR_SKINS: Array[Dictionary] = [
	{
		"id": &"harbor_slate",
		"name": "Harbor Slate",
		"description": "Storm-shell slate with sea-glass telemetry.",
		"primary": Color("223744"),
		"secondary": Color("ff6b4a"),
		"visor": Color("5ed3c6"),
	},
	{
		"id": &"rescue_coral",
		"name": "Search + Rescue",
		"description": "High-visibility rescue-coral over deep-ocean fabric.",
		"primary": Color("142635"),
		"secondary": Color("ff6b4a"),
		"visor": Color("f2c14e"),
	},
	{
		"id": &"pelagic_night",
		"name": "Pelagic Night",
		"description": "Low-light navy with violet trial hardware.",
		"primary": Color("07131f"),
		"secondary": Color("244e60"),
		"visor": Color("7e6edb"),
	},
]

const WEAPON_CAMOS: Array[Dictionary] = [
	{
		"id": &"saltline",
		"name": "Saltline",
		"description": "Mist-white shell with slate hardware.",
		"base": Color("dce8eb"),
		"accent": Color("5f7a82"),
		"metallic": 0.42,
	},
	{
		"id": &"kelp_grid",
		"name": "Kelp Grid",
		"description": "Deep kelp panels with sea-glass indexing.",
		"base": Color("173c38"),
		"accent": Color("5ed3c6"),
		"metallic": 0.64,
	},
	{
		"id": &"signal_flare",
		"name": "Signal Flare",
		"description": "Rescue-coral shell with sun-gold status marks.",
		"base": Color("ff6b4a"),
		"accent": Color("f2c14e"),
		"metallic": 0.82,
	},
]


static func loadout(index: int) -> Dictionary:
	return LOADOUTS[clampi(index, 0, LOADOUTS.size() - 1)].duplicate(true)


static func bot_name(index: int) -> String:
	return BOT_NAMES[clampi(index, 0, BOT_NAMES.size() - 1)]


static func operator_skin(index: int) -> Dictionary:
	return OPERATOR_SKINS[clampi(index, 0, OPERATOR_SKINS.size() - 1)].duplicate(true)


static func weapon_camo(index: int) -> Dictionary:
	return WEAPON_CAMOS[clampi(index, 0, WEAPON_CAMOS.size() - 1)].duplicate(true)


static func operator_skin_by_id(id: StringName) -> Dictionary:
	for entry: Dictionary in OPERATOR_SKINS:
		if entry.id == id:
			return entry.duplicate(true)
	return operator_skin(0)


static func weapon_camo_by_id(id: StringName) -> Dictionary:
	for entry: Dictionary in WEAPON_CAMOS:
		if entry.id == id:
			return entry.duplicate(true)
	return weapon_camo(0)
