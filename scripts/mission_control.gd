extends Node3D
## Meridian Mission Control (UESA, 2110) — runtime controller for the level.
## Handles: normal ⇄ emergency lighting, the 5-stage display-wall sequence, all screen content,
## sliding doors, signage text and the two small holograms.
## Nothing here is baked into the mesh: screens, text and lights are applied at runtime.
##
## Demo keys: G = toggle emergency · T / Y = next / previous wall stage · P = play the whole signal scene.

signal stage_changed(stage: int)
signal emergency_changed(active: bool)

const UI := "res://assets/ui_mc/"
const STAGE_FILES := ["wall_0_operations", "wall_1_signal", "wall_2_tracking", "wall_3_mars", "wall_4_ares_station", "wall_5_alert"]
const STAGE_NAMES := ["Operations overview", "Unidentified signal", "Deep-space tracking", "Mars", "Ares Research Station", "Priority Alpha alert"]
const SIGN_TEXT := {
	"Sign_Row_1": "ROW 1 · FLIGHT DYNAMICS",
	"Sign_Row_2": "ROW 2 · DEEP SPACE COMMS",
	"Sign_Row_3": "ROW 3 · SYSTEMS & LIFE SUPPORT",
	"Sign_Row_4": "ROW 4 · SCIENCE & PLANETARY",
	"Sign_Level2_West": "LEVEL 2 · MISSION DIRECTOR",
	"Sign_Level2_East": "LEVEL 2 · MISSION DIRECTOR",
	"Sign_Prep_Corridor": "PREP CORRIDOR → BRIEFING ROOM",
	"Sign_Facility_Access": "FACILITY ACCESS · RESTRICTED",
	"Sign_Hall_Name": "MERIDIAN MISSION CONTROL · UESA",
	"Sign_Hall_Motto": "DEEP SPACE OPERATIONS · EST. 2084",
	"Sign_Director_Office": "MISSION DIRECTOR · L2-01",
	"Sign_Launch_Prep": "LAUNCH PREP · HANGAR 3 · SEALED",
	"Sign_EVA_Suits": "EVA SUIT STORAGE · ARES PROGRAM",
	"Sign_Briefing_Room": "DIRECTOR'S BRIEFING ROOM",
}
# Light rig, mirrored from the level builder (x, y, z, energy, range).
const HALL_LIGHTS := [[-10, 11.5, -12, 2.2, 22], [10, 11.5, -12, 2.2, 22], [-10, 11.5, 1, 2.2, 22], [10, 11.5, 1, 2.2, 22], [0, 11.5, -6, 2.2, 22], [-11, 3.6, 16, 0.9, 9], [11, 3.6, 16, 0.9, 9], [0, 3.6, 24, 0.9, 9]]
const ROOM_LIGHTS := [[0, 7.8, 24.8, 1.0, 9], [25.5, 3.1, -6, 0.8, 6], [32.5, 3.1, -6, 0.8, 6], [28.8, 3.1, -1.8, 0.6, 6], [41, 3.5, -6, 1.2, 8], [44.5, 3.5, -6, 0.8, 6]]
const COOL := Color(0.9, 0.95, 1.0)
const ALERT_RED := Color(1.0, 0.16, 0.1)

@export var player_path: NodePath = ^"../Player"
@export var environment_path: NodePath = ^"../WorldEnvironment"
@export var blend_seconds := 1.6

var stage := 0
var emergency := false
var briefing_choice := ""
var signal_on := false
var _signal_a: Array = []
var _director_mat: StandardMaterial3D
var _e := 0.0
var _t := 0.0
var _auto := -1.0
var _warn_now := false
var _meshes: Array[MeshInstance3D] = []
var _player: Node3D
var _env: Environment
var _ambient_normal := Color(0.55, 0.63, 0.78)
var _wall_mat: StandardMaterial3D
var _briefing_mat: StandardMaterial3D
var _overlay: MeshInstance3D
var _overlay_mat: StandardMaterial3D
var _strip_mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _led_mat: StandardMaterial3D
var _ticker_mats: Array[StandardMaterial3D] = []
var _swaps: Array = []        # [mesh, normal_mat, alert_mat] — swapped when the emergency passes 50 %
var _signal_swaps: Array = [] # [mesh, idle_mat, hot_mat] — the signal workstation lights up from stage 1
var _lights: Array[Light3D] = []
var _red_lights: Array[OmniLight3D] = []
var _key: SpotLight3D
var _signal_spot: SpotLight3D
var _doors: Array = []
var _holo_orbit: Node3D
var _holo_mars: Node3D


func _ready() -> void:
	_player = get_node_or_null(player_path)
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we and we.environment:
		_env = we.environment
		_ambient_normal = _env.ambient_light_color
	_collect(self)
	_setup_shared_materials()
	_setup_screens()
	_setup_lights()
	_setup_signs()
	_setup_doors()
	_setup_holograms()
	set_stage(0)
	_apply(0.0)


func find_marker(marker_name: String) -> Node3D:
	return find_child(marker_name, true, false) as Node3D


# ------------------------------------------------------------------ public API
func set_emergency(active: bool) -> void:
	if emergency == active:
		return
	emergency = active
	emergency_changed.emit(active)


func set_stage(i: int) -> void:
	stage = clampi(i, 0, STAGE_FILES.size() - 1)
	if _wall_mat:
		_wall_mat.emission_texture = load(UI + STAGE_FILES[stage] + ".png")
	_update_signal_station()
	stage_changed.emit(stage)


func play_signal_scene() -> void:
	set_emergency(true)
	set_stage(1)
	_auto = 0.0


func set_briefing_choice(id: String) -> void:
	briefing_choice = id
	if _briefing_mat:
		_briefing_mat.emission_texture = load(UI + "briefing_%s.png" % id)
	if _holo_mars:
		var m := (_holo_mars.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		m.emission = Color(1.0, 0.7, 0.3) if id == "A" else Color(0.3, 1.0, 0.55)


# ------------------------------------------------------------------ setup
func _collect(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_meshes.append(c)
		_collect(c)


func _emissive(file: String, energy := 1.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.roughness = 0.6
	m.metallic_specular = 0.15
	m.emission_enabled = true
	m.emission_texture = load(UI + file + ".png")
	m.emission_energy_multiplier = energy
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.texture_repeat = true
	m.uv1_scale = Vector3(1, -1, 1)  # glTF screen UVs arrive flipped on V; flip back so text reads correctly
	return m


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.6)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _setup_shared_materials() -> void:
	_strip_mat = _glow(Color(0.74, 0.83, 1.0), 0.6)
	_beacon_mat = _glow(ALERT_RED, 0.0)
	_led_mat = _glow(Color(0.93, 0.96, 1.0), 2.0)
	for mi in _meshes:
		var n := String(mi.name)
		if n.contains("Emissive_EmergencyStrip"):
			mi.material_override = _strip_mat
		elif n.contains("Emissive_Beacon"):
			mi.material_override = _beacon_mat
		elif n.contains("Emissive_LED_Panel"):
			mi.material_override = _led_mat


func _setup_screens() -> void:
	var sig := find_child("*_SIGNAL", true, false) as Node3D
	var sig_pos := sig.global_position if sig else Vector3.ZERO
	for mi in _meshes:
		var n := String(mi.name)
		if not n.begins_with("Screen_"):
			continue
		if n == "Screen_Wall_Center_AlertOverlay":
			_overlay = mi
			_overlay_mat = StandardMaterial3D.new()
			_overlay_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_overlay_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_overlay_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_overlay_mat.albedo_color = Color(1, 0.1, 0.06, 0.0)
			mi.material_override = _overlay_mat
			mi.visible = false
		elif n == "Screen_Wall_Center":
			_wall_mat = _emissive(STAGE_FILES[0], 1.5)
			mi.material_override = _wall_mat
		elif n == "Screen_Wall_Left" or n == "Screen_Wall_Right":
			var base := "wall_left_earth" if n.ends_with("Left") else "wall_right_mars"
			_swap(mi, _emissive(base), _emissive(base + "_alert"))
		elif n == "Screen_Wall_Ticker":
			var a := _emissive("ticker")
			var b := _emissive("ticker_alert")
			for m in [a, b]:
				m.uv1_scale = Vector3(0.25, -1, 1)
				m.texture_repeat = true
				_ticker_mats.append(m)
			_swap(mi, a, b)
		elif n.begins_with("Screen_Wall_Lower_"):
			mi.material_override = _emissive("lower_%d" % (int(n.right(1)) - 1))
		elif n.begins_with("Screen_Status_") or n == "Screen_Corridor_Status" or n == "Screen_Briefing_Side":
			var v := n.hash() % 2
			_swap(mi, _emissive("status_%d" % v), _emissive("status_%d_alert" % v))
		elif n == "Screen_Director_Wall":
			_director_mat = _emissive("director_wall")
			mi.material_override = _director_mat
		elif n == "Screen_Briefing_Wall":
			_briefing_mat = _emissive("briefing")
			mi.material_override = _briefing_mat
		else:
			# workstation and director monitors: Screen_<id>_<slot>
			var slot := n.right(1)
			var parent_name := String(mi.get_parent().name)
			if parent_name.ends_with("_SIGNAL"):
				_signal_swaps.append([mi, _emissive("signal_" + slot), _emissive("signal_%s_hot" % slot, 1.6)])
				if slot == "A":
					_signal_a = _signal_swaps[-1]
				continue
			var normal := _emissive(("strip_%d" % (n.hash() % 4)) if slot == "D" else ("ws_%d" % (n.hash() % 8)), 1.2)
			mi.material_override = normal
			if sig and mi.global_position.distance_to(sig_pos) < 6.5 and not n.begins_with("Screen_Director"):
				_swaps.append([mi, normal, _emissive("strip_warning" if slot == "D" else "ws_warning", 1.5)])


func _swap(mi: MeshInstance3D, normal: StandardMaterial3D, alert: StandardMaterial3D) -> void:
	mi.material_override = normal
	_swaps.append([mi, normal, alert])


func _update_signal_station() -> void:
	var hot := signal_on or stage >= 1 or _e > 0.5
	for s in _signal_swaps:
		(s[0] as MeshInstance3D).material_override = s[2] if hot else s[1]


func _setup_lights() -> void:
	_key = SpotLight3D.new()
	_key.name = "Key_Overhead"
	_key.position = Vector3(0, 13.6, -3)
	_key.rotation_degrees = Vector3(-90, 0, 0)
	_key.spot_angle = 62.0
	_key.spot_range = 30.0
	_key.light_energy = 5.0
	_key.light_color = COOL
	_key.shadow_enabled = true
	add_child(_key)
	for spec in HALL_LIGHTS + ROOM_LIGHTS:
		var l := OmniLight3D.new()
		l.position = Vector3(spec[0], spec[1], spec[2])
		l.light_energy = spec[3]
		l.omni_range = spec[4]
		l.light_color = COOL if spec[1] > 4 or absf(spec[0]) < 12 else Color(1.0, 0.96, 0.9)
		l.set_meta("base", float(spec[3]))
		l.set_meta("color", l.light_color)
		add_child(l)
		_lights.append(l)
	for x in [-20.6, 20.6]:
		var r := OmniLight3D.new()
		r.position = Vector3(x, 12.2, -19.0)
		r.omni_range = 18.0
		r.light_color = ALERT_RED
		r.light_energy = 0.0
		add_child(r)
		_red_lights.append(r)
	_signal_spot = SpotLight3D.new()
	_signal_spot.name = "Signal_Red_Spot"
	var m := find_marker("Light_Signal_Red")
	_signal_spot.position = m.global_position if m else Vector3(2.9, 6.25, -3.35)
	_signal_spot.rotation_degrees = Vector3(-90, 0, 0)
	_signal_spot.spot_angle = 20.0
	_signal_spot.spot_range = 9.0
	_signal_spot.light_color = ALERT_RED
	_signal_spot.light_energy = 0.0
	_signal_spot.shadow_enabled = true
	add_child(_signal_spot)


func _setup_signs() -> void:
	for mi in _meshes:
		var n := String(mi.name)
		if not SIGN_TEXT.has(n):
			continue
		var aabb := mi.get_aabb()
		var w := aabb.size.x
		var h := aabb.size.y
		var label := Label3D.new()
		label.text = SIGN_TEXT[n]
		label.font_size = 96
		label.outline_size = 0
		label.modulate = Color(0.09, 0.13, 0.18)
		label.pixel_size = 0.5 * h / 96.0
		var est_w := label.text.length() * 0.6 * 96.0 * label.pixel_size
		if est_w > w * 0.9:
			label.pixel_size *= (w * 0.9) / est_w
		label.position = Vector3(0, 0, 0.006)
		label.shaded = false
		mi.add_child(label)


func _setup_doors() -> void:
	for d in find_children("Door_*", "Node3D", true, false):
		var n := String(d.name)
		if n.ends_with("_Frame") or n.contains("_Leaf"):
			continue
		var l := d.find_child(n + "_LeafL", false, false) as Node3D
		var r := d.find_child(n + "_LeafR", false, false) as Node3D
		if l == null or r == null:
			continue
		var w := absf(l.position.x) * 4.0
		var locked := n.contains("_Locked")
		_doors.append({"node": d, "leaves": [l, r], "w": w, "open": 0.0, "locked": locked})
		if locked:
			# keep sealed doors solid for the player
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(w, 2.8, 0.3)
			shape.shape = box
			shape.position = Vector3(0, 1.4, 0)
			body.add_child(shape)
			d.add_child(body)


func _setup_holograms() -> void:
	var holo := StandardMaterial3D.new()
	holo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	holo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	holo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	holo.albedo_color = Color(0.37, 0.86, 1.0, 0.55)
	var a := find_marker("Hologram_Anchor_Orbits")
	if a:
		_holo_orbit = Node3D.new()
		_holo_orbit.position = a.global_position
		add_child(_holo_orbit)
		for r in [0.7, 1.05]:
			var t := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = r - 0.01
			tm.outer_radius = r + 0.01
			t.mesh = tm
			t.material_override = holo
			_holo_orbit.add_child(t)
		var sun := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.12
		sm.height = 0.24
		sun.mesh = sm
		sun.material_override = holo
		_holo_orbit.add_child(sun)
	var b := find_marker("Hologram_Anchor_Briefing")
	if b:
		_holo_mars = Node3D.new()
		_holo_mars.position = b.global_position
		add_child(_holo_mars)
		var s := MeshInstance3D.new()
		var sm2 := SphereMesh.new()
		sm2.radius = 0.42
		sm2.height = 0.84
		s.mesh = sm2
		var mm := _glow(Color(1.0, 0.45, 0.25), 1.2)
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.albedo_color = Color(1.0, 0.45, 0.25, 0.35)
		s.material_override = mm
		_holo_mars.add_child(s)


# ------------------------------------------------------------------ runtime
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_G:
				set_emergency(not emergency)
			KEY_T:
				_auto = -1.0
				set_stage(stage + 1)
			KEY_Y:
				_auto = -1.0
				set_stage(stage - 1)
			KEY_P:
				play_signal_scene()


func _process(delta: float) -> void:
	_t += delta
	var target := 1.0 if emergency else 0.0
	_e = move_toward(_e, target, delta / blend_seconds)
	_apply(delta)
	if _auto >= 0.0:
		_auto += delta
		var s := 1 + int(_auto / 7.0)
		if s != stage and s <= 5:
			set_stage(s)
		if s >= 5:
			_auto = -1.0
	for m in _ticker_mats:
		m.uv1_offset.x = fmod(_t * 0.018, 1.0)
	if _holo_orbit:
		_holo_orbit.rotation.y = _t * 0.15
	if _holo_mars:
		_holo_mars.rotation.y = _t * 0.3
	_update_doors(delta)


func _apply(_delta: float) -> void:
	var e := _e
	var pulse := 0.5 + 0.5 * sin(_t * 5.2)
	for l in _lights:
		l.light_energy = float(l.get_meta("base")) * lerpf(1.0, 0.45, e)
		l.light_color = (l.get_meta("color") as Color).lerp(ALERT_RED, e)
	if _key:
		_key.light_energy = lerpf(5.0, 2.6, e)
		_key.light_color = COOL.lerp(ALERT_RED, e)
	for i in _red_lights.size():
		_red_lights[i].light_energy = e * 4.0 * (0.5 + 0.5 * sin(_t * 5.2 + i * 1.6))
	if _signal_spot:
		_signal_spot.light_energy = e * (14.0 + 4.0 * pulse)
	_strip_mat.emission = Color(0.74, 0.83, 1.0).lerp(ALERT_RED, e)
	_strip_mat.emission_energy_multiplier = lerpf(0.6, 2.2 + 2.0 * pulse, e)
	_beacon_mat.emission_energy_multiplier = e * (0.6 + 3.5 * pulse)
	_led_mat.emission_energy_multiplier = lerpf(2.0, 0.3, e)
	_led_mat.emission = Color(0.93, 0.96, 1.0).lerp(Color(1.0, 0.82, 0.78), e)
	if _overlay:
		_overlay.visible = e > 0.02
		_overlay_mat.albedo_color.a = e * (0.08 + 0.1 * pulse) * (1.6 if stage == 5 else 1.0)
	if _env:
		_env.ambient_light_color = _ambient_normal.lerp(Color(0.6, 0.12, 0.1), e)
	var warn := e > 0.5
	if warn != _warn_now:
		_warn_now = warn
		for s in _swaps:
			(s[0] as MeshInstance3D).material_override = s[2] if warn else s[1]
		_update_signal_station()


func _update_doors(delta: float) -> void:
	var openers: Array = get_tree().get_nodes_in_group("door_openers")
	if _player:
		openers.append(_player)
	for d in _doors:
		if d["locked"]:
			continue
		var node := d["node"] as Node3D
		var p := node.global_position
		var near := false
		for o in openers:
			var q: Vector3 = (o as Node3D).global_position
			if Vector2(q.x - p.x, q.z - p.z).length() < 3.2 and absf(q.y - p.y) < 2.0:
				near = true
		d["open"] = lerpf(d["open"], 1.0 if near else 0.0, minf(1.0, delta * 4.0))
		var w: float = d["w"]
		(d["leaves"][0] as Node3D).position.x = -(w / 4.0 + d["open"] * w * 0.47)
		(d["leaves"][1] as Node3D).position.x = w / 4.0 + d["open"] * w * 0.47


# ------------------------------------------------------------------ Chapter 1 hooks
func set_signal(on: bool) -> void:
	## Lights up only the signal workstation (red pendant + its screens), without the full emergency.
	signal_on = on
	_update_signal_station()


func set_trace(progress: float) -> void:
	## Shows the signal tracing across the solar system on the operator's main monitor (progress 0..1, <0 = off).
	if _signal_a.is_empty():
		return
	var mi := _signal_a[0] as MeshInstance3D
	if progress < 0.0:
		_update_signal_station()
		return
	mi.material_override = _emissive("signal_trace_%d" % clampi(int(progress * 4.0), 0, 3), 1.6)


func set_wall_mode(mode: String, highlight := "") -> void:
	## "planning" or "missions" on the director's office screen; highlight "", "A", "B", "both"; prefix "chosen_" to mark the decision.
	if _director_mat == null:
		return
	var file := "director_wall" if mode == "planning" else ("director_missions" + ("_" + highlight if highlight != "" else ""))
	_director_mat.emission_texture = load(UI + file + ".png")
