extends Node
## Autoload `Audio`: every sound and all the music in the game.
##
## Nothing here needs an audio file. Every effect and every music track is synthesised in
## code the first time the game runs and cached as .wav files under user://audio_cache/, so
## the game is complete and licence-free as it stands. Real recordings can replace any sound
## by dropping a file into res://assets/sounds/<name>.wav|ogg (effects) or
## res://assets/music/<track>.ogg|wav (music); see assets/sounds/README.md for the names and
## for where to get free (CC0) recordings.
##
## Buses: "Effects" (battle sounds, ambience, UI), "Music", "Radio" (dispatch and card chimes).

const CACHE_VERSION := 5
const RATE := 22050
const MUSIC_RATE := 16000

## Effects: name -> how to build it. "loop" sounds are built to loop seamlessly.
const SOUNDS := ["gun_small", "gun_medium", "gun_large", "boom", "boom_big", "splash", "torp",
	"alarm", "flak", "dc", "ping", "mg", "click", "radio", "creak", "bell", "bomb", "aa_bofors", "aa_mg",
	"plane", "fire", "ocean", "wind", "rain"]
const LOOPS := ["plane", "fire", "ocean", "wind", "rain"]
const TRACKS := ["menu", "map", "battle", "victory", "defeat"]

var bank := {}                 # name -> AudioStream
var variants := {}             # name -> [AudioStream, ...] when recordings with _1, _2 ... exist
var music_streams := {}        # track -> AudioStream
var ready_ok := false          # true once the bank exists
var headless := false
var fx_players: Array = []     # one-shot effect players (Effects bus)
var loops := {}                # name -> AudioStreamPlayer (looping ambience)
var loop_goal := {}            # name -> target linear volume
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var music_cur := ""            # track now playing
var _va := 0.0                 # current linear volumes of the two music players
var _vb := 0.0
var music_goal := 0.0
var sting_t := -1.0
var sting_back := ""
var _thread: Thread
var _tables := {}              # wavetables for the music synth


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	for i in 16:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		fx_players.append(p)
	for nm in LOOPS:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		p.volume_db = -80.0
		add_child(p)
		loops[nm] = p
		loop_goal[nm] = 0.0
	music_a = AudioStreamPlayer.new(); music_a.bus = "Music"; add_child(music_a)
	music_b = AudioStreamPlayer.new(); music_b.bus = "Music"; add_child(music_b)
	if "--audiotest" in OS.get_cmdline_user_args():
		# test hook: synthesise everything now, on the main thread, and report the time
		headless = false
		var t0 := Time.get_ticks_msec()
		_build_all_sync()
		print("audio: built %d sounds and %d tracks in %.1f s -> %s" % [bank.size(), music_streams.size(), (Time.get_ticks_msec() - t0) / 1000.0, ProjectSettings.globalize_path(_cache_dir())])
		return
	if headless:
		return
	if _load_cache():
		_finish_bank()
	else:
		_thread = Thread.new()
		_thread.start(_build_all)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


# ---------------------------------------------------------------- building and caching

func _cache_dir() -> String:
	return "user://audio_cache/v%d" % CACHE_VERSION


func _load_cache() -> bool:
	var dir := _cache_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return false
	for nm in SOUNDS:
		var w := _load_wav(dir + "/%s.wav" % nm)
		if w == null:
			return false
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if nm in LOOPS else AudioStreamWAV.LOOP_DISABLED
		w.loop_end = w.data.size() / 2
		bank[nm] = w
	for tr in TRACKS:
		var w := _load_wav(dir + "/music_%s.wav" % tr)
		if w == null:
			return false
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if tr in ["menu", "map", "battle"] else AudioStreamWAV.LOOP_DISABLED
		w.loop_end = w.data.size() / 2
		music_streams[tr] = w
	return true


## Reads a 16-bit mono PCM .wav written by AudioStreamWAV.save_to_wav.
func _load_wav(path: String) -> AudioStreamWAV:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var rate := bytes.decode_u32(24)
	# find the data chunk
	var pos := 12
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var sz := bytes.decode_u32(pos + 4)
		if id == "data":
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS
			w.mix_rate = rate
			w.stereo = false
			w.data = bytes.slice(pos + 8, pos + 8 + sz)
			return w
		pos += 8 + sz + (sz & 1)
	return null


## Runs on a worker thread the first time: synthesises everything and writes the cache.
func _build_all() -> void:
	var dir := _cache_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var snd := {}
	for nm in SOUNDS:
		var w := _make_sound(nm)
		w.save_to_wav(dir + "/%s.wav" % nm)
		snd[nm] = w
	var mus := {}
	_make_tables()
	for tr in TRACKS:
		var w := _make_track(tr)
		w.save_to_wav(dir + "/music_%s.wav" % tr)
		mus[tr] = w
	call_deferred("_built", snd, mus)


func _build_all_sync() -> void:
	_build_all()
	# _build_all defers _built(); do it now instead
	_load_cache()
	_finish_bank()


func _built(snd: Dictionary, mus: Dictionary) -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	bank = snd
	music_streams = mus
	_finish_bank()


## Real recordings in assets/ override the synthesised ones, then everything goes live.
func _finish_bank() -> void:
	variants.clear()
	for nm in SOUNDS:
		# name.wav|ogg replaces the synthesised sound; name_1, name_2 ... are variations picked at random
		var found := []
		for suffix in ["", "_1", "_2", "_3", "_4", "_5", "_6", "_7", "_8"]:
			for ext in ["wav", "ogg"]:
				var path := "res://assets/sounds/%s%s.%s" % [nm, suffix, ext]
				if ResourceLoader.exists(path):
					var st = load(path)
					if st is AudioStreamWAV and nm in LOOPS:
						st.loop_mode = AudioStreamWAV.LOOP_FORWARD
						st.loop_end = st.data.size() / (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1) / (2 if st.stereo else 1)
					elif st is AudioStreamOggVorbis:
						st.loop = nm in LOOPS
					found.append(st)
		if not found.is_empty():
			bank[nm] = found[0]
			variants[nm] = found
	for tr in TRACKS:
		for ext in ["ogg", "wav"]:
			var path := "res://assets/music/%s.%s" % [tr, ext]
			if ResourceLoader.exists(path):
				var st = load(path)
				if st is AudioStreamOggVorbis:
					st.loop = tr in ["menu", "map", "battle"]
				music_streams[tr] = st
	for nm in LOOPS:
		loops[nm].stream = bank[nm]
		loops[nm].play()
	ready_ok = true
	if music_cur != "":
		var tr := music_cur
		music_cur = ""
		music(tr)


# ---------------------------------------------------------------- playing

## One-shot effect at full volume (UI, radio). `bus` lets the dispatch chime go to Radio.
func ui(nm: String, vol := 1.0, bus := "Effects") -> void:
	_shoot(nm, vol, randf_range(0.97, 1.03), bus)


## One-shot effect at a world position; volume falls off with distance from the camera.
func at(nm: String, pos: Vector2, cam: Vector3, vol := 1.0) -> void:
	var d := Vector2(pos.x - cam.x, pos.y - cam.z).length() + cam.y * 0.4
	var g := vol / (1.0 + d / 900.0)
	if g < 0.03:
		return
	_shoot(nm, g, randf_range(0.92, 1.08), "Effects")


func _shoot(nm: String, g: float, pitch: float, bus: String) -> void:
	if not ready_ok or not bank.has(nm):
		return
	var st: AudioStream = bank[nm]
	if variants.has(nm):
		var v: Array = variants[nm]
		st = v[randi() % v.size()]
	for p in fx_players:
		if not p.playing:
			p.bus = bus
			p.stream = st
			p.volume_db = linear_to_db(clampf(g, 0.0, 1.5))
			p.pitch_scale = pitch
			p.play()
			return


## Target volume (0..1) for a looping ambience sound; it fades there over a second or so.
func loop(nm: String, vol: float) -> void:
	if loop_goal.has(nm):
		loop_goal[nm] = clampf(vol, 0.0, 1.0)


## Sets the sea/wind/rain beds for a weather key from Data.WEATHER.
func ambience(weather: String, sea := 1.0) -> void:
	var w: Dictionary = Data.WEATHER.get(weather, {})
	var chop: float = w.get("chop", 1.0)
	loop("ocean", sea * clampf(0.35 + 0.35 * chop, 0.3, 0.9))
	loop("wind", sea * clampf((chop - 0.7) * 0.5, 0.0, 0.6))
	loop("rain", sea * (0.5 if weather == "overcast" and chop > 1.2 else 0.0))


func silence_ambience() -> void:
	for nm in LOOPS:
		loop_goal[nm] = 0.0


## Switch music with a cross-fade. "" stops it. Victory/defeat stingers play once and the
## previous track comes back quietly afterwards (or silence if `back` is "").
func music(track: String, back := "") -> void:
	if track == music_cur:
		return
	music_cur = track
	if track == "" or not ready_ok or not music_streams.has(track):
		return
	var nxt: AudioStreamPlayer = music_b if music_goal < 0.5 else music_a
	nxt.stream = music_streams[track]
	nxt.volume_db = -80.0
	nxt.play()
	music_goal = 1.0 if nxt == music_b else 0.0
	if track in ["victory", "defeat"]:
		sting_t = 0.0
		sting_back = back
	else:
		sting_t = -1.0


func _process(delta: float) -> void:
	if headless:
		return
	# ambience fades
	for nm in LOOPS:
		var p: AudioStreamPlayer = loops[nm]
		var cur := db_to_linear(p.volume_db) if p.volume_db > -79.0 else 0.0
		var goal: float = loop_goal[nm]
		cur = move_toward(cur, goal, delta * 0.6)
		p.volume_db = linear_to_db(cur) if cur > 0.001 else -80.0
	# music cross-fade: each player eases toward 1 (its turn) or 0
	var ta := 1.0 if (music_cur != "" and music_goal < 0.5) else 0.0
	var tb := 1.0 if (music_cur != "" and music_goal > 0.5) else 0.0
	_va = move_toward(_va, ta, delta / 2.5)
	_vb = move_toward(_vb, tb, delta / 2.5)
	music_a.volume_db = linear_to_db(_va * 0.8) if _va > 0.001 else -80.0
	music_b.volume_db = linear_to_db(_vb * 0.8) if _vb > 0.001 else -80.0
	if _va <= 0.001 and music_a.playing and ta == 0.0:
		music_a.stop()
	if _vb <= 0.001 and music_b.playing and tb == 0.0:
		music_b.stop()
	if sting_t >= 0.0:
		sting_t += delta
		if sting_t > 9.0:
			sting_t = -1.0
			music_cur = ""
			if sting_back != "":
				music(sting_back)


# ================================================================ synthesis: effects

func _wav(buf: PackedFloat32Array, rate: int, is_loop: bool) -> AudioStreamWAV:
	var n := buf.size()
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	var k := (0.92 / peak) if peak > 0.0 else 1.0
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * k, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if is_loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = n
	return w


## Deterministic noise so the cache is the same every time.
class Rng:
	var s: int = 12345
	func next() -> float:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		return float(s) / float(0x7fffffff) * 2.0 - 1.0


func _make_sound(nm: String) -> AudioStreamWAV:
	var r := Rng.new()
	r.s = hash(nm) & 0x7fffffff
	match nm:
		"gun_small": return _gun(r, 0.7, 2200.0, 5.0, 0.35, 95.0)
		"gun_medium": return _gun(r, 1.1, 1300.0, 3.2, 0.6, 70.0)
		"gun_large": return _gun(r, 2.2, 700.0, 1.6, 1.0, 48.0)
		"boom": return _boom(r, 2.2, 520.0, 1.7, 0.8)
		"boom_big": return _boom(r, 4.0, 300.0, 0.9, 1.0)
		"bomb": return _boom(r, 2.6, 800.0, 1.4, 0.9)
		"splash": return _splash(r)
		"torp": return _torp(r)
		"alarm": return _alarm()
		"flak": return _flak(r)
		"aa_bofors": return _bofors(r)
		"aa_mg": return _mgstream(r)
		"mg": return _mg(r)
		"dc": return _dc(r)
		"ping": return _ping()
		"click": return _click()
		"radio": return _radio(r)
		"creak": return _creak(r)
		"bell": return _bell()
		"plane": return _plane(r)
		"fire": return _fire(r)
		"ocean": return _ocean(r)
		"wind": return _wind(r)
		"rain": return _rain(r)
	return _click()


## Noise burst through two one-pole low-passes, plus a sine thump for the body.
func _gun(r: Rng, length: float, cutoff: float, decay: float, thump: float, thump_hz: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0; var lp2 := 0.0
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.004) * exp(-t * decay)
		lp += (r.next() - lp) * k
		lp2 += (lp - lp2) * k
		var th := sin(TAU * thump_hz * t * (1.0 - 0.4 * minf(1.0, t * 2.0))) * exp(-t * decay * 1.3) * thump
		b[i] = lp2 * 2.5 * env + th
	return _wav(b, RATE, false)


## Heavy flak burst heard from a distance: a muffled crump with a short tail.
func _flak(r: Rng) -> AudioStreamWAV:
	var n := int(0.9 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0; var lp2 := 0.0
	var k := 1.0 - exp(-TAU * 380.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.006) * exp(-t * 5.5)
		var x := r.next()
		lp += (x - lp) * k
		lp2 += (lp - lp2) * k
		b[i] = lp2 * 3.0 * env + sin(TAU * 110.0 * t) * exp(-t * 9.0) * 0.5
	return _wav(b, RATE, false)


## Bofors clip: four sharp pom-pom reports 0.11 s apart.
func _bofors(r: Rng) -> AudioStreamWAV:
	var n := int(0.8 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0
	var k := 1.0 - exp(-TAU * 1800.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var ph := fmod(t, 0.11)
		var shot := int(t / 0.11)
		var env := (minf(1.0, ph / 0.002) * exp(-ph * 28.0)) if shot < 4 else 0.0
		lp += (r.next() - lp) * k
		b[i] = lp * 2.2 * env + sin(TAU * 170.0 * ph) * exp(-ph * 40.0) * 0.45 * (1.0 if shot < 4 else 0.0)
	return _wav(b, RATE, false)


## Machine-gun stream: seven quick cracks.
func _mgstream(r: Rng) -> AudioStreamWAV:
	var n := int(0.55 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0
	var k := 1.0 - exp(-TAU * 3200.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var ph := fmod(t, 0.06)
		var shot := int(t / 0.06)
		var env := (minf(1.0, ph / 0.001) * exp(-ph * 70.0)) if shot < 7 else 0.0
		lp += (r.next() - lp) * k
		b[i] = lp * 2.4 * env
	return _wav(b, RATE, false)


## Explosion: crack, then a rumbling tail with a slow sub-bass sweep.
func _boom(r: Rng, length: float, cutoff: float, decay: float, sub: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0; var lp2 := 0.0; var rum := 0.0
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	var kr := 1.0 - exp(-TAU * 90.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.01) * exp(-t * decay)
		var tail := exp(-t * decay * 0.55) * (1.0 if t > 0.05 else t / 0.05)
		var x := r.next()
		lp += (x - lp) * k
		lp2 += (lp - lp2) * k
		rum += (x - rum) * kr
		var f := 55.0 - 25.0 * minf(1.0, t / 1.5)
		b[i] = lp2 * 2.0 * env + rum * 4.0 * tail + sin(TAU * f * t) * exp(-t * 1.6) * sub * 0.5
	return _wav(b, RATE, false)


func _splash(r: Rng) -> AudioStreamWAV:
	var n := int(1.1 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0; var hp_in := 0.0; var hp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.03) * exp(-t * 3.2)
		var cut := 3200.0 - 1800.0 * minf(1.0, t)
		var k := 1.0 - exp(-TAU * cut / RATE)
		var x := r.next()
		lp += (x - lp) * k
		hp = 0.98 * (hp + lp - hp_in); hp_in = lp
		var bubbles := sin(TAU * (180.0 + 60.0 * sin(t * 9.0)) * t) * 0.15 * exp(-t * 2.0) * (1.0 if t > 0.1 else 0.0)
		b[i] = (hp * 2.2 + bubbles) * env
	return _wav(b, RATE, false)


## Compressed-air launch: a clank, then a descending hiss.
func _torp(r: Rng) -> AudioStreamWAV:
	var n := int(1.3 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var cut := 4000.0 * exp(-t * 2.0) + 200.0
		var k := 1.0 - exp(-TAU * cut / RATE)
		lp += (r.next() - lp) * k
		var hiss := lp * 1.6 * minf(1.0, t / 0.05) * exp(-t * 2.2)
		var clank := (sin(TAU * 620.0 * t) + sin(TAU * 1480.0 * t) * 0.5) * exp(-t * 18.0) * 0.5
		b[i] = hiss + clank
	return _wav(b, RATE, false)


## General-quarters alarm: rapid square-wave bursts.
func _alarm() -> AudioStreamWAV:
	var n := int(1.6 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	for i in n:
		var t := float(i) / RATE
		var gate := 1.0 if fmod(t, 0.4) < 0.25 else 0.0
		var env := gate * minf(1.0, fmod(t, 0.4) / 0.01) * minf(1.0, (1.6 - t) / 0.05)
		var f := 540.0 + 25.0 * sin(TAU * 7.0 * t)
		var sq := 1.0 if sin(TAU * f * t) > 0.0 else -1.0
		b[i] = (sq * 0.6 + sin(TAU * f * 2.0 * t) * 0.2) * env * 0.5
	return _wav(b, RATE, false)


func _mg(r: Rng) -> AudioStreamWAV:
	var n := int(0.6 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0
	var k := 1.0 - exp(-TAU * 3000.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var ph := fmod(t, 0.09)
		var env := minf(1.0, ph / 0.002) * exp(-ph * 60.0)
		lp += (r.next() - lp) * k
		b[i] = lp * 2.4 * env + sin(TAU * 140.0 * ph) * exp(-ph * 70.0) * 0.3
	return _wav(b, RATE, false)


## Depth charge: a muffled thump felt through the hull, then a long rumble.
func _dc(r: Rng) -> AudioStreamWAV:
	var n := int(2.8 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0; var lp2 := 0.0
	var k := 1.0 - exp(-TAU * 140.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.03) * exp(-t * 1.4)
		var x := r.next()
		lp += (x - lp) * k
		lp2 += (lp - lp2) * k
		b[i] = lp2 * 6.0 * env + sin(TAU * (42.0 - 14.0 * minf(1.0, t)) * t) * exp(-t * 2.4) * 0.6
	return _wav(b, RATE, false)


func _ping() -> AudioStreamWAV:
	var n := int(1.4 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * 1480.0 * t) * minf(1.0, t / 0.01) * exp(-t * 7.0)
		var echo := 0.0
		if t > 0.5:
			echo = sin(TAU * 1480.0 * (t - 0.5)) * exp(-(t - 0.5) * 9.0) * 0.22
		b[i] = (s + echo) * 0.6
	return _wav(b, RATE, false)


func _click() -> AudioStreamWAV:
	var n := int(0.08 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	for i in n:
		var t := float(i) / RATE
		b[i] = sin(TAU * 1900.0 * t) * exp(-t * 90.0) * 0.5 + sin(TAU * 700.0 * t) * exp(-t * 60.0) * 0.3
	return _wav(b, RATE, false)


## Radio: a burst of static, then two message beeps.
func _radio(r: Rng) -> AudioStreamWAV:
	var n := int(1.1 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var bp_in := 0.0; var bp := 0.0; var lp := 0.0
	var k := 1.0 - exp(-TAU * 2500.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var x := r.next()
		lp += (x - lp) * k
		bp = 0.9 * (bp + lp - bp_in); bp_in = lp
		var st := bp * 1.4 * (1.0 if t < 0.35 else 0.0) * minf(1.0, t / 0.02) * (1.0 - t / 0.35 if t < 0.35 else 0.0)
		var beep := 0.0
		for t0 in [0.45, 0.72]:
			if t > t0 and t < t0 + 0.14:
				beep += sin(TAU * 1000.0 * t) * minf(1.0, (t - t0) / 0.01) * minf(1.0, (t0 + 0.14 - t) / 0.02) * 0.35
		b[i] = st + beep
	return _wav(b, RATE, false)


## Hull groan of a sinking ship: a bending low tone with noise and knocks.
func _creak(r: Rng) -> AudioStreamWAV:
	var n := int(3.5 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0
	var k := 1.0 - exp(-TAU * 400.0 / RATE)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 70.0 + 30.0 * sin(t * 1.3) - 12.0 * t
		ph += TAU * f / RATE
		var env := minf(1.0, t / 0.4) * minf(1.0, (3.5 - t) / 0.8)
		lp += (r.next() - lp) * k
		var tone := (sin(ph) + 0.5 * sin(2.0 * ph + 0.3) + 0.25 * sin(3.0 * ph)) * 0.35
		var knock := 0.0
		var kt := fmod(t + 0.3, 0.9)
		if kt < 0.15:
			knock = sin(TAU * 95.0 * kt) * exp(-kt * 30.0) * 0.4
		b[i] = (tone + lp * 0.5 + knock) * env
	return _wav(b, RATE, false)


func _bell() -> AudioStreamWAV:
	var n := int(2.5 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for p in [[1.0, 1.0, 1.2], [2.0, 0.6, 2.0], [2.98, 0.4, 2.6], [4.2, 0.25, 3.5], [5.4, 0.15, 4.5]]:
			s += sin(TAU * 780.0 * p[0] * t) * p[1] * exp(-t * p[2])
		b[i] = s * minf(1.0, t / 0.003) * 0.3
	return _wav(b, RATE, false)


## Radial engine drone (loop): sawtooth-ish harmonics with slow flutter.
func _plane(r: Rng) -> AudioStreamWAV:
	var n := int(2.0 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0
	var k := 1.0 - exp(-TAU * 900.0 / RATE)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		var f := 92.0
		for h in range(1, 9):
			s += sin(TAU * f * h * t) / h * (1.0 if h % 2 == 1 else 0.7)
		var flutter := 1.0 + 0.18 * sin(TAU * 3.0 * t) + 0.08 * sin(TAU * 7.5 * t)
		lp += (r.next() - lp) * k
		b[i] = (s * 0.3 * flutter + lp * 0.25)
	return _wav(b, RATE, true)


## Fire crackle (loop).
func _fire(r: Rng) -> AudioStreamWAV:
	var n := int(3.0 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0; var pop := 0.0
	var k := 1.0 - exp(-TAU * 1200.0 / RATE)
	for i in n:
		var x := r.next()
		lp += (x - lp) * k
		pop *= 0.995
		if absf(x) > 0.9992:
			pop = 1.0
		var roar := lp * (0.5 + 0.3 * sin(TAU * 0.7 * float(i) / RATE) + 0.2 * sin(TAU * 1.9 * float(i) / RATE))
		b[i] = roar + x * pop * 0.8
	return _wav(b, RATE, true)


## Sea (loop, 8 s): deep filtered noise with swells.
func _ocean(r: Rng) -> AudioStreamWAV:
	var n := int(8.0 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0; var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var swell := 0.55 + 0.3 * sin(TAU * t / 8.0) + 0.15 * sin(TAU * t / 8.0 * 3.0 + 1.0)
		var cut := 350.0 + 500.0 * swell
		var k := 1.0 - exp(-TAU * cut / RATE)
		lp += (r.next() - lp) * k
		lp2 += (lp - lp2) * k
		b[i] = lp2 * 3.0 * swell
	return _wav(b, RATE, true)


## Wind (loop, 8 s): band-passed noise sweeping slowly.
func _wind(r: Rng) -> AudioStreamWAV:
	var n := int(8.0 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var lp := 0.0; var hp := 0.0; var hp_in := 0.0
	for i in n:
		var t := float(i) / RATE
		var sweep := 0.5 + 0.5 * sin(TAU * t / 8.0 + 2.0) * sin(TAU * t / 8.0 * 2.0)
		var k := 1.0 - exp(-TAU * (500.0 + 900.0 * sweep) / RATE)
		lp += (r.next() - lp) * k
		hp = 0.995 * (hp + lp - hp_in); hp_in = lp
		b[i] = hp * 3.0 * (0.4 + 0.6 * sweep)
	return _wav(b, RATE, true)


func _rain(r: Rng) -> AudioStreamWAV:
	var n := int(4.0 * RATE)
	var b := PackedFloat32Array(); b.resize(n)
	var hp := 0.0; var hp_in := 0.0
	for i in n:
		var x := r.next()
		hp = 0.9 * (hp + x - hp_in); hp_in = x
		b[i] = hp * 0.6 + (x if absf(x) > 0.995 else 0.0) * 0.4
	return _wav(b, RATE, true)


# ================================================================ synthesis: music
# A small wavetable synth and five short compositions. Note numbers are MIDI (60 = middle C).

const TABLE := 2048

func _make_tables() -> void:
	for nm in ["pad", "brass", "bass", "sine", "bell"]:
		var t := PackedFloat32Array(); t.resize(TABLE)
		for i in TABLE:
			var ph := TAU * float(i) / TABLE
			var s := 0.0
			match nm:
				"pad":    # soft, hollow: odd harmonics falling fast
					for h in [1, 2, 3, 5]:
						s += sin(ph * h) / (h * h) * (1.0 if h != 2 else 0.5)
				"brass":  # bright saw-like
					for h in range(1, 13):
						s += sin(ph * h) / h
				"bass":
					s = sin(ph) + 0.4 * sin(2.0 * ph) + 0.1 * sin(3.0 * ph)
				"sine":
					s = sin(ph)
				"bell":
					s = sin(ph) + 0.5 * sin(2.0 * ph) + 0.3 * sin(2.76 * ph) + 0.2 * sin(5.4 * ph)
			t[i] = s
		var peak := 0.0
		for i in TABLE:
			peak = maxf(peak, absf(t[i]))
		for i in TABLE:
			t[i] /= peak
		_tables[nm] = t


## Bass an octave under the chord root, but never below about 45 Hz.
static func _bass_of(root: int) -> int:
	var n := root - 12
	while n < 31:
		n += 12
	return n


static func _hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Adds one note to `buf`: wavetable `tim`, start/duration in seconds, ADSR-ish envelope.
func _note(buf: PackedFloat32Array, tim: String, note: float, start: float, dur: float, vol: float,
		att := 0.05, rel := 0.3, detune := 0.0, vib := 0.0) -> void:
	var tab: PackedFloat32Array = _tables[tim]
	var n := buf.size()
	var i0 := int(start * MUSIC_RATE)
	var i1 := mini(n, int((start + dur + rel) * MUSIC_RATE))
	var f := _hz(note)
	var ph := 0.0
	var ph2 := 0.0
	var step := f * TABLE / MUSIC_RATE
	var step2 := _hz(note + detune) * TABLE / MUSIC_RATE
	var two := detune != 0.0
	for i in range(i0, i1):
		var t := float(i - i0) / MUSIC_RATE
		var env := minf(1.0, t / att)
		if t > dur:
			env *= maxf(0.0, 1.0 - (t - dur) / rel)
		var v := vib * sin(TAU * 5.0 * t) * minf(1.0, t / 0.6)
		ph = fmod(ph + step * (1.0 + v * 0.01), TABLE)
		var s := tab[int(ph)]
		if two:
			ph2 = fmod(ph2 + step2, TABLE)
			s = (s + tab[int(ph2)]) * 0.5
		buf[i] += s * env * vol


## Timpani-style thump: a sine falling in pitch.
func _drum(buf: PackedFloat32Array, start: float, vol: float, hz := 70.0) -> void:
	var i0 := int(start * MUSIC_RATE)
	var i1 := mini(buf.size(), i0 + int(0.9 * MUSIC_RATE))
	for i in range(i0, i1):
		var t := float(i - i0) / MUSIC_RATE
		buf[i] += sin(TAU * hz * (1.0 - 0.25 * minf(1.0, t * 3.0)) * t) * exp(-t * 4.5) * vol * minf(1.0, t / 0.004)


## Chord voicings by name (MIDI notes).
const CHORDS := {
	"Dm": [50, 57, 62, 65], "Bb": [46, 53, 58, 62], "F": [53, 57, 60, 65], "C": [48, 55, 60, 64],
	"Gm": [43, 50, 55, 58], "A": [45, 52, 57, 61], "Am": [45, 52, 57, 60], "D": [50, 57, 62, 66],
	"G": [43, 50, 55, 59], "Ebm": [51, 58, 63, 66], "D5": [38, 50, 57], "Eb5": [39, 51, 58],
	"Gmaj": [43, 55, 59, 62, 67], "Bbmaj7": [46, 53, 57, 60, 65],
}


func _make_track(tr: String) -> AudioStreamWAV:
	match tr:
		"menu": return _track_menu()
		"map": return _track_map()
		"battle": return _track_battle()
		"victory": return _track_sting(true)
		"defeat": return _track_sting(false)
	return _track_sting(false)


## Title theme, 64 s loop, D minor, 60 bpm: slow hymn-like pad with a brass melody.
func _track_menu() -> AudioStreamWAV:
	var bpm := 60.0
	var beat := 60.0 / bpm
	var bars := 16
	var len := bars * 4 * beat
	var buf := PackedFloat32Array(); buf.resize(int(len * MUSIC_RATE))
	var prog := ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A", "Dm", "F", "Bb", "C", "Gm", "Dm", "A", "Dm"]
	for b in bars:
		var ch: Array = CHORDS[prog[b]]
		var t0 := b * 4 * beat
		for k in ch.size():
			_note(buf, "pad", ch[k], t0, 4 * beat - 0.1, 0.11, 0.8, 1.2, 0.07)
		_note(buf, "bass", _bass_of(ch[0]), t0, 4 * beat - 0.2, 0.16, 0.05, 0.4)
	# melody: [note, start beat, length beats]; rests where there is no entry
	var mel := [[69, 2, 2], [72, 4, 3], [70, 7, 1], [69, 8, 2], [65, 10, 2], [67, 12, 4],
		[65, 18, 2], [67, 20, 2], [69, 22, 2], [72, 24, 3], [74, 27, 1], [73, 28, 4],
		[74, 34, 2], [77, 36, 3], [74, 39, 1], [72, 40, 2], [70, 42, 2], [69, 44, 4],
		[67, 50, 2], [65, 52, 2], [62, 54, 2], [64, 56, 3], [65, 59, 1], [62, 60, 4]]
	for m in mel:
		_note(buf, "brass", m[0], m[1] * beat, m[2] * beat - 0.15, 0.12, 0.25, 0.4, 0.0, 0.6)
		_note(buf, "brass", m[0] - 12, m[1] * beat, m[2] * beat - 0.15, 0.05, 0.3, 0.4)
	# a low drum on the first beat of every other bar
	for b in range(0, bars, 2):
		_drum(buf, b * 4 * beat, 0.25, 62.0)
	return _wav(buf, MUSIC_RATE, true)


## Operations map, 72 s loop: open fifths and sparse bell notes, like a long watch at sea.
func _track_map() -> AudioStreamWAV:
	var beat := 60.0 / 50.0
	var bars := 15
	var len := bars * 4 * beat
	var buf := PackedFloat32Array(); buf.resize(int(len * MUSIC_RATE))
	var prog := ["D5", "D5", "Bbmaj7", "D5", "Gmaj", "D5", "D5", "Eb5", "D5", "Bbmaj7", "Gmaj", "D5", "D5", "Am", "D5"]
	for b in bars:
		var ch: Array = CHORDS[prog[b]]
		var t0 := b * 4 * beat
		for k in ch.size():
			_note(buf, "pad", ch[k] + 12, t0, 4 * beat, 0.07, 1.5, 2.0, 0.05)
		_note(buf, "bass", _bass_of(ch[0]), t0, 4 * beat - 0.1, 0.1, 0.8, 1.5)
	var r := Rng.new(); r.s = 777
	var scale := [62, 65, 67, 69, 72, 74, 77]
	var t := 2.0
	while t < len - 4.0:
		var nt: int = scale[int((r.next() + 1.0) * 0.5 * scale.size()) % scale.size()]
		_note(buf, "bell", nt + 12, t, 2.5, 0.05, 0.005, 2.5)
		t += 2.4 + (r.next() + 1.0) * 2.2
	return _wav(buf, MUSIC_RATE, true)


## Battle, 38 s loop, 100 bpm: clashing drones, timpani pattern, brass stabs.
func _track_battle() -> AudioStreamWAV:
	var beat := 60.0 / 100.0
	var bars := 16
	var len := bars * 4 * beat
	var buf := PackedFloat32Array(); buf.resize(int(len * MUSIC_RATE))
	var prog := ["D5", "D5", "Eb5", "D5", "D5", "Gm", "Eb5", "A", "D5", "D5", "Eb5", "D5", "Bb", "Gm", "A", "D5"]
	for b in bars:
		var ch: Array = CHORDS[prog[b]]
		var t0 := b * 4 * beat
		for k in ch.size():
			_note(buf, "pad", ch[k], t0, 4 * beat, 0.08, 0.3, 0.5, 0.1)
		_note(buf, "bass", _bass_of(ch[0]), t0, 4 * beat, 0.14, 0.02, 0.3)
		# timpani: beats 1, 2.5, 4 and a roll into bar 8 and 16
		_drum(buf, t0, 0.32, 58.0)
		_drum(buf, t0 + 1.5 * beat, 0.2, 58.0)
		_drum(buf, t0 + 3 * beat, 0.26, 52.0)
		if b % 8 == 7:
			for i in 8:
				_drum(buf, t0 + (3.0 + i * 0.125) * beat, 0.12 + 0.02 * i, 58.0)
		# brass stabs on the off-beats of bars 5-8 and 13-16
		if (b % 8) >= 4:
			for k in [1, 2]:
				_note(buf, "brass", ch[k] + 12, t0 + 0.5 * beat, 0.3, 0.07, 0.01, 0.2)
				_note(buf, "brass", ch[k] + 12, t0 + 2.5 * beat, 0.3, 0.07, 0.01, 0.2)
			_note(buf, "brass", ch[0] + 12, t0 + 3.5 * beat, 0.3, 0.09, 0.01, 0.2)
	return _wav(buf, MUSIC_RATE, true)


## Stingers: a major resolution (victory) or a low minor swell (defeat), 8 s.
func _track_sting(won: bool) -> AudioStreamWAV:
	var len := 8.0
	var buf := PackedFloat32Array(); buf.resize(int(len * MUSIC_RATE))
	if won:
		for k in [[50, 0.0], [57, 0.5], [62, 1.0], [66, 1.5], [69, 2.0], [74, 2.5]]:
			_note(buf, "brass", k[0], k[1], 4.5 - k[1], 0.1, 0.1, 2.5, 0.0, 0.4)
			_note(buf, "pad", k[0], k[1], 4.5 - k[1], 0.08, 0.5, 2.5, 0.08)
		_drum(buf, 0.0, 0.3, 62.0)
		_drum(buf, 2.0, 0.35, 62.0)
		_note(buf, "bell", 86, 2.5, 3.0, 0.05, 0.005, 3.0)
	else:
		for k in CHORDS["Dm"]:
			_note(buf, "pad", k - 12, 0.0, 4.0, 0.12, 1.5, 3.0, 0.1)
		_note(buf, "bass", 38, 0.0, 4.5, 0.18, 0.5, 3.0)
		_note(buf, "brass", 65, 1.5, 2.0, 0.07, 0.6, 2.0, 0.0, 0.5)
		_note(buf, "brass", 64, 3.5, 1.5, 0.06, 0.6, 2.5, 0.0, 0.5)
		_drum(buf, 0.0, 0.3, 48.0)
	return _wav(buf, MUSIC_RATE, false)
