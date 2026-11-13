extends SceneTree
## Headless smoke test: plays the whole chapter through the real interpreter and checks the key beats.

var ch: Node
var frame := 0
var log_worlds := []
var chapters := []
var picked := ""

func _initialize() -> void:
	ch = (load("res://main.tscn") as PackedScene).instantiate()
	ch.autoplay = false
	root.add_child(ch)
	ch.shot_changed.connect(func(n): chapters.append([n, snappedf(ch.T, 0.1)]))
	ch.mission_selected.connect(func(id): picked = id)

func _physics_process(_d: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	var last_world := ""
	var checks := {}
	while not ch.waiting and ch.T < 190.0:
		ch._tick(1.0 / 30.0, false)
		if ch.world != last_world:
			log_worlds.append([ch.world, snappedf(ch.T, 0.1)])
			last_world = ch.world
		for probe in [30.0, 60.0, 90.0, 115.0, 160.0, 179.0]:
			if not checks.has(probe) and ch.T >= probe:
				checks[probe] = true
				var n: CineActor = ch.actors["nolan"]
				var d: CineActor = ch.actors["director"]
				print("t=%5.1f world=%s stage=%d emerg=%s nolan=%s dir=%s" % [ch.T, ch.world, ch.mc.stage, ch.mc.emergency, n.pos.snapped(Vector3.ONE * 0.01), d.pos.snapped(Vector3.ONE * 0.01)])
	print("worlds: ", log_worlds)
	print("chapters: ", chapters)
	print("paused at mission select: ", ch.waiting, " T=", snappedf(ch.T, 0.01), " choice panel visible=", ch.ui._choice.visible)
	print("crowd=", ch.crowd.size(), " crew=", ch.crew.size())
	var before: float = ch.T
	for i in 60:
		ch._process(1.0 / 30.0)
	print("story held (no auto-continue): ", is_equal_approx(before, ch.T))
	ch.ui._pick(ch.data["missions"][1])
	print("mission_selected emitted: ", picked)
	ch.seek(150.0)
	print("seek(150) -> world=", ch.world, " T=", snappedf(ch.T, 0.01))
	return true
