class_name BreakwaterSkinsScreen
extends BreakwaterUIScreen
## Operator palette and weapon-camouflage selection.

signal selection_changed(selection: Dictionary)
signal apply_requested(selection: Dictionary)

const SKINS: Array[Dictionary] = [
	{"id": &"harbor_slate", "name": "HARBOR SLATE", "role": "STANDARD ISSUE", "colors": [Color("223744"), Color("ff6b4a"), Color("5ed3c6")]},
	{"id": &"rescue_coral", "name": "SEARCH + RESCUE", "role": "HIGH VISIBILITY", "colors": [Color("142635"), Color("ff6b4a"), Color("f2c14e")]},
	{"id": &"pelagic_night", "name": "PELAGIC NIGHT", "role": "LOW-LIGHT TRIAL", "colors": [Color("07131f"), Color("244e60"), Color("7e6edb")]},
]

const CAMOS: Array[Dictionary] = [
	{"id": &"saltline", "name": "SALTLINE", "colors": [Color("dce8eb"), Color("5f7a82"), Color("142635")]},
	{"id": &"kelp_grid", "name": "KELP GRID", "colors": [Color("173c38"), Color("5ed3c6"), Color("091b20")]},
	{"id": &"signal_flare", "name": "SIGNAL FLARE", "colors": [Color("ff6b4a"), Color("f2c14e"), Color("142635")]},
]

var _selection := {"skin": &"harbor_slate", "camo": &"saltline"}
var _equipped_selection := _selection.duplicate(true)
var _skin_cards: Dictionary = {}
var _camo_cards: Dictionary = {}
var _first_skin_button: Button


func build_screen() -> void:
	var layout := make_page_layout("Visual identity", "READY DECK / QUARTERMASTER")
	var stack: VBoxContainer = layout.stack
	stack.add_child(BreakwaterUI.section_label("OPERATOR SKIN"))
	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override(&"separation", 18)
	skin_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(skin_row)
	for skin: Dictionary in SKINS:
		var card := _appearance_card(skin, true)
		skin_row.add_child(card)
		_skin_cards[skin.id] = card

	stack.add_child(BreakwaterUI.section_label("WEAPON CAMOUFLAGE"))
	var camo_row := HBoxContainer.new()
	camo_row.add_theme_constant_override(&"separation", 18)
	stack.add_child(camo_row)
	for camo: Dictionary in CAMOS:
		var card := _appearance_card(camo, false)
		camo_row.add_child(card)
		_camo_cards[camo.id] = card

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override(&"separation", 12)
	stack.add_child(actions)
	var back := BreakwaterUI.button("BACK")
	back.pressed.connect(_cancel_and_return)
	actions.add_child(back)
	var apply := BreakwaterUI.button("APPLY APPEARANCE", &"PrimaryButton")
	apply.pressed.connect(_emit_apply)
	actions.add_child(apply)
	_refresh_cards()


func set_selection(selection: Dictionary) -> void:
	if selection.has("skin"):
		_selection.skin = selection.skin
	if selection.has("camo"):
		_selection.camo = selection.camo
	_equipped_selection = _selection.duplicate(true)
	if is_node_ready():
		_refresh_cards()


func get_selection() -> Dictionary:
	return _equipped_selection.duplicate(true)


func get_pending_selection() -> Dictionary:
	return _selection.duplicate(true)


func focus_default() -> void:
	_selection = _equipped_selection.duplicate(true)
	_refresh_cards()
	if is_instance_valid(_first_skin_button):
		_first_skin_button.grab_focus()


func _appearance_card(entry: Dictionary, is_skin: bool) -> PanelContainer:
	var card := BreakwaterUI.panel()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(290.0, 190.0 if is_skin else 130.0)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	card.add_child(content)
	var swatches := HBoxContainer.new()
	swatches.custom_minimum_size.y = 58.0 if is_skin else 30.0
	content.add_child(swatches)
	for swatch_color: Color in entry.colors:
		var swatch := ColorRect.new()
		swatch.color = swatch_color
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatches.add_child(swatch)
	content.add_child(BreakwaterUI.section_label(String(entry.get("role", "WEAPON FINISH"))))
	var choose := BreakwaterUI.button(String(entry.name), &"NavButton")
	choose.custom_minimum_size = Vector2(0.0, 46.0)
	choose.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if is_skin:
		choose.pressed.connect(_select_skin.bind(StringName(entry.id)))
		if _first_skin_button == null:
			_first_skin_button = choose
	else:
		choose.pressed.connect(_select_camo.bind(StringName(entry.id)))
	content.add_child(choose)
	card.set_meta(&"choice_button", choose)
	return card


func _select_skin(skin_id: StringName) -> void:
	_selection.skin = skin_id
	_refresh_cards()
	selection_changed.emit(get_pending_selection())


func _select_camo(camo_id: StringName) -> void:
	_selection.camo = camo_id
	_refresh_cards()
	selection_changed.emit(get_pending_selection())


func _emit_apply() -> void:
	_equipped_selection = _selection.duplicate(true)
	apply_requested.emit(get_selection())


func _cancel_and_return() -> void:
	_selection = _equipped_selection.duplicate(true)
	_refresh_cards()
	back_requested.emit()


func _refresh_cards() -> void:
	for skin_id: Variant in _skin_cards.keys():
		_style_card(_skin_cards[skin_id] as PanelContainer, skin_id == _selection.skin)
	for camo_id: Variant in _camo_cards.keys():
		_style_card(_camo_cards[camo_id] as PanelContainer, camo_id == _selection.camo)


func _style_card(card: PanelContainer, selected: bool) -> void:
	card.add_theme_stylebox_override(
		&"panel",
		BreakwaterUI.panel_style(
			Color(BreakwaterUI.SLATE, 0.94),
			BreakwaterUI.SUN_GOLD if selected else Color(BreakwaterUI.SLATE_LIGHT, 0.75),
			2 if selected else 1,
			8,
			16,
			4 if selected else 0
		)
	)
	var choice: Button = card.get_meta(&"choice_button")
	choice.modulate = BreakwaterUI.MIST if selected else Color(BreakwaterUI.MIST, 0.67)
