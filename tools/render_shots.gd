extends SceneTree
## Renders key frames of the chapter to user://renders (run with a display, e.g. xvfb-run).
const TIMES := [6.0, 22.0, 40.0, 50.0, 56.6, 63.0, 77.0, 92.0, 99.0, 110.0, 126.0, 139.0, 150.0, 166.0, 181.0]
var ch: Node
var i := -1
var wait := 0

func _initialize() -> void:
	ch = (load("res://main.tscn") as PackedScene).instantiate()
	ch.autoplay = false
	root.add_child(ch)
	DirAccess.make_dir_recursive_absolute("user://renders")

func _process(_d: float) -> bool:
	if wait > 0:
		wait -= 1
		if wait == 0:
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("user://renders/shot_%03d.png" % int(TIMES[i] * 10))
			print("saved ", TIMES[i])
		return false
	i += 1
	if i >= TIMES.size():
		return true
	var t: float = TIMES[i]
	# advance the film from where it is (faster than seeking from 0 each time)
	while ch.T < minf(t, 179.5):
		ch._tick(minf(1.0 / 30.0, t - ch.T), t > 180.0)
	if t > 180.0:
		while not ch.waiting:
			ch._tick(1.0 / 30.0, false)
	wait = 30
	return false
