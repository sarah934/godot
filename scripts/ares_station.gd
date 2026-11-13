extends Node3D
## Ares Research Station — runtime controller for both eras of the level.
##   Intact  = the station in 2080 (flashback)      Ruined = the same station in 2110
## Both share one layout. This script switches between them (visibility AND collision),
## and drives lights, screens, doors, the roof cutaway, signs, the alarm/power states
## used by the disaster sequence, and the ambience of the ruin (red sensor, glowing specimen, dying terminal).

signal state_changed(new_state: String)

const UI := "res://assets/ui_ares/"
const ROOMS := {
	"SPINE": [-22.0, 22.0, -1.6, 1.6], "LAB": [0.0, 16.0, 1.6, 13.6], "HAB1": [-16.0, -2.0, 1.6, 8.6],
	"DATA": [-12.0, -2.0, -9.6, -1.6], "GEO": [2.0, 14.0, -11.6, -1.6], "GREEN": [15.0, 22.0, -9.6, -1.6],
	"HAB2": [-30.0, -22.0, -4.0, 4.0], "AIRLOCK": [22.0, 28.0, -2.2, 2.2],
}
const RUIN_WORKING_DOORS := ["Door_Emergency_Concealed", "Door_DATA_Core"]
# kind: [colour, energy, range]
const LIGHT_KIND := {
	"lab": [Color(1.0, 0.95, 0.89), 1.4, 9.0], "room": [Color(1.0, 0.95, 0.89), 1.0, 8.0], "grow": [Color(1.0, 0.35, 0.85), 1.0, 7.0],
	"specimen": [Color(0.48, 0.36, 1.0), 0.9, 5.0], "terminal": [Color(0.37, 0.82, 1.0), 0.5, 4.0], "sensor": [Color(0.24, 0.94, 0.54), 0.25, 2.0],
}
const SCREEN_MAP := {
	"Screen_LAB_Analysis_A": ["lab_mon_0", "lab_mon_alarm"], "Screen_LAB_Analysis_B": ["lab_mon_1", "lab_mon_alarm"], "Screen_LAB_Analysis_C": ["lab_mon_2", "lab_mon_alarm"],
	"Screen_LAB_Wall_Lattice": ["lab_wall", "lab_wall_alarm"], "Screen_LAB_WS1": ["ws_0", "ws_alarm"], "Screen_LAB_WS2": ["ws_1", "ws_alarm"],
	"Screen_GEO_WS": ["ws_0", "ws_alarm"], "Screen_DATA_Comm": ["ws_2", "ws_alarm"],
	"Screen_DATA_Terminal_Main": ["terminal", "terminal_alarm"], "Screen_DATA_Terminal_Side": ["terminal", "terminal_alarm"],
}
const LOOK := {
	"intact": {"el": 34.0, "az": -128.0, "sun": 1.6, "sun_col": Color(1.0, 0.94, 0.86), "amb": Color(0.89, 0.65, 0.48), "amb_e": 0.55,
		"top": Color(0.5, 0.36, 0.29), "hor": Color(0.86, 0.63, 0.47), "fog": Color(0.86, 0.63, 0.47), "fog_d": 0.0025},
	"ruined": {"el": 8.0, "az": -112.0, "sun": 1.2, "sun_col": Color(1.0, 0.8, 0.62), "amb": Color(0.55, 0.46, 0.43), "amb_e": 0.4,
		"top": Color(0.12, 0.1, 0.14), "hor": Color(0.62, 0.36, 0.24), "fog": Color(0.55, 0.33, 0.24), "fog_d": 0.0055},
}

@export var player_path: NodePath = ^"../Player"
@export var environment_path: NodePath = ^"../WorldEnvironment"
@export var sun_path: NodePath = ^"../Sun"
@export var start_state := "ruined"
@export var roof_cutaway := true   ## hide the roofs while the player is indoors (third-person camera)
@export var aerial_cutaway := false ## hide every roof (for overview shots)

var state := ""
var alarm := false
var power := 1.0
var _t := 0.0
var _roots := {}
var _player: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _lights := {"intact": [], "ruined": []}
var _doors := {"intact": [], "ruined": []}
var _roofs := {"intact": [], "ruined": []}
var _screens: Array = []        # [mesh, normal_mat, alarm_mat] — intact era only
var _bodies := {"intact": [], "ruined": []}
var _interact := {"intact": [], "ruined": []}
var _led := {}
var _alarm_mat: StandardMaterial3D
var _specimen_mat := {}
var _sensor_mat: StandardMaterial3D
var _sensor_light: OmniLight3D
var _terminal_light: OmniLight3D
var _terminal_mesh: MeshInstance3D
var _terminal_frames: Array[StandardMaterial3D] = []
var _flicker := 0.0


func _ready() -> void:
	_roots = {"intact": $Intact, "ruined": $Ruined}
	_player = get_node_or_null(player_path)
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we:
		_env = we.environment
	_sun = get_node_or_null(sun_path)
	_alarm_mat = _glow(Color(1.0, 0.14, 0.08), 0.0)
	for st in ["intact", "ruined"]:
		_led[st] = _glow(Color(1.0, 0.96, 0.89), 2.0 if st == "intact" else 0.0)
		_specimen_mat[st] = _glow(Color(0.42, 0.3, 1.0), 2.4 if st == "intact" else 1.3)
		_scan(_roots[st], st)
	for i in 3:
		_terminal_frames.append(_screen_mat("terminal_ruined_%d" % i, 1.1))
	if _terminal_mesh:
		_terminal_mesh.material_override = _terminal_frames[0]
	_setup_signs()
	set_state(start_state)


# ------------------------------------------------------------------ public API
func set_state(new_state: String) -> void:
	state = new_state
	for st in ["intact", "ruined"]:
		var on: bool = st == state
		(_roots[st] as Node3D).visible = on
		for b in _bodies[st]:
			(b as CollisionObject3D).collision_layer = 1 if on else 0
		for l in _lights[st]:
			(l as Light3D).visible = on
	_apply_look(LOOK[state])
	if state == "ruined":
		set_alarm(false)
		set_power(1.0)
	state_changed.emit(state)


func set_alarm(on: bool) -> void:
	alarm = on
	for s in _screens:
		(s[0] as MeshInstance3D).material_override = s[2] if on else s[1]


func set_power(p: float) -> void:
	power = p
	(_led["intact"] as StandardMaterial3D).emission_energy_multiplier = 2.0 * p
	for l in _lights["intact"]:
		(l as Light3D).light_energy = float(l.get_meta("base")) * p
	for s in _screens:
		for m in [s[1], s[2]]:
			(m as StandardMaterial3D).emission_energy_multiplier = 1.3 * p


func find_marker(marker_name: String, in_state := "") -> Node3D:
	var st := in_state if in_state != "" else state
	return (_roots[st] as Node).find_child(marker_name, true, false) as Node3D


func nearest_interact(pos: Vector3, radius := 1.9) -> String:
	## Returns the key of the closest point of interest ("specimen", "sensor", "terminal", "log", "emergency") or "".
	var best := ""
	var best_d := radius
	for m in _interact[state]:
		var p := (m as Node3D).global_position
		var d := Vector2(pos.x - p.x, pos.z - p.z).length()
		if d < best_d and absf(pos.y - p.y) < 1.5:
			best_d = d
			best = String(m.name).trim_prefix("Interact_").to_lower()
	return best


func room_at(pos: Vector3) -> String:
	for id in ROOMS:
		var r: Array = ROOMS[id]
		if state == "ruined" and id == "AIRLOCK" and pos.x > 26.2:
			continue
		if pos.x >= r[0] and pos.x <= r[1] and pos.z >= r[2] and pos.z <= r[3] and pos.y < 3.0:
			return id
	return ""


# ------------------------------------------------------------------ setup
func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.6)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _screen_mat(file: String, energy := 1.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.roughness = 0.6
	m.metallic_specular = 0.15
	m.emission_enabled = true
	m.emission_texture = load(UI + file + ".png")
	m.emission_energy_multiplier = energy
	m.uv1_scale = Vector3(1, -1, 1)  # glTF screen UVs arrive flipped on V
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _scan(root: Node, st: String) -> void:
	for n in root.find_children("*", "", true, false):
		var nm := String(n.name)
		if n is StaticBody3D:
			_bodies[st].append(n)
		elif n is MeshInstance3D:
			_dress_mesh(n as MeshInstance3D, nm, st)
		elif n is Node3D:
			if nm.begins_with("Roof_"):
				_roofs[st].append(n)
			elif nm.begins_with("Interact_"):
				_interact[st].append(n)
			elif nm.begins_with("LightSpot_"):
				_make_light(n as Node3D, nm.split("_")[1], st)
			elif nm.begins_with("Door_") and not nm.contains("_Leaf") and not nm.contains("_Frame"):
				var l := n.find_child(nm + "_LeafL", false, false) as Node3D
				var r := n.find_child(nm + "_LeafR", false, false) as Node3D
				if l and r:
					var works: bool = st == "intact" or nm in RUIN_WORKING_DOORS
					_doors[st].append({"node": n, "leaves": [l, r], "base": [l.position.x, r.position.x], "w": absf(l.position.x) * 4.0, "open": 0.0, "works": works})


func _dress_mesh(mi: MeshInstance3D, nm: String, st: String) -> void:
	if nm.contains("Emissive_LED"):
		mi.material_override = _led[st]
	elif nm.contains("Emissive_Specimen"):
		mi.material_override = _specimen_mat[st]
	elif nm.contains("Emissive_Alarm"):
		mi.material_override = _alarm_mat
	elif nm == "Sensor_Unit_RS2_Indicator" and st == "ruined":
		_sensor_mat = _glow(Color(1.0, 0.1, 0.04), 3.0)
		mi.material_override = _sensor_mat
	elif nm.begins_with("Screen_"):
		if st == "intact" and SCREEN_MAP.has(nm):
			var pair: Array = SCREEN_MAP[nm]
			var normal := _screen_mat(pair[0])
			mi.material_override = normal
			_screens.append([mi, normal, _screen_mat(pair[1], 1.6)])
		elif st == "ruined" and nm == "Screen_DATA_Terminal_Main":
			_terminal_mesh = mi


func _make_light(m: Node3D, kind: String, st: String) -> void:
	if not LIGHT_KIND.has(kind):
		return
	var spec: Array = LIGHT_KIND[kind]
	var col: Color = spec[0]
	var energy: float = spec[1]
	if st == "ruined":
		if kind == "specimen":
			energy = 0.6
		elif kind == "sensor":
			col = Color(1.0, 0.12, 0.06)
			energy = 0.5
		elif kind == "terminal":
			energy = 0.4
		else:
			return
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = spec[2]
	l.set_meta("base", energy)
	l.position = m.position
	m.get_parent().add_child(l)
	_lights[st].append(l)
	if st == "ruined" and kind == "sensor":
		_sensor_light = l
	if st == "ruined" and kind == "terminal":
		_terminal_light = l


func _setup_signs() -> void:
	var f := FileAccess.open("res://assets/signs.json", FileAccess.READ)
	if f == null:
		return
	var texts: Dictionary = JSON.parse_string(f.get_as_text())
	for st in ["intact", "ruined"]:
		for n in (_roots[st] as Node).find_children("Sign_*", "MeshInstance3D", true, false):
			var key := String(n.name)
			if not texts.has(key):
				continue
			var mi := n as MeshInstance3D
			var aabb := mi.get_aabb()
			var label := Label3D.new()
			label.text = texts[key]
			label.font_size = 96
			label.outline_size = 0
			label.modulate = Color(0.1, 0.1, 0.1) if st == "intact" else Color(0.25, 0.18, 0.14)
			label.pixel_size = 0.5 * aabb.size.y / 96.0
			var est := label.text.length() * 0.6 * 96.0 * label.pixel_size
			if est > aabb.size.x * 0.88:
				label.pixel_size *= aabb.size.x * 0.88 / est
			label.position = Vector3(0, 0, 0.006)
			label.shaded = false
			mi.add_child(label)


func _apply_look(L: Dictionary) -> void:
	if _sun:
		_sun.rotation_degrees = Vector3(-L["el"], L["az"], 0.0)
		_sun.light_energy = L["sun"]
		_sun.light_color = L["sun_col"]
	if _env:
		_env.ambient_light_color = L["amb"]
		_env.ambient_light_energy = L["amb_e"]
		_env.fog_light_color = L["fog"]
		_env.fog_density = L["fog_d"]
		if _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
			var sm := _env.sky.sky_material as ProceduralSkyMaterial
			sm.sky_top_color = L["top"]
			sm.sky_horizon_color = L["hor"]
			sm.ground_horizon_color = L["hor"]


# ------------------------------------------------------------------ runtime
func _process(delta: float) -> void:
	_t += delta
	if alarm:
		_alarm_mat.emission_energy_multiplier = 3.0 if sin(_t * 8.0) > 0.0 else 0.2
	else:
		_alarm_mat.emission_energy_multiplier = 0.0
	if state == "ruined":
		var blink := 3.2 if sin(_t * 3.1) > 0.2 else 0.15
		if _sensor_mat:
			_sensor_mat.emission_energy_multiplier = blink
		if _sensor_light:
			_sensor_light.light_energy = blink * 0.16
		(_specimen_mat["ruined"] as StandardMaterial3D).emission_energy_multiplier = 1.1 + 0.3 * sin(_t * 0.9)
		_flicker -= delta
		if _flicker <= 0.0 and _terminal_mesh:
			_flicker = randf_range(0.05, 0.4)
			var f := 2 if randf() < 0.12 else randi() % 2
			_terminal_mesh.material_override = _terminal_frames[f]
			if _terminal_light:
				_terminal_light.light_energy = 0.0 if f == 2 else 0.4
	else:
		(_specimen_mat["intact"] as StandardMaterial3D).emission_energy_multiplier = 2.2 + 0.4 * sin(_t * 1.3)
	_update_doors(delta)
	_update_roofs()


func _update_doors(delta: float) -> void:
	var actors: Array[Vector3] = []
	if _player:
		actors.append(_player.global_position)
	for c in get_tree().get_nodes_in_group("door_openers"):
		actors.append((c as Node3D).global_position)
	for d in _doors[state]:
		if not d["works"]:
			continue
		var p := (d["node"] as Node3D).global_position
		var near := false
		for a in actors:
			if Vector2(a.x - p.x, a.z - p.z).length() < 3.0 and absf(a.y - p.y) < 2.0:
				near = true
		d["open"] = lerpf(d["open"], 1.0 if near else 0.0, minf(1.0, delta * 4.0))
		var w: float = d["w"]
		(d["leaves"][0] as Node3D).position.x = -(w / 4.0 + d["open"] * w * 0.47)
		(d["leaves"][1] as Node3D).position.x = w / 4.0 + d["open"] * w * 0.47


func _update_roofs() -> void:
	var hide := aerial_cutaway
	if not hide and roof_cutaway and _player and get_viewport().get_camera_3d() and _player.is_ancestor_of(get_viewport().get_camera_3d()):
		hide = room_at(_player.global_position) != ""
	for st in ["intact", "ruined"]:
		for r in _roofs[st]:
			(r as Node3D).visible = not hide
