class_name Sfx
extends Node
## Placeholder sound effects made in code (no audio files needed yet).
## Replace these later with real recordings: put .wav or .ogg files in
## res://assets/sounds/ named gun, boom, splash, torp, alarm and they are used instead.

const RATE := 22050
var streams := {}
var players: Array = []
var enabled := true


func _ready() -> void:
	streams["gun"] = _make(0.9, 0.012, 3.5, 900.0, 0.95)
	streams["boom"] = _make(2.4, 0.02, 1.5, 420.0, 1.0)
	streams["splash"] = _make(0.8, 0.03, 4.0, 2600.0, 0.5)
	streams["torp"] = _make(0.6, 0.01, 5.0, 300.0, 0.6)
	streams["alarm"] = _tone(0.7, 520.0)
	for nm in ["gun", "boom", "splash", "torp", "alarm"]:
		for ext in ["wav", "ogg"]:
			var path := "res://assets/sounds/%s.%s" % [nm, ext]
			if ResourceLoader.exists(path):
				streams[nm] = load(path)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)


## Noise burst with a fast attack and exponential decay, low-pass filtered.
func _make(length: float, attack: float, decay: float, cutoff: float, gain: float) -> AudioStreamWAV:
	var count := int(length * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	var lp2 := 0.0
	var k := 1.0 - exp(-TAU * cutoff / RATE)
	var rumble := 0.0
	for i in count:
		var t := float(i) / RATE
		var env := minf(1.0, t / attack) * exp(-t * decay)
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * k
		lp2 += (lp - lp2) * k
		rumble += ((randf() * 2.0 - 1.0) - rumble) * 0.004
		var s := (lp2 * 2.2 + rumble * 6.0) * env * gain
		var iv := int(clampf(s, -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, iv)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _tone(length: float, freq: float) -> AudioStreamWAV:
	var count := int(length * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.02) * minf(1.0, (length - t) / 0.05)
		var s := (1.0 if sin(TAU * freq * t) > 0.0 else -1.0) * 0.18 * env
		data.encode_s16(i * 2, int(s * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


## Play a sound at a world position; volume falls off with distance from the camera.
func play(nm: String, pos: Vector2, cam: Vector3, vol := 1.0) -> void:
	if not enabled or not streams.has(nm):
		return
	var d := Vector2(pos.x - cam.x, pos.y - cam.z).length() + cam.y * 0.4
	var g := vol / (1.0 + d / 900.0)
	if g < 0.03:
		return
	for p in players:
		if not p.playing:
			p.stream = streams[nm]
			p.volume_db = linear_to_db(clampf(g, 0.0, 1.5))
			p.pitch_scale = randf_range(0.92, 1.08)
			p.play()
			return
