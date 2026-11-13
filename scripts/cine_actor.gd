extends Node3D
class_name CineActor
## A scripted performer for cinematics: walks paths, turns, sits, leans, looks at people or points,
## gestures (type / raise / point / nod / glass), shows simple expressions, blinks and lip-flaps while talking.
## The model is any character GLB built with the project's rig (Hip/Knee/Shoulder/Elbow _L/_R, Upper, Head, Eye, Brow, Mouth).

var id := ""
var model: Node3D
var pos := Vector3.ZERO
var face := 0.0
var face_target := NAN
var path: Array = []
var speed := 1.0
var end_face := NAN
var sit := 0.0
var sit_target := 0.0
var lean := 0.0
var lean_target := 0.0
var look_target: Variant = null   # String (actor id), Vector3, or null
var gesture := "none"
var gesture_t := 0.0
var expr := "neutral"
var talking := false
var _hy := 0.0
var _hp := 0.0
var _phase := 0.0
var _moving := 0.0
var _blink := 3.0
var _b := {}

const EXPR := {"neutral": [0.0, 0.0, 1.0], "surprised": [0.007, 0.0, 1.25], "serious": [-0.003, 0.2, 0.92], "thoughtful": [-0.002, 0.1, 0.82]}


func setup(actor_id: String, scene: PackedScene) -> void:
	id = actor_id
	name = actor_id
	model = scene.instantiate()
	add_child(model)
	for n in ["Hip_R", "Hip_L", "Knee_R", "Knee_L", "Shoulder_R", "Shoulder_L", "Elbow_R", "Elbow_L", "Upper", "Head", "Eye_R", "Eye_L", "Brow_R", "Brow_L", "Mouth"]:
		_b[n] = model.find_child(n, true, false)
	add_to_group("door_openers")
	_blink = randf_range(2.0, 4.5)


func head_world() -> Vector3:
	return Vector3(pos.x, pos.y + 1.62 - lean * 0.35, pos.z)


func command(e: Dictionary, t: float) -> void:
	match String(e.get("do", "")):
		"place":
			var p: Array = e["pos"]
			pos = Vector3(p[0], p[1], p[2])
			face = float(e.get("face", face))
			face_target = NAN
			path = []
		"walk":
			path = (e["path"] as Array).duplicate(true)
			speed = float(e["speed"])
			end_face = float(e["face"]) if e.has("face") and e["face"] != null else NAN
		"sit":
			sit_target = float(e["v"])
			sit = sit_target
		"lean":
			lean_target = float(e["v"])
		"look":
			var at: Variant = e.get("at")
			if at is Array:
				look_target = Vector3(at[0], at[1], at[2])
			else:
				look_target = at
		"face":
			face_target = float(e["v"])
		"gesture":
			gesture = String(e["v"])
			gesture_t = t
		"expr":
			expr = String(e["v"])
		"hide":
			visible = false
		"show":
			visible = true


func tick(dt: float, t: float, actors: Dictionary) -> void:
	# locomotion
	if not path.is_empty():
		var target: Array = path[0]
		var to := Vector2(float(target[0]) - pos.x, float(target[1]) - pos.z)
		var d := to.length()
		if d < 0.04:
			path.pop_front()
			if path.is_empty() and not is_nan(end_face):
				face_target = end_face
		else:
			var st := minf(d, speed * dt)
			pos.x += to.x / d * st
			pos.z += to.y / d * st
			face_target = atan2(to.x, to.y)
			_moving = minf(1.0, _moving + dt * 4.0)
			_phase += dt * speed * 4.4
	else:
		_moving = maxf(0.0, _moving - dt * 4.0)
	if not is_nan(face_target):
		var a := angle_difference(face, face_target)
		face += signf(a) * minf(absf(a), dt * (5.0 if not path.is_empty() else 3.0))
	sit += (sit_target - sit) * minf(1.0, dt * 3.0)
	lean += (lean_target - lean) * minf(1.0, dt * 3.0)
	# head look
	var ty := 0.0
	var tp := 0.0
	var tgt: Variant = null
	if look_target is String and actors.has(look_target):
		tgt = (actors[look_target] as CineActor).head_world()
	elif look_target is Vector3:
		tgt = look_target
	if tgt != null:
		var hw := head_world()
		var dv: Vector3 = (tgt as Vector3) - hw
		ty = clampf(angle_difference(face, atan2(dv.x, dv.z)), -1.15, 1.15)
		tp = clampf(-atan2(dv.y, Vector2(dv.x, dv.z).length()), -0.5, 0.55) - lean * 0.6
	_hy += (ty - _hy) * minf(1.0, dt * 4.0)
	_hp += (tp - _hp) * minf(1.0, dt * 4.0)
	# body
	var sw := sin(_phase) * 0.42 * _moving if _moving > 0.05 and sit < 0.5 else 0.0
	_rx("Hip_R", -1.5 * sit + sw)
	_rx("Hip_L", -1.5 * sit - sw)
	_rx("Knee_R", 1.45 * sit + maxf(0.0, -sw) * 1.1)
	_rx("Knee_L", 1.45 * sit + maxf(0.0, sw) * 1.1)
	if _b["Upper"]:
		_b["Upper"].rotation.x = lean + sin(t * 1.1 + id.length()) * 0.008
		_b["Upper"].rotation.y = _hy * 0.25
	if _b["Head"]:
		var nod := maxf(0.0, sin((t - gesture_t) * 7.0)) * 0.28 if gesture == "nod" else 0.0
		_b["Head"].rotation.y = _hy * 0.75
		_b["Head"].rotation.x = _hp + nod + (sin(t * 5.3) * 0.02 if talking else 0.0)
	# arms
	var a := [sw * -0.7, sw * 0.7, -0.15, -0.15]
	var zr := -0.06
	match gesture:
		"type":
			a = [-0.75, -0.75, -0.8 + sin(t * 9.0) * 0.06, -0.8 + sin(t * 8.1 + 1.0) * 0.06]
		"raise":
			a = [-2.75 + sin(t * 7.0) * 0.12, -0.05, -0.35, -0.15]
			zr = -0.25
		"point":
			a = [-1.45, -0.05, -0.08, -0.15]
		"glass":
			a = [-1.55, -0.05, -0.35, -0.15]
	if sit > 0.5 and gesture == "none":
		a = [-0.5, -0.5, -0.9, -0.9]
	var k := minf(1.0, dt * 5.0)
	_lx("Shoulder_R", a[0], k)
	_lx("Shoulder_L", a[1], k)
	_lx("Elbow_R", a[2], k)
	_lx("Elbow_L", a[3], k)
	if _b["Shoulder_R"]:
		_b["Shoulder_R"].rotation.z = lerpf(_b["Shoulder_R"].rotation.z, zr, k)
	# face
	if _b["Mouth"]:
		_blink -= dt
		var eye_y := -1.0
		if _blink < 0.0:
			eye_y = 0.12
			if _blink < -0.12:
				_blink = (4.5 if expr == "thoughtful" else 2.6) + randf() * 2.5
		var E: Array = EXPR.get(expr, EXPR["neutral"])
		var ey: float = eye_y if eye_y > 0.0 else E[2]
		for n in ["Eye_R", "Eye_L"]:
			if _b[n]:
				_b[n].scale.y = lerpf(_b[n].scale.y, ey, minf(1.0, dt * 18.0))
		var i := 0
		for n in ["Brow_R", "Brow_L"]:
			if _b[n]:
				_b[n].position.y = lerpf(_b[n].position.y, 0.168 + E[0], minf(1.0, dt * 8.0))
				_b[n].rotation.z = lerpf(_b[n].rotation.z, (1.0 if i == 0 else -1.0) * E[1], minf(1.0, dt * 8.0))
			i += 1
		var m := 1.0 + 2.4 * absf(sin(t * 11.3) * sin(t * 4.1 + 1.0)) if talking else (1.7 if expr == "surprised" else 1.0)
		_b["Mouth"].scale.y = lerpf(_b["Mouth"].scale.y, m, minf(1.0, dt * 20.0))
	position = pos + Vector3(0, absf(cos(_phase)) * 0.02 * _moving if _moving > 0.05 else 0.0, 0)
	rotation.y = face


func _rx(n: String, v: float) -> void:
	if _b[n]:
		_b[n].rotation.x = v


func _lx(n: String, v: float, k: float) -> void:
	if _b[n]:
		_b[n].rotation.x = lerpf(_b[n].rotation.x, v, k)
