class_name Sfx
extends Node
## The battle's sound hooks. All sounds live in the `Audio` autoload (scripts/audio.gd);
## this node adds what the battle knows: positions, the weather, which ship is burning,
## where the planes are, and the "Sound on/off" switch on the HUD.

var enabled := true
var B                      # the Battle
var _ping_t := 0.0
var _drone := 0.0


## Play a named effect at a world position (x, z); volume falls off with camera distance.
func play(nm: String, pos: Vector2, cam: Vector3, vol := 1.0) -> void:
	if not enabled:
		return
	Audio.at(nm, pos, cam, vol)


## Gun report by calibre: `sz` is the mount's size factor (1.0 = a 5-inch mount).
func gun(sz: float, pos: Vector2, cam: Vector3) -> void:
	var nm := "gun_small" if sz < 0.5 else ("gun_medium" if sz < 1.3 else "gun_large")
	play(nm, pos, cam, 0.7 + 0.3 * minf(sz, 2.0))


## Called every frame by the battle: ambience, fire crackle, engine drone, sonar pings.
func step(dt: float) -> void:
	if B == null or Audio.headless:
		return
	if not enabled:
		Audio.silence_ambience()
		return
	Audio.ambience(B.weather)
	var cam: Vector3 = B.cam.position
	var p: Ship = B.player
	# fire on the player's ship, or a burning ship close under the camera
	var fire := 0.0
	for s in B.ships:
		if not s.alive or s.fires.is_empty():
			continue
		var d: float = Vector2(s.x - cam.x, s.z - cam.z).length() + cam.y * 0.4
		fire = maxf(fire, minf(1.0, 0.25 * s.fires.size()) / (1.0 + d / 500.0))
	Audio.loop("fire", fire * 0.8)
	# nearest airborne squadron
	var near := 1e9
	if B.air:
		for sq in B.air.sqs:
			if sq.state in ["ready", "landing", "lost"]:
				continue
			var d: float = Vector2(sq.x - cam.x, sq.z - cam.z).length() + absf(sq.alt - cam.y) * 0.5
			near = minf(near, d / maxf(1.0, sqrt(sq.n / 6.0)))
	var goal := clampf(1.0 - near / 2200.0, 0.0, 1.0) * 0.5
	_drone = move_toward(_drone, goal, dt * 0.5)
	Audio.loop("plane", _drone)
	# the player's sonar pings while hunting (or an escort pinging a submerged player)
	if p and p.alive and p.sonar_range() > 0.0 and not p.is_sub() and not p.sonar_contacts.is_empty():
		_ping_t -= dt
		if _ping_t <= 0.0:
			_ping_t = 3.5
			Audio.ui("ping", 0.35)
	elif p and p.is_sub() and p.submerged():
		_ping_t -= dt
		if _ping_t <= 0.0:
			_ping_t = 6.0
			for s in B.ships:
				if s.team != p.team and s.alive and s.sonar_contacts.has(p.ship_name):
					Audio.ui("ping", 0.5)
					break


func quiet() -> void:
	Audio.silence_ambience()
	Audio.loop("fire", 0.0)
	Audio.loop("plane", 0.0)
