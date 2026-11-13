extends Node3D
## CHAPTER 1 — THE SIGNAL FROM MARS
## Plays res://chapter1_script.json (the same file the web version uses): ten shots across Meridian Mission
## Control (2110) and the Ares Research Station flashback (2080), then PAUSES on the mission choice.
## Nothing is chosen automatically: connect to `mission_selected` to continue your story.
##
## Keys: Space pause/resume · N next shot · B previous shot · L switch subtitles (ar/en) · R restart

signal mission_selected(mission_id: String)
signal shot_changed(number: int)

@export_file("*.json") var script_path := "res://chapter1_script.json"
@export var start_time := 0.0          ## start the film here (the script is fast-forwarded to this moment)
@export var autoplay := true
@export_enum("ar", "en") var subtitle_language := "ar"
@export var env_mc: Environment
@export var env_ares: Environment

@onready var cam: Camera3D = $Camera
@onready var mc: Node3D = $MissionControl
@onready var ares: Node3D = $Ares
@onready var ui: CanvasLayer = $UI
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun

var data: Dictionary
var T := 0.0
var ei := 0
var playing := false
var waiting := false
var world := ""
var actors := {}
var crowd: Array = []
var crew: Array = []
var sub: Dictionary = {}
var sub_until := 0.0
var trace_t := -1.0
var fade_from := Color(0, 0, 0, 0)
var fade_to := Color(0, 0, 0, 0)
var fade_t0 := 0.0
var fade_dur := 0.0
var ar_alarm := false
var ar_evac := false
var meteor_start := -1.0
var meteor_impact := -1.0
var _meteor: Node3D
var _fireball: MeshInstance3D
var _shock: MeshInstance3D
var _entry := Vector3(180, 140, -120)
var _impact := Vector3(40, 0, 3)
var _chapter := 0
var _cur_fov := 45.0

const CREW := [[7.2, 6.9, 0.3, [[8, 4.5], [8, 0]]], [9.0, 6.9, -0.3, [[8, 4.5], [8, 0]]], [13.9, 11.0, PI / 2, [[11, 8], [8.5, 3], [8, 0]]], [8.2, -5.4, PI, [[8, -2.5], [8, 0]]], [-6.2, -4.9, PI, [[-7, -2.5], [-7, 0]]], [16.8, -5.2, PI / 2, [[18.5, -2.5], [18.5, 0]]]]
const EXIT := [[-22, 0], [-29.2, 0], [-31.6, 0], [-33.2, -2.6], [-34.6, -6.5], [-36, -11]]


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(script_path))
	mc.set("_env", env_mc)
	mc.set("_ambient_normal", env_mc.ambient_light_color)
	ares.set("_env", env_ares)
	ares.set("_sun", sun)
	for id in data["actors"]:
		var a := CineActor.new()
		a.setup(id, load("res://assets/char_%s.glb" % id))
		add_child(a)
		actors[id] = a
	_spawn_crowd()
	_spawn_crew()
	_build_fx()
	ui.set_language(subtitle_language)
	ui.mission_chosen.connect(_on_mission_chosen)
	seek(start_time)
	playing = autoplay


# ------------------------------------------------------------------ playback control
func seek(t: float) -> void:
	## Replays the script silently from 0 to t so every actor and system lands exactly where the film is.
	T = 0.0
	ei = 0
	waiting = false
	sub = {}
	trace_t = -1.0
	fade_from = Color(0, 0, 0, 0)
	fade_to = Color(0, 0, 0, 0)
	fade_dur = 0.0
	ar_alarm = false
	ar_evac = false
	meteor_start = -1.0
	meteor_impact = -1.0
	ui.reset()
	for a in actors.values():
		(a as CineActor).path = []
		(a as CineActor).visible = true
		(a as CineActor).look_target = null
		(a as CineActor).gesture = "none"
		(a as CineActor).expr = "neutral"
		(a as CineActor).lean_target = 0.0
	mc.set_stage(0)
	mc.set_emergency(false)
	mc.set("_e", 0.0)
	mc.set_signal(false)
	mc.set_trace(-1.0)
	mc.set_wall_mode("planning")
	_reset_crew()
	_set_world("mc")
	while T < t - 0.0001:
		_tick(minf(1.0 / 30.0, t - T), true)
	if mc.get("emergency"):
		mc.set("_e", 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_SPACE:
			if not waiting:
				playing = not playing
		KEY_N:
			_jump(1)
		KEY_B:
			_jump(-1)
		KEY_L:
			subtitle_language = "en" if subtitle_language == "ar" else "ar"
			ui.set_language(subtitle_language)
		KEY_R:
			seek(0.0)
			playing = true


func _jump(dir: int) -> void:
	var chs: Array = data["chapters"]
	var idx := clampi(_chapter - 1 + dir, 0, chs.size() - 1)
	seek(float(chs[idx]["t"]) + 0.01)
	playing = true


# ------------------------------------------------------------------ the frame
func _process(delta: float) -> void:
	if playing and not waiting:
		_tick(minf(delta, 0.05), false)
	_camera(T)
	ui.update_overlays(T, _fade_color(), sub if T < sub_until else {}, data["actors"])


func _tick(dt: float, silent: bool) -> void:
	T += dt
	var evs: Array = data["events"]
	while ei < evs.size() and float(evs[ei]["t"]) <= T:
		_apply(evs[ei], silent)
		ei += 1
	for a in actors.values():
		var ca := a as CineActor
		ca.talking = not sub.is_empty() and sub.get("who", "") == ca.id and not sub.get("vo", false) and T < sub_until - 0.25
		ca.tick(dt, T, actors)
	_tick_crowd(dt)
	if trace_t >= 0.0:
		mc.set_trace(clampf((T - trace_t) / 8.0, 0.0, 1.0))
	_tick_ares(dt)
	var chs: Array = data["chapters"]
	var n := 1
	for c in chs:
		if T >= float(c["t"]):
			n = int(c["n"])
	if n != _chapter:
		_chapter = n
		shot_changed.emit(n)


func _apply(e: Dictionary, silent: bool) -> void:
	var t := float(e["t"])
	if e.has("world"):
		_set_world(e["world"])
	match String(e.get("mc", "")):
		"stage": mc.set_stage(int(e["v"]))
		"emergency": mc.set_emergency(int(e["v"]) == 1)
		"signal": mc.set_signal(int(e["v"]) == 1)
		"trace": trace_t = t
		"wall": mc.set_wall_mode(String(e["v"]))
		"highlight": mc.set_wall_mode("missions", String(e["v"]))
	if e.has("crowd"):
		_crowd_mode(String(e["crowd"]), t)
	match String(e.get("ares", "")):
		"reset": _reset_crew()
		"alarm": ar_alarm = int(e["v"]) == 1
		"evac": ar_evac = true
		"power": ares.set_power(float(e["v"]))
		"meteor":
			meteor_start = float(e["start"])
			meteor_impact = float(e["impact"])
	if e.has("a") and actors.has(e["a"]):
		(actors[e["a"]] as CineActor).command(e, t)
	if e.has("sub"):
		sub = e["sub"]
		sub_until = t + float(sub["dur"])
	if e.has("card"):
		ui.show_card(e["card"], t)
	if e.has("fade"):
		fade_from = _fade_color()
		var c: Array = e["fade"]["to"]
		fade_to = Color(c[0], c[1], c[2], c[3])
		fade_t0 = t
		fade_dur = float(e["fade"]["dur"])
	if e.has("pause") and not silent:
		waiting = true
		ui.show_choice(data["missions"])


func _fade_color() -> Color:
	var u := clampf((T - fade_t0) / fade_dur, 0.0, 1.0) if fade_dur > 0.0 else 1.0
	return fade_from.lerp(fade_to, u)


func _set_world(w: String) -> void:
	world = w
	mc.visible = w == "mc"
	ares.visible = w != "mc"
	sun.visible = w != "mc"
	world_env.environment = env_mc if w == "mc" else env_ares
	if w != "mc":
		ares.set_state("intact" if w == "ares_intact" else "ruined")
	for c in crew:
		(c["node"] as Node3D).visible = w == "ares_intact" and c["leg"] < 99
	for a in actors.values():
		(a as CineActor).model.visible = w == "mc"
	for p in crowd:
		(p["node"] as Node3D).visible = w == "mc"


func _camera(t: float) -> void:
	var shots: Array = data["shots"]
	var s: Dictionary = shots[0]
	for sh in shots:
		if t >= float(sh["t0"]):
			s = sh
	var span := maxf(0.001, float(s["t1"]) - float(s["t0"]))
	var u := clampf((t - float(s["t0"])) / span, 0.0, 1.0)
	if s["ease"] != "linear":
		u = u * u * (3.0 - 2.0 * u)
	var p := _v(s["from"]).lerp(_v(s["to"]), u)
	var l := _v(s["look"]).lerp(_v(s["lookTo"]), u)
	if s.get("lookActor") != null and actors.has(s["lookActor"]):
		l = (actors[s["lookActor"]] as CineActor).head_world()
	var shake := float(s["shake"])
	if meteor_impact > 0.0 and world != "mc":
		var ti := t - meteor_impact
		if world == "ares_intact" and ti > -3.0 and ti < 0.0:
			shake = maxf(shake, 0.03)
		if ti > 0.0 and ti < 3.0:
			shake = maxf(shake, 0.6 * (1.0 - ti / 3.0))
	if shake > 0.0:
		p += Vector3(sin(t * 37.1), sin(t * 29.3 + 1.0), 0.0) * shake
	cam.global_position = p
	if not p.is_equal_approx(l):
		cam.look_at(l, Vector3.UP)
	cam.fov = float(s["fov"])


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _on_mission_chosen(id: String) -> void:
	mc.set_wall_mode("missions", "chosen_" + ("A" if id.begins_with("EOS") else "B"))
	mission_selected.emit(id)


# ------------------------------------------------------------------ mission control crowd
func _spawn_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var scenes := []
	for i in 4:
		scenes.append(load("res://assets/char_crowd_%d.glb" % i))
	for n in mc.find_children("Workstation_R*", "Node3D", true, false):
		var nm := String(n.name)
		if nm.contains("SIGNAL") or not (n as Node3D).find_child("Chair_*", false, false):
			continue
		if rng.randf() < 0.3:
			continue
		var h: Node3D = (scenes[rng.randi() % 4] as PackedScene).instantiate()
		add_child(h)
		var ws := n as Node3D
		var bones := {}
		for bn in ["Hip_L", "Hip_R", "Knee_L", "Knee_R", "Shoulder_L", "Shoulder_R", "Elbow_L", "Elbow_R", "Head", "Mouth"]:
			bones[bn] = h.find_child(bn, true, false)
		crowd.append({"b": bones, "node": h, "ws": ws.global_position, "th": ws.global_rotation.y, "rnd": rng.randf(), "rnd2": rng.randf(), "stand": 0.0, "stand_t": 0.0, "at": 0.0, "mode": "work", "look": 0.0, "talk": false})


func _crowd_mode(mode: String, t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t * 10.0)
	for p in crowd:
		p["mode"] = mode
		p["at"] = t + rng.randf() * 3.0
		if mode == "panic":
			p["stand_t"] = 1.0 if p["rnd"] < 0.55 else 0.0
			p["look"] = 1.0
			p["talk"] = p["rnd2"] < 0.6
		elif mode == "calm":
			p["stand_t"] = 1.0 if p["rnd"] < 0.25 else 0.0
			p["look"] = 1.0 if p["rnd"] < 0.4 else 0.0
			p["talk"] = false
		else:
			p["stand_t"] = 0.0
			p["look"] = 0.0
			p["talk"] = false


func _tick_crowd(dt: float) -> void:
	for p in crowd:
		var h := p["node"] as Node3D
		var B: Dictionary = p["b"]
		var active: bool = T >= p["at"]
		var goal: float = p["stand_t"] if active else p["stand"]
		p["stand"] = p["stand"] + clampf(goal - p["stand"], -dt * 1.2, dt * 1.2)
		var st: float = p["stand"]
		var th: float = p["th"]
		var back := 0.84 + 0.45 * st
		var w: Vector3 = p["ws"]
		h.position = Vector3(w.x + back * sin(th), -0.33 * (1.0 - st), w.z + back * cos(th))
		h.rotation.y = th + PI + ((p["rnd"] - 0.5) * 0.6 * st if active and p["look"] > 0.0 else 0.0)
		for n in ["Hip_L", "Hip_R"]:
			var b := B[n] as Node3D
			if b: b.rotation.x = -1.5 * (1.0 - st)
		for n in ["Knee_L", "Knee_R"]:
			var b := B[n] as Node3D
			if b: b.rotation.x = 1.45 * (1.0 - st)
		var typing: bool = not (active and p["mode"] == "panic") and st < 0.3
		for n in ["Shoulder_L", "Shoulder_R"]:
			var b := B[n] as Node3D
			if b: b.rotation.x = -0.75 if typing else lerpf(-0.5, -0.1, st)
		var i := 0
		for n in ["Elbow_L", "Elbow_R"]:
			var b := B[n] as Node3D
			if b: b.rotation.x = (-0.8 + sin(T * 7.0 + i + p["rnd"] * 9.0) * 0.06) if typing else lerpf(-0.9, -0.3, st)
			i += 1
		var head := B["Head"] as Node3D
		if head:
			var want := 0.0
			if active and p["look"] > 0.0:
				want = clampf(angle_difference(h.rotation.y, atan2(-h.position.x, -20.0 - h.position.z)), -1.1, 1.1) * (1.0 if p["rnd2"] < 0.5 else 0.4)
			head.rotation.y = lerpf(head.rotation.y, want, minf(1.0, dt * 3.0))
			head.rotation.x = -0.15 if active and p["look"] > 0.0 else 0.1
		var mouth := B["Mouth"] as Node3D
		if mouth:
			mouth.scale.y = 1.0 + 2.0 * absf(sin(T * 10.0 + p["rnd"] * 20.0)) if active and p["talk"] else 1.0


# ------------------------------------------------------------------ Ares flashback
func _spawn_crew() -> void:
	var scene: PackedScene = load("res://assets/crew_member.glb")
	for c in CREW:
		var n: Node3D = scene.instantiate()
		add_child(n)
		n.add_to_group("door_openers")
		crew.append({"node": n, "def": c, "leg": 0, "phase": 0.0, "path": []})


func _reset_crew() -> void:
	for c in crew:
		var d: Array = c["def"]
		var n := c["node"] as Node3D
		n.position = Vector3(d[0], 0.15, d[1])
		n.rotation.y = d[2]
		var p: Array = (d[3] as Array).duplicate(true)
		p.append_array(EXIT)
		c["path"] = p
		c["leg"] = 0
		for s in ["Shoulder_L", "Shoulder_R"]:
			var b := n.find_child(s, true, false) as Node3D
			if b: b.rotation.x = -0.6
	ar_alarm = false
	ar_evac = false
	ares.set_power(1.0)
	ares.set_alarm(false)


func _build_fx() -> void:
	_meteor = Node3D.new()
	add_child(_meteor)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.2
	sm.height = 6.4
	core.mesh = sm
	core.material_override = _unshaded(Color(1.0, 0.82, 0.55, 1.0), false)
	_meteor.add_child(core)
	var tm := _unshaded(Color(1.0, 0.62, 0.3, 0.35), true)
	var dir := (_entry - _impact).normalized()
	for i in 22:
		var s := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = maxf(0.8, 5.5 - i * 0.2)
		sp.height = sp.radius * 2.0
		s.mesh = sp
		s.material_override = tm
		s.position = dir * ((i + 1) * 2.6)
		_meteor.add_child(s)
	_meteor.visible = false
	_fireball = MeshInstance3D.new()
	_fireball.mesh = SphereMesh.new()
	_fireball.material_override = _unshaded(Color(1.0, 0.7, 0.35, 0.9), true)
	_fireball.visible = false
	add_child(_fireball)
	_shock = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.92
	ring.outer_radius = 1.0
	ring.rings = 64
	_shock.mesh = ring
	_shock.material_override = _unshaded(Color(0.8, 0.55, 0.38, 0.7), true)
	_shock.visible = false
	add_child(_shock)


func _unshaded(c: Color, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _tick_ares(dt: float) -> void:
	if world == "ares_intact":
		ares.set_alarm(ar_alarm)
		for i in crew.size():
			var c: Dictionary = crew[i]
			var n := c["node"] as Node3D
			if not ar_evac:
				continue
			var path: Array = c["path"]
			if c["leg"] >= path.size():
				n.visible = false
				c["leg"] = 99
				continue
			if c["leg"] == 99:
				continue
			var tg: Array = path[c["leg"]]
			var to := Vector2(float(tg[0]) - n.position.x, float(tg[1]) - n.position.z)
			var d := to.length()
			var sp := 3.1 + (i % 3) * 0.25
			if d < 0.25:
				c["leg"] += 1
				continue
			n.position.x += to.x / d * sp * dt
			n.position.z += to.y / d * sp * dt
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.y), minf(1.0, dt * 10.0))
			c["phase"] += dt * sp * 4.0
			var sw := sin(c["phase"]) * 0.55
			var hl := n.find_child("Hip_L", true, false) as Node3D
			var hr := n.find_child("Hip_R", true, false) as Node3D
			if hl: hl.rotation.x = sw
			if hr: hr.rotation.x = -sw
	if meteor_impact > 0.0:
		var ti := T - meteor_impact
		_meteor.visible = T > meteor_start and ti < 0.0 and world == "ares_intact"
		if _meteor.visible:
			_meteor.position = _entry.lerp(_impact, pow((T - meteor_start) / (meteor_impact - meteor_start), 2.2))
		if ti >= 0.0 and world == "ares_intact":
			_set_world("ares_ruined")
			_fireball.position = _impact
			_shock.position = _impact + Vector3(0, 0.4, 0)
		var on := ti > 0.0 and ti < 3.4
		_fireball.visible = on
		_shock.visible = on
		if on:
			_fireball.scale = Vector3.ONE * (4.0 + ti * 16.0)
			(_fireball.material_override as StandardMaterial3D).albedo_color.a = maxf(0.0, 0.95 - ti * 0.3)
			_shock.scale = Vector3(1, 0.05, 1) * (4.0 + ti * 55.0)
			(_shock.material_override as StandardMaterial3D).albedo_color.a = maxf(0.0, 0.7 - ti * 0.21)
		ui.set_flash(1.0 - ti / 1.4 if ti > 0.0 and ti < 1.4 else 0.0)
	else:
		_meteor.visible = false
		ui.set_flash(0.0)
