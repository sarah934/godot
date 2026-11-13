extends CanvasLayer
## Chapter 1 overlays: letterbox, fades and the impact flash, title/place/time cards,
## subtitles in Arabic or English (DejaVu Sans ships with the project and shapes Arabic),
## and the mission-selection panel shown when the film pauses.

signal mission_chosen(mission_id: String)

const SPEAKER_COLORS := {"nolan": Color(1.0, 0.71, 0.28), "director": Color(0.5, 0.84, 1.0), "operator": Color(0.61, 0.9, 0.61), "officer": Color(0.84, 0.71, 1.0), "crowd": Color(0.62, 0.69, 0.76)}

var lang := "ar"
var _root: Control
var _bars: Array[ColorRect] = []
var _fade: ColorRect
var _flash: ColorRect
var _who: Label
var _line: Label
var _cards := {}
var _card_state := {}
var _choice: PanelContainer
var _choice_box: HBoxContainer
var _done: Label
var _choice_title: Label


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = load("res://fonts/DejaVuSans.ttf")
	_root.theme = th
	add_child(_root)
	_fade = _rect(Color(0, 0, 0, 0))
	_flash = _rect(Color(1, 0.97, 0.92, 0))
	var sub := VBoxContainer.new()
	_place(sub, 0.08, 1.0, 0.92, 1.0, -0.245, -0.11)
	_root.add_child(sub)
	_who = _label(16, Color.WHITE, sub, true)
	_line = _label(26, Color(0.95, 0.96, 0.98), sub, true)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for style in ["title", "place", "time"]:
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(box)
		var a := _label(56 if style == "title" else (22 if style == "place" else 46), Color(0.95, 0.96, 0.98), box, style != "place")
		var b := _label(16 if style != "place" else 13, Color(1.0, 0.71, 0.28) if style == "title" else Color(0.62, 0.69, 0.76), box, style != "place")
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		if style == "place":
			_place(box, 0.5, 0.0, 0.96, 0.0, 0.15, 0.26)
			a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			_place(box, 0.05, 0.5, 0.95, 0.5, -0.1, 0.1)
		box.modulate.a = 0.0
		_cards[style] = [box, a, b]
	for i in 2:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(b)
		_bars.append(b)
	_build_choice()


## Anchors a control to a fraction of the screen; the last two values are vertical offsets as a fraction of 720 px.
func _place(c: Control, l: float, t: float, r: float, b: float, oy0: float, oy1: float) -> void:
	c.anchor_left = l
	c.anchor_right = r
	c.anchor_top = t
	c.anchor_bottom = b
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = oy0 * 720.0
	c.offset_bottom = oy1 * 720.0


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


func _label(size: int, c: Color, parent: Node, centered: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_y", 2)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _build_choice() -> void:
	_choice = PanelContainer.new()
	_place(_choice, 0.17, 1.0, 0.83, 1.0, -0.5, -0.135)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.02, 0.04, 0.07, 0.9)
	st.border_color = Color(0.4, 0.7, 1.0, 0.35)
	st.set_border_width_all(1)
	st.set_corner_radius_all(12)
	st.set_content_margin_all(18)
	_choice.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_choice.add_child(v)
	_choice_title = _label(20, Color.WHITE, v, false)
	_choice_box = HBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 14)
	v.add_child(_choice_box)
	_done = _label(16, Color(1.0, 0.71, 0.28), v, false)
	_done.visible = false
	_choice.visible = false
	_root.add_child(_choice)


func set_language(l: String) -> void:
	lang = l


func reset() -> void:
	_card_state.clear()
	_choice.visible = false
	_fade.color.a = 0.0


func show_card(card: Dictionary, t: float) -> void:
	_card_state[card["style"]] = {"c": card, "t0": t, "t1": t + float(card["dur"])}


func set_flash(a: float) -> void:
	_flash.color.a = clampf(a, 0.0, 1.0)


func update_overlays(T: float, fade: Color, sub: Dictionary, actors: Dictionary) -> void:
	var vp := get_viewport().get_visible_rect().size
	var bar := maxf(0.0, (vp.y - vp.x / 2.39) / 2.0)
	_bars[0].position = Vector2.ZERO
	_bars[0].size = Vector2(vp.x, bar)
	_bars[1].position = Vector2(0, vp.y - bar)
	_bars[1].size = Vector2(vp.x, bar)
	_fade.color = fade
	if sub.is_empty():
		_who.text = ""
		_line.text = ""
	else:
		var who: String = sub["who"]
		var name_key := "name_ar" if lang == "ar" else "name_en"
		var nm: String = (actors[who][name_key] if actors.has(who) and actors[who].has(name_key) else ("أصوات في القاعة" if lang == "ar" else "Voices in the room"))
		if sub.get("vo", false):
			nm += " (صوت)" if lang == "ar" else " (V.O.)"
		_who.text = nm
		_who.add_theme_color_override("font_color", SPEAKER_COLORS.get(who, Color.WHITE))
		_line.text = sub[lang]
	for style in _cards:
		var parts: Array = _cards[style]
		var box := parts[0] as Control
		var on := false
		if _card_state.has(style):
			var cs: Dictionary = _card_state[style]
			on = T >= cs["t0"] and T < cs["t1"]
			(parts[1] as Label).text = cs["c"][lang]
			(parts[2] as Label).text = cs["c"]["en"] if lang == "ar" else ""
		box.modulate.a = move_toward(box.modulate.a, 1.0 if on else 0.0, get_process_delta_time() * 1.5)


func show_choice(missions: Array) -> void:
	for c in _choice_box.get_children():
		c.queue_free()
	_choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if lang == "ar" else HORIZONTAL_ALIGNMENT_LEFT
	_done.horizontal_alignment = _choice_title.horizontal_alignment
	_choice_title.text = "اختر مهمة نولان — القرار قرارك" if lang == "ar" else "Choose Nolan's mission — the decision is yours"
	for m in missions:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 170)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_contents = true
		var risky: bool = m["risk"] != "LOW"
		var acc := Color(1.0, 0.42, 0.3) if risky else Color(0.5, 0.84, 1.0)
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0.05, 0.08, 0.12, 0.95)
		bs.border_color = acc
		bs.set_border_width_all(1)
		bs.set_corner_radius_all(8)
		var hs := bs.duplicate() as StyleBoxFlat
		hs.bg_color = Color(acc.r, acc.g, acc.b, 0.18)
		hs.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", bs)
		b.add_theme_stylebox_override("hover", hs)
		b.add_theme_stylebox_override("focus", hs)
		b.add_theme_stylebox_override("pressed", hs)
		var mg := MarginContainer.new()
		mg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			mg.add_theme_constant_override("margin_" + side, 14)
		b.add_child(mg)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mg.add_child(col)
		var rows := [[m["id"], 13, acc], [m[lang + "_title"], 20, Color.WHITE], [m[lang], 14, Color(0.75, 0.8, 0.86)], [("الخطورة: " if lang == "ar" else "RISK: ") + String(m["risk"]), 13, acc]]
		for r in rows:
			var l := _label(r[1], r[2], col, false)
			l.text = r[0]
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if lang == "ar":
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.pressed.connect(_pick.bind(m))
		_choice_box.add_child(b)
	_done.visible = false
	_choice_box.visible = true
	_choice.visible = true
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _pick(m: Dictionary) -> void:
	_choice_box.visible = false
	_done.visible = true
	_done.text = ("تم تسجيل القرار: %s · %s" if lang == "ar" else "Decision recorded: %s · %s") % [m["id"], m[lang + "_title"]]
	mission_chosen.emit(m["id"])
