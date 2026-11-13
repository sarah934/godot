# Chapter 1 — The Signal from Mars (Godot 4.3+)

A ten-shot, about three-minute cinematic that runs in real time in the engine. It plays across the two levels built earlier:

- **Meridian Mission Control**, the UESA hall in 2110.
- **Ares Research Station**, intact in 2080 and ruined in 2110.

At the end, the film stops on the mission choice. **It never picks a mission for you.**

## Run it
1. Open the folder in Godot 4.3 or newer. The first import takes about a minute.
2. Press **F5**. `main.tscn` is the main scene.

| Key | Action |
|---|---|
| Space | Pause / resume |
| N / B | Next / previous shot |
| L | Switch subtitles between Arabic and English |
| R | Restart |

## How it works
The whole film is one data file, `chapter1_script.json`, and the web version uses the same file. It contains:

| Section | What it holds |
|---|---|
| `shots` | Camera moves: from/to, look/lookTo, fov, ease, shake, and `lookActor` to follow a face |
| `events` | Timed cues. `world` switches between mc, ares_intact and ares_ruined. `mc` drives stage, emergency, signal, trace, wall and highlight. `ares` drives reset, alarm, evac, power and meteor. `crowd` sets work, panic or calm. Actor commands are place, walk, sit, lean, look, face, gesture and expr. Overlays are `sub`, `card` and `fade`. `pause` stops the film. |
| `actors` | Nolan, Dr. Amara Sen (director), Eli Navarro (signal operator), Tomas Reyes (operations officer), plus two extras |
| `missions` | The two options shown at the decision |

To edit timing, dialogue or camera, change the JSON. You do not need to touch code.

## Scripts
| Script | Role |
|---|---|
| `scripts/chapter1.gd` | The director. Reads the JSON, runs events, camera and worlds, the seated crowd, the 2080 crew evacuation, and the meteor, fireball and shockwave. |
| `scripts/cine_actor.gd` | `CineActor`: walking, turning, sitting, leaning, head look-at, gestures, expressions, blinking and lip movement. |
| `scripts/chapter1_ui.gd` | Letterbox (2.39:1), fades and flash, title/place/time cards, Arabic and English subtitles, and the mission panel. |
| `scripts/mission_control.gd` | The level controller. New in this chapter: `set_signal()`, `set_trace()` and `set_wall_mode()`. |
| `scripts/ares_station.gd` | The station controller: `set_state()`, `set_alarm()` and `set_power()`. |

## Hooking the decision into your game
```gdscript
$Chapter1.mission_selected.connect(func(id):
    # "EOS-2110-047" = satellite deployment near Earth (risk LOW)
    # "ARES-RETURN"  = investigate the Ares station (risk EXTREME)
    get_tree().change_scene_to_file(...))
```

You can also set the export `start_time` to jump straight to any moment while testing. The script is fast-forwarded so that everyone is in the right place.

## Notes
- The characters are stylised mannequins with a simple rig. They are not scanned humans. Swap in your own models by keeping the bone/node names: Hip, Knee, Shoulder and Elbow with _L/_R, plus Upper, Head, Eye, Brow and Mouth.
- Arabic subtitles use the bundled DejaVu Sans font, which Godot shapes right-to-left.
- The Godot version has no sound. The web version synthesises sound. Add AudioStreamPlayers on the `sound` events if you need it.
- Test commands:
  - `godot --headless -s res://tools/test_run.gd` plays the whole film and checks the beats.
  - `tools/render_shots.gd` saves still frames.
