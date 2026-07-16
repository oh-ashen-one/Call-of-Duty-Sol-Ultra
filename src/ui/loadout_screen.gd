class_name BreakwaterLoadoutScreen
extends BreakwaterUIScreen
## Data-driven weapon and equipment selection.

signal loadout_changed(loadout: Dictionary)
signal apply_requested(loadout: Dictionary)

const DEFAULT_WEAPONS: Array[Dictionary] = [
	{"id": &"vx4_carbine", "name": "VX-4 CARBINE", "role": "ASSAULT RIFLE", "tagline": "Balanced automatic rifle", "damage": 68, "range": 72, "control": 66, "mobility": 62, "magazine": 30},
	{"id": &"kestrel_smg", "name": "KESTREL SMG", "role": "SUBMACHINE GUN", "tagline": "Fast close-quarters pressure", "damage": 49, "range": 42, "control": 72, "mobility": 91, "magazine": 36},
	{"id": &"breaker_12", "name": "BREAKER-12", "role": "PUMP SHOTGUN", "tagline": "Heavy short-range impact", "damage": 96, "range": 31, "control": 43, "mobility": 65, "magazine": 8},
	{"id": &"helix_dmr", "name": "HELIX DMR", "role": "MARKSMAN RIFLE", "tagline": "Precise semi-automatic reach", "damage": 86, "range": 94, "control": 57, "mobility": 48, "magazine": 14},
	{"id": &"atlas_lmg", "name": "ATLAS LMG", "role": "LIGHT MACHINE GUN", "tagline": "Sustained lane control", "damage": 64, "range": 78, "control": 48, "mobility": 32, "magazine": 72},
	{"id": &"sparrow_pistol", "name": "SPARROW PISTOL", "role": "SIDEARM", "tagline": "Reliable emergency sidearm", "damage": 58, "range": 46, "control": 82, "mobility": 96, "magazine": 15},
]

var _catalog: Array[Dictionary] = DEFAULT_WEAPONS.duplicate(true)
var _loadout: Dictionary = {
	"primary": &"vx4_carbine",
	"secondary": &"sparrow_pistol",
	"lethal": &"frag",
	"tactical": &"flash",
}
var _equipped_loadout: Dictionary = _loadout.duplicate(true)
var _weapon_buttons: Dictionary = {}
var _name_label: Label
var _role_label: Label
var _description_label: Label
var _stat_bars: Dictionary = {}
var _preset_option: OptionButton
var _sidearm_caption: Label
var _lethal_option: OptionButton
var _tactical_option: OptionButton
var _apply_button: Button


func build_screen() -> void:
	var layout := make_page_layout("Field loadout", "READY DECK / ARMORY")
	var stack: VBoxContainer = layout.stack
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", 24)
	stack.add_child(split)

	var list_panel := BreakwaterUI.panel()
	list_panel.custom_minimum_size.x = 430.0
	split.add_child(list_panel)
	var list_stack := VBoxContainer.new()
	list_stack.add_theme_constant_override(&"separation", 8)
	list_panel.add_child(list_stack)
	list_stack.add_child(BreakwaterUI.section_label("LOADOUT PRESET"))
	_preset_option = OptionButton.new()
	_preset_option.custom_minimum_size = Vector2(0.0, 48.0)
	_preset_option.add_item("CUSTOM FIELD KIT")
	_preset_option.set_item_metadata(0, &"custom")
	for preset: Dictionary in BreakwaterContent.LOADOUTS:
		_preset_option.add_item("%s  /  %s" % [String(preset.name).to_upper(), String(preset.role).to_upper()])
		_preset_option.set_item_metadata(_preset_option.item_count - 1, preset.id)
	list_stack.add_child(_preset_option)
	list_stack.add_child(BreakwaterUI.section_label("PRIMARY PLATFORM"))
	for weapon: Dictionary in _catalog:
		if weapon.id == &"sparrow_pistol":
			continue
		var weapon_button := BreakwaterUI.button(String(weapon.name), &"NavButton")
		weapon_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		weapon_button.pressed.connect(_select_primary.bind(StringName(weapon.id)))
		list_stack.add_child(weapon_button)
		_weapon_buttons[weapon.id] = weapon_button
	_sidearm_caption = BreakwaterUI.data_label("")
	_sidearm_caption.add_theme_color_override(&"font_color", BreakwaterUI.SUN_GOLD)
	list_stack.add_child(_sidearm_caption)

	var detail_panel := BreakwaterUI.panel(&"GlassPanel")
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail_panel)
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override(&"separation", 14)
	detail_panel.add_child(detail)
	_role_label = BreakwaterUI.section_label("")
	detail.add_child(_role_label)
	_name_label = BreakwaterUI.label("", &"HeadingLabel")
	detail.add_child(_name_label)
	_description_label = BreakwaterUI.label("")
	detail.add_child(_description_label)
	detail.add_child(BreakwaterUI.h_rule())
	for stat_name in ["DAMAGE", "RANGE", "CONTROL", "MOBILITY"]:
		detail.add_child(_make_stat_row(stat_name))
	var flex := Control.new()
	flex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(flex)
	detail.add_child(BreakwaterUI.section_label("FIELD EQUIPMENT"))
	var equipment := HBoxContainer.new()
	equipment.add_theme_constant_override(&"separation", 14)
	detail.add_child(equipment)
	_lethal_option = _equipment_option("LETHAL", [{"label": "FRAG GRENADE", "id": &"frag"}])
	equipment.add_child(_lethal_option.get_parent())
	_tactical_option = _equipment_option("TACTICAL", [
		{"label": "FLASH GRENADE", "id": &"flash"},
		{"label": "CONCUSSION", "id": &"concussion"},
	])
	equipment.add_child(_tactical_option.get_parent())
	_apply_button = BreakwaterUI.button("EQUIP LOADOUT", &"PrimaryButton")
	_apply_button.pressed.connect(_emit_apply)
	detail.add_child(_apply_button)
	var back := BreakwaterUI.button("BACK")
	back.pressed.connect(_cancel_and_return)
	detail.add_child(back)

	_preset_option.item_selected.connect(_on_preset_selected)
	_lethal_option.item_selected.connect(_on_lethal_selected)
	_tactical_option.item_selected.connect(_on_tactical_selected)
	_sync_options()
	_sync_preset_selection()
	_refresh_selection()


func set_weapon_catalog(catalog: Array[Dictionary]) -> void:
	_catalog = catalog.duplicate(true)


func set_loadout(loadout: Dictionary) -> void:
	for key: Variant in _loadout.keys():
		if loadout.has(key):
			_loadout[key] = loadout[key]
	_equipped_loadout = _loadout.duplicate(true)
	if is_node_ready():
		_sync_options()
		_sync_preset_selection()
		_refresh_selection()


func get_loadout() -> Dictionary:
	return _equipped_loadout.duplicate(true)


func get_pending_loadout() -> Dictionary:
	return _loadout.duplicate(true)


func focus_default() -> void:
	_loadout = _equipped_loadout.duplicate(true)
	_sync_options()
	_sync_preset_selection()
	_refresh_selection()
	var selected_button: Variant = _weapon_buttons.get(_loadout.primary)
	if selected_button is Button:
		selected_button.grab_focus()


func _select_primary(weapon_id: StringName) -> void:
	_loadout.primary = weapon_id
	_mark_custom_preset()
	_refresh_selection()
	loadout_changed.emit(get_pending_loadout())


func _refresh_selection() -> void:
	var secondary := _weapon_by_id(StringName(_loadout.secondary))
	var secondary_name := String(secondary.get("name", String(_loadout.secondary).replace("_", " ").to_upper()))
	_sidearm_caption.text = "SECONDARY  /  %s" % secondary_name
	var weapon := _weapon_by_id(StringName(_loadout.primary))
	if weapon.is_empty():
		return
	_name_label.text = String(weapon.name)
	_role_label.text = String(weapon.role)
	_description_label.text = "%s  /  %d-round capacity" % [weapon.tagline, weapon.magazine]
	for stat_key: String in ["damage", "range", "control", "mobility"]:
		(_stat_bars[stat_key] as ProgressBar).value = float(weapon[stat_key])
	for id: Variant in _weapon_buttons.keys():
		var button_node := _weapon_buttons[id] as Button
		button_node.modulate = BreakwaterUI.MIST if id == _loadout.primary else Color(BreakwaterUI.MIST, 0.62)


func _make_stat_row(stat_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	var caption := BreakwaterUI.data_label(stat_name)
	caption.custom_minimum_size.x = 112.0
	row.add_child(caption)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size.y = 12.0
	bar.add_theme_stylebox_override(&"background", BreakwaterUI.panel_style(BreakwaterUI.SLATE_LIGHT, BreakwaterUI.SLATE_LIGHT, 0, 3, 0))
	bar.add_theme_stylebox_override(&"fill", BreakwaterUI.panel_style(BreakwaterUI.SEA_GLASS, BreakwaterUI.SEA_GLASS, 0, 3, 0))
	row.add_child(bar)
	_stat_bars[stat_name.to_lower()] = bar
	return row


func _equipment_option(caption: String, entries: Array[Dictionary]) -> OptionButton:
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(BreakwaterUI.data_label(caption))
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(260.0, 48.0)
	for entry: Dictionary in entries:
		option.add_item(String(entry.label))
		option.set_item_metadata(option.item_count - 1, entry.id)
	stack.add_child(option)
	return option


func _on_lethal_selected(index: int) -> void:
	_loadout.lethal = _lethal_option.get_item_metadata(index)
	_mark_custom_preset()
	loadout_changed.emit(get_pending_loadout())


func _on_tactical_selected(index: int) -> void:
	_loadout.tactical = _tactical_option.get_item_metadata(index)
	_mark_custom_preset()
	loadout_changed.emit(get_pending_loadout())


func _on_preset_selected(index: int) -> void:
	if index <= 0 or index > BreakwaterContent.LOADOUTS.size():
		return
	_preset_option.select(index)
	var preset := BreakwaterContent.loadout(index - 1)
	for key: String in ["primary", "secondary", "lethal", "tactical"]:
		_loadout[key] = preset[key]
	_sync_options()
	_refresh_selection()
	loadout_changed.emit(get_pending_loadout())


func _sync_options() -> void:
	_select_option_by_metadata(_lethal_option, _loadout.lethal)
	_select_option_by_metadata(_tactical_option, _loadout.tactical)


func _sync_preset_selection() -> void:
	for preset_index in BreakwaterContent.LOADOUTS.size():
		var preset: Dictionary = BreakwaterContent.LOADOUTS[preset_index]
		if (
			preset.primary == _loadout.primary
			and preset.secondary == _loadout.secondary
			and preset.lethal == _loadout.lethal
			and preset.tactical == _loadout.tactical
		):
			_preset_option.select(preset_index + 1)
			return
	_preset_option.select(0)


func _mark_custom_preset() -> void:
	if _preset_option != null:
		_preset_option.select(0)


func _select_option_by_metadata(option: OptionButton, value: Variant) -> void:
	for index in option.item_count:
		if option.get_item_metadata(index) == value:
			option.select(index)
			return


func _emit_apply() -> void:
	_equipped_loadout = _loadout.duplicate(true)
	apply_requested.emit(get_loadout())


func _cancel_and_return() -> void:
	_loadout = _equipped_loadout.duplicate(true)
	_sync_options()
	_sync_preset_selection()
	_refresh_selection()
	back_requested.emit()


func _weapon_by_id(weapon_id: StringName) -> Dictionary:
	for weapon: Dictionary in _catalog:
		if StringName(weapon.id) == weapon_id:
			return weapon
	return {}
