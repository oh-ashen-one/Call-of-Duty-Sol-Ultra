class_name MatchRules
extends Node

## Free-for-all scoring authority. Every registered combatant emits the same
## eliminated(victim_id, killer_id) signal, so bots can score against one another
## even when the player never supplies input.

signal score_changed(combatant_id: StringName, score: int)
signal kill_recorded(killer_id: StringName, victim_id: StringName, killer_score: int)
signal leader_changed(combatant_id: StringName, score: int)
signal match_finished(winner_id: StringName, final_scores: Dictionary)
signal match_reset

@export_range(1, 999, 1) var target_score: int = 30

var scores: Dictionary = {}
var deaths: Dictionary = {}
var display_names: Dictionary = {}
var match_active: bool = true
var winner_id: StringName = &""
var _leader_id: StringName = &""
var _leader_score: int = 0
var _registered_nodes: Dictionary = {}


func register_combatant(combatant: Node, explicit_id: StringName = &"") -> StringName:
	if combatant == null:
		return &""
	var id := explicit_id
	if id.is_empty() and combatant.get("combatant_id") != null:
		id = StringName(str(combatant.get("combatant_id")))
	if id.is_empty():
		id = StringName("combatant_%d" % combatant.get_instance_id())
	if not scores.has(id):
		scores[id] = 0
		deaths[id] = 0
	var combatant_name: Variant = combatant.get("display_name")
	display_names[id] = str(combatant_name) if combatant_name != null else str(id)
	_registered_nodes[id] = combatant
	if combatant.has_signal("eliminated"):
		var callback := Callable(self, "_on_combatant_eliminated")
		if not combatant.is_connected("eliminated", callback):
			combatant.connect("eliminated", callback)
	return id


func unregister_combatant(combatant_id: StringName) -> void:
	_registered_nodes.erase(combatant_id)


func record_elimination(killer_id: StringName, victim_id: StringName) -> bool:
	if not match_active:
		return false
	if not deaths.has(victim_id):
		deaths[victim_id] = 0
	deaths[victim_id] = int(deaths[victim_id]) + 1
	if killer_id.is_empty() or killer_id == victim_id:
		kill_recorded.emit(killer_id, victim_id, get_score(killer_id))
		return false
	if not scores.has(killer_id):
		scores[killer_id] = 0
		display_names[killer_id] = str(killer_id)
	var new_score := mini(int(scores[killer_id]) + 1, target_score)
	scores[killer_id] = new_score
	score_changed.emit(killer_id, new_score)
	kill_recorded.emit(killer_id, victim_id, new_score)
	_update_leader()
	if new_score == target_score:
		_finish_match(killer_id)
	return true


func reset_match() -> void:
	for id in scores.keys():
		scores[id] = 0
		deaths[id] = 0
	match_active = true
	winner_id = &""
	_leader_id = &""
	_leader_score = 0
	match_reset.emit()


func get_score(combatant_id: StringName) -> int:
	return int(scores.get(combatant_id, 0))


func get_deaths(combatant_id: StringName) -> int:
	return int(deaths.get(combatant_id, 0))


func get_leader_id() -> StringName:
	return _leader_id


func scoreboard() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: Variant in scores.keys():
		rows.append({
			"id": StringName(id),
			"name": str(display_names.get(id, id)),
			"score": int(scores[id]),
			"deaths": int(deaths.get(id, 0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) == int(b["score"]):
			return int(a["deaths"]) < int(b["deaths"])
		return int(a["score"]) > int(b["score"])
	)
	return rows


func _on_combatant_eliminated(victim_id: StringName, killer_id: StringName) -> void:
	record_elimination(killer_id, victim_id)


func _update_leader() -> void:
	var best_id: StringName = &""
	var best_score := -1
	for raw_id: Variant in scores.keys():
		var candidate_id := StringName(raw_id)
		var candidate_score := int(scores[raw_id])
		if candidate_score > best_score:
			best_id = candidate_id
			best_score = candidate_score
	if best_id != _leader_id or best_score != _leader_score:
		_leader_id = best_id
		_leader_score = best_score
		leader_changed.emit(_leader_id, _leader_score)


func _finish_match(winner: StringName) -> void:
	match_active = false
	winner_id = winner
	match_finished.emit(winner_id, scores.duplicate(true))
