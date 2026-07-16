class_name AudioDirector
extends Node

## Lightweight original procedural audio. It keeps the playable build completely
## self-contained while still providing layered weapon, UI, impact, and ambience
## feedback. No external samples are used.

const MIX_RATE := 22050
const POOL_SIZE := 14

var _pool: Array[AudioStreamPlayer] = []
var _pool_cursor := 0
var _ambience: AudioStreamPlayer
var _score: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _cache: Dictionary = {}
var _disabled := false
var ambience_active := true
var ui_navigation_requests := 0
var ui_confirm_requests := 0
var movement_requests: Dictionary = {}
var stinger_requests := 0


func _ready() -> void:
	_disabled = DisplayServer.get_name() == "headless"
	if _disabled:
		return
	_rng.seed = 0xB4E4A7E2
	for index in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%02d" % index
		player.bus = "SFX"
		add_child(player)
		_pool.append(player)
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "CoastalAmbience"
	_ambience.bus = "SFX"
	add_child(_ambience)
	_ambience.stream = _make_ambience()
	_ambience.volume_db = -24.0
	_ambience.play()
	_score = AudioStreamPlayer.new()
	_score.name = "BreakwaterScore"
	_score.bus = "Music"
	add_child(_score)
	_score.stream = _make_score()
	_score.volume_db = -18.0
	_score.play()


func play_ui(confirm: bool = false) -> void:
	if confirm:
		ui_confirm_requests += 1
	else:
		ui_navigation_requests += 1
	if _disabled:
		return
	var key := "ui_confirm" if confirm else "ui_move"
	if not _cache.has(key):
		_cache[key] = _make_tone(720.0 if confirm else 510.0, 0.075, 0.22, 0.0, 0.0, 90.0)
	_play(_cache[key], "UI", -4.0)


func play_shot(weapon_id: StringName) -> void:
	if _disabled:
		return
	var profiles := {
		&"sparrow_pistol": [150.0, 0.11, 0.72, 0.46],
		&"kestrel_smg": [118.0, 0.085, 0.58, 0.54],
		&"vx4_carbine": [92.0, 0.13, 0.82, 0.51],
		&"breaker_12": [66.0, 0.24, 1.0, 0.68],
		&"helix_dmr": [78.0, 0.18, 0.92, 0.44],
		&"atlas_lmg": [72.0, 0.16, 0.9, 0.57],
	}
	var profile: Array = profiles.get(weapon_id, profiles[&"vx4_carbine"])
	var key := "shot_%s" % weapon_id
	if not _cache.has(key):
		_cache[key] = _make_tone(profile[0], profile[1], profile[2], profile[3], 0.65, -45.0)
	_play(_cache[key], "SFX", -2.0, _rng.randf_range(0.96, 1.04))


func play_hit(kill: bool = false) -> void:
	if _disabled:
		return
	var key := "kill" if kill else "hit"
	if not _cache.has(key):
		_cache[key] = _make_tone(880.0 if kill else 610.0, 0.09 if kill else 0.045, 0.34, 0.0, 0.08, 240.0)
	_play(_cache[key], "UI", -1.0)


func play_reload() -> void:
	if _disabled:
		return
	if not _cache.has("reload"):
		_cache["reload"] = _make_tone(230.0, 0.16, 0.2, 0.55, 0.12, 320.0)
	_play(_cache["reload"], "SFX", -8.0, _rng.randf_range(0.94, 1.06))


func play_pump() -> void:
	if _disabled:
		return
	if not _cache.has("pump"):
		_cache["pump"] = _make_tone(168.0, 0.21, 0.28, 0.68, 0.18, 210.0)
	_play(_cache["pump"], "SFX", -5.0, _rng.randf_range(0.95, 1.04))


func play_impact() -> void:
	if _disabled:
		return
	if not _cache.has("impact"):
		_cache["impact"] = _make_tone(310.0, 0.075, 0.24, 0.72, 0.12, -150.0)
	_play(_cache["impact"], "SFX", -9.0, _rng.randf_range(0.9, 1.1))


func play_melee() -> void:
	if _disabled:
		return
	if not _cache.has("melee"):
		_cache["melee"] = _make_tone(96.0, 0.18, 0.52, 0.78, 0.3, 110.0)
	_play(_cache["melee"], "SFX", -3.0, _rng.randf_range(0.94, 1.04))


func play_grenade_throw() -> void:
	if _disabled:
		return
	if not _cache.has("grenade_throw"):
		_cache["grenade_throw"] = _make_tone(142.0, 0.16, 0.3, 0.6, 0.06, 180.0)
	_play(_cache["grenade_throw"], "SFX", -6.0, _rng.randf_range(0.95, 1.08))


func play_weapon_swap() -> void:
	if _disabled:
		return
	if not _cache.has("weapon_swap"):
		_cache["weapon_swap"] = _make_tone(205.0, 0.13, 0.2, 0.52, 0.05, -80.0)
	_play(_cache["weapon_swap"], "SFX", -8.0, _rng.randf_range(0.94, 1.06))


func play_movement(kind: StringName, strength: float = 1.0) -> void:
	movement_requests[kind] = int(movement_requests.get(kind, 0)) + 1
	if _disabled:
		return
	var key := "movement_%s" % kind
	if not _cache.has(key):
		match kind:
			&"footstep": _cache[key] = _make_tone(92.0, 0.09, 0.36, 0.82, 0.22, -38.0)
			&"jump": _cache[key] = _make_tone(135.0, 0.11, 0.26, 0.52, 0.08, 105.0)
			&"land": _cache[key] = _make_tone(58.0, 0.18, 0.58, 0.86, 0.42, -24.0)
			&"slide": _cache[key] = _make_tone(74.0, 0.34, 0.4, 0.92, 0.18, 62.0)
			_: _cache[key] = _make_tone(100.0, 0.1, 0.25, 0.7, 0.1, 0.0)
	_play(
		_cache[key],
		"SFX",
		lerpf(-13.0, -4.0, clampf(strength, 0.0, 1.0)),
		_rng.randf_range(0.92, 1.08),
	)


func play_result_stinger(victory: bool) -> void:
	stinger_requests += 1
	if _disabled:
		return
	var key := "victory_stinger" if victory else "defeat_stinger"
	if not _cache.has(key):
		_cache[key] = _make_tone(
			196.0 if victory else 164.0,
			0.85,
			0.42,
			0.06,
			0.05,
			196.0 if victory else -82.0,
		)
	_play(_cache[key], "Music", -2.0)


func play_explosion(intensity: float = 1.0) -> void:
	if _disabled:
		return
	var key := "explosion"
	if not _cache.has(key):
		_cache[key] = _make_tone(48.0, 0.78, 1.0, 0.8, 0.82, -35.0)
	_play(_cache[key], "SFX", lerpf(-10.0, 1.0, clampf(intensity, 0.0, 1.0)), _rng.randf_range(0.9, 1.03))


func set_match_intensity(active: bool) -> void:
	if _disabled:
		return
	if not is_instance_valid(_ambience):
		return
	_ambience.volume_db = -20.0 if active else -24.0
	_ambience.pitch_scale = 1.06 if active else 1.0
	if is_instance_valid(_score):
		_score.volume_db = -13.5 if active else -18.0
		_score.pitch_scale = 1.02 if active else 1.0


func set_ambience_active(active: bool) -> void:
	ambience_active = active
	if _disabled or not is_instance_valid(_ambience):
		return
	if active:
		if not _ambience.playing:
			_ambience.play()
		if is_instance_valid(_score) and not _score.playing:
			_score.play()
	else:
		_ambience.stop()
		if is_instance_valid(_score):
			_score.stop()


func _play(stream: AudioStream, bus_name: StringName, volume_db: float, pitch: float = 1.0) -> void:
	if _pool.is_empty():
		return
	var player := _pool[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % _pool.size()
	player.stop()
	player.bus = bus_name
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _make_tone(
	frequency: float,
	duration: float,
	level: float,
	noise_mix: float,
	distortion: float,
	pitch_sweep: float
) -> AudioStreamWAV:
	var frames := maxi(1, int(duration * MIX_RATE))
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var phase := 0.0
	for index in frames:
		var t := float(index) / float(MIX_RATE)
		var life := t / duration
		var envelope := pow(1.0 - life, 2.2) * minf(1.0, life * 70.0)
		var current_frequency := maxf(20.0, frequency + pitch_sweep * life)
		phase += TAU * current_frequency / float(MIX_RATE)
		var tonal := sin(phase) * 0.68 + sin(phase * 2.03) * 0.22
		var noise := _rng.randf_range(-1.0, 1.0)
		var sample := lerpf(tonal, noise, noise_mix) * envelope * level
		if distortion > 0.0:
			sample = lerpf(sample, tanh(sample * (1.0 + distortion * 5.0)), distortion)
		_write_sample(bytes, index, sample)
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = MIX_RATE
	wave.stereo = false
	wave.data = bytes
	return wave


func _make_ambience() -> AudioStreamWAV:
	var duration := 5.0
	var frames := int(duration * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var smoothed_noise := 0.0
	for index in frames:
		var t := float(index) / float(MIX_RATE)
		smoothed_noise = lerpf(smoothed_noise, _rng.randf_range(-1.0, 1.0), 0.006)
		var surf := sin(t * TAU * 0.17) * 0.035 + sin(t * TAU * 0.31) * 0.02
		var beacon := sin(t * TAU * 67.0) * maxf(0.0, sin(t * TAU * 0.2)) * 0.005
		_write_sample(bytes, index, smoothed_noise * 0.11 + surf + beacon)
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = MIX_RATE
	wave.stereo = false
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave.loop_begin = 0
	wave.loop_end = frames
	wave.data = bytes
	return wave


func _make_score() -> AudioStreamWAV:
	# Twelve-second original generative cue: four soft suspended chords over a
	# restrained low pulse. It loops seamlessly at a zero-crossing envelope and
	# uses no samples or third-party musical material.
	var duration := 12.0
	var chord_duration := 3.0
	var frames := int(duration * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var chords: Array[PackedFloat32Array] = [
		PackedFloat32Array([110.0, 146.83, 164.81, 220.0]),
		PackedFloat32Array([98.0, 130.81, 146.83, 196.0]),
		PackedFloat32Array([130.81, 164.81, 196.0, 261.63]),
		PackedFloat32Array([87.31, 116.54, 130.81, 174.61]),
	]
	for index in frames:
		var t := float(index) / float(MIX_RATE)
		var chord_index := mini(int(t / chord_duration), chords.size() - 1)
		var local_time := fmod(t, chord_duration)
		var pad_envelope := sin(PI * local_time / chord_duration)
		pad_envelope *= pad_envelope
		var pad := 0.0
		for frequency in chords[chord_index]:
			pad += sin(TAU * frequency * t) * 0.012
			pad += sin(TAU * frequency * 0.5 * t) * 0.006
		var beat_time := fmod(t, 0.75)
		var pulse := sin(TAU * (52.0 - beat_time * 9.0) * beat_time) * exp(-beat_time * 11.0) * 0.045
		var shimmer := sin(TAU * 523.25 * t) * maxf(0.0, sin(TAU * t / 6.0)) * 0.0025
		_write_sample(bytes, index, pad * pad_envelope + pulse + shimmer)
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = MIX_RATE
	wave.stereo = false
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave.loop_begin = 0
	wave.loop_end = frames
	wave.data = bytes
	return wave


func _write_sample(bytes: PackedByteArray, frame: int, sample: float) -> void:
	var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
	if value < 0:
		value += 65536
	bytes[frame * 2] = value & 0xFF
	bytes[frame * 2 + 1] = (value >> 8) & 0xFF
