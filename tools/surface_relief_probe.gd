extends SceneTree

## Measures whether rendered frames actually carry sub-polygon surface variation.
##
## Run against one capture directory:
##   ./tools/godot --headless --script tools/surface_relief_probe.gd -- <dir>
## Or against two, to report the delta between them:
##   ./tools/godot --headless --script tools/surface_relief_probe.gd -- <a> <b>
##
## An untextured primitive is shaded once per face, so every interior pixel of
## that face carries the same luminance and the high-frequency energy of the
## image collapses to the silhouettes. Micro-relief puts variation back inside
## the faces. That makes "is there surface detail" a measurable claim rather
## than an aesthetic one: take the mean absolute Laplacian over the interior of
## the frame and compare.
##
## HUD overlays are flat-shaded UI and would dilute the measurement unevenly, so
## the sampled window excludes the top and bottom bands where the HUD draws.

const HUD_TOP := 0.10
const HUD_BOTTOM := 0.86
const MIN_RELIEF := 0.0025


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: surface_relief_probe.gd -- <dir> [<dir_b>]")
		quit(2)
		return

	var first := _scan(args[0])
	if first.is_empty():
		push_error("no capture PNGs found in %s" % args[0])
		quit(2)
		return

	if args.size() == 1:
		_report_single(args[0], first)
		return
	_report_delta(args[0], first, args[1], _scan(args[1]))


func _report_single(label: String, scores: Dictionary) -> void:
	print("relief energy in ", label)
	var total := 0.0
	var failures := 0
	for name in scores:
		var value: float = scores[name]
		total += value
		var flag := "ok  "
		if value < MIN_RELIEF:
			flag = "FLAT"
			failures += 1
		print("  %s %-38s %.5f" % [flag, name, value])
	print("mean %.5f over %d frames" % [total / float(scores.size()), scores.size()])
	if failures > 0:
		print("SURFACE_RELIEF_FAILED flat=", failures)
		quit(1)
		return
	print("SURFACE_RELIEF_OK")
	quit(0)


func _report_delta(
		label_a: String,
		a: Dictionary,
		label_b: String,
		b: Dictionary
) -> void:
	if b.is_empty():
		push_error("no capture PNGs found in %s" % label_b)
		quit(2)
		return
	print("relief energy: ", label_a, " -> ", label_b)
	var gained := 0
	var compared := 0
	var sum_a := 0.0
	var sum_b := 0.0
	for name in a:
		if not b.has(name):
			continue
		var va: float = a[name]
		var vb: float = b[name]
		compared += 1
		sum_a += va
		sum_b += vb
		if vb > va:
			gained += 1
		print("  %-38s %.5f -> %.5f  (%+.1f%%)" % [
			name, va, vb, _percent(va, vb)
		])
	if compared == 0:
		push_error("no frames in common between the two directories")
		quit(2)
		return
	var mean_a := sum_a / float(compared)
	var mean_b := sum_b / float(compared)
	print("mean %.5f -> %.5f  (%+.1f%%) over %d frames, %d gained" % [
		mean_a, mean_b, _percent(mean_a, mean_b), compared, gained
	])
	print("SURFACE_RELIEF_DELTA_OK")
	quit(0)


func _percent(from_value: float, to_value: float) -> float:
	if absf(from_value) < 0.000001:
		return 0.0
	return (to_value - from_value) / from_value * 100.0


func _scan(dir_path: String) -> Dictionary:
	var scores := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return scores
	var names := dir.get_files()
	names.sort()
	for name in names:
		if not name.ends_with(".png"):
			continue
		var image := Image.load_from_file(dir_path.path_join(name))
		if image == null:
			continue
		scores[name] = _relief_energy(image)
	return scores


## Mean absolute discrete Laplacian of luminance. Sampling every second pixel:
## the statistic is stable well before a full sweep and the frames are large.
func _relief_energy(image: Image) -> float:
	if image.is_compressed():
		image.decompress()
	var width := image.get_width()
	var height := image.get_height()
	var y0 := maxi(1, int(float(height) * HUD_TOP))
	var y1 := mini(height - 1, int(float(height) * HUD_BOTTOM))
	if width < 3 or y1 - y0 < 3:
		return 0.0
	var total := 0.0
	var count := 0
	var y := y0
	while y < y1:
		var x := 1
		while x < width - 1:
			var centre := _luma(image, x, y)
			var lap := (
				_luma(image, x - 1, y)
				+ _luma(image, x + 1, y)
				+ _luma(image, x, y - 1)
				+ _luma(image, x, y + 1)
				- 4.0 * centre
			)
			total += absf(lap)
			count += 1
			x += 2
		y += 2
	if count == 0:
		return 0.0
	return total / float(count)


func _luma(image: Image, x: int, y: int) -> float:
	var c := image.get_pixel(x, y)
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
