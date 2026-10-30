class_name U
## Small math helpers shared by every script.
## World axes: x = east, z = south, y = up. Headings are clockwise radians from north (-z).

static func rnd(a: float, b: float) -> float:
	return randf_range(a, b)

## Normal-distributed random number (mean 0, deviation 1).
static func gauss() -> float:
	return sqrt(-2.0 * log(maxf(randf(), 1e-9))) * cos(TAU * randf())

## Signed smallest difference from angle a to angle b, in -PI..PI.
static func ang_d(a: float, b: float) -> float:
	return fposmod(b - a + PI, TAU) - PI

static func hyp(x: float, z: float) -> float:
	return sqrt(x * x + z * z)

## Unit vector (x, z) pointing along heading h.
static func fwd(h: float) -> Vector2:
	return Vector2(sin(h), -cos(h))

## Compass bearing from (ax, az) to (bx, bz).
static func bearing(ax: float, az: float, bx: float, bz: float) -> float:
	return atan2(bx - ax, -(bz - az))

static func deg3(a: float) -> String:
	var d := int(round(fposmod(rad_to_deg(a), 360.0))) % 360
	return "%03d" % d

static func yards(m: float) -> String:
	var y := int(round(m / Data.YD / 100.0)) * 100
	if y >= 1000:
		return "%d,%03d yd" % [y / 1000, y % 1000]
	return "%d yd" % y
