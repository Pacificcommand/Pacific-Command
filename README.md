# Pacific Command — combat sandbox (build 0.3)

WWII Pacific naval game for PC, made in **Godot 4.7.2**. Combat sandbox with three
missions, picked on the briefing screen:

- **Destroyer action:** USS O'Bannon (Fletcher class) against two Kagero-class destroyers.
- **PT barge hunt:** you and two AI PT boats against a night run of Daihatsu barges
  (four supply barges, two gun barges). Torpedoes run under barges, so it's a gun fight.
- **PT convoy attack:** three PT boats against two cargo ships and a tanker with a
  Kagero escort. PT torpedoes fire straight ahead: aim the boat, then press T.

The other PT boats follow you in formation, attack the target you pick (or the nearest
transport), hold their fire on torpedo approaches and make smoke as they withdraw.

## How to open and play
1. Start Godot 4.7.2. In the Project Manager choose **Import**, pick
   `project.godot` in this folder, then **Import & Edit**.
2. The first time, Godot spends a minute importing the ship models.
3. Press **F5** (or the ▶ Play button at the top right) to run the game.

## Controls
| Key / mouse | Action |
|---|---|
| W / S | Engine telegraph up / down (Back, Stop, 1/3, 2/3, Std, Full, Flank) |
| A / D | Rudder 5° left / right; Q centers the rudder |
| M | Switch aim: Crew (automatic) or Manual (mouse) |
| F | Crew aim: open / cease fire on the target |
| Left click | Crew aim: pick a target. Manual aim: fire where you click |
| Right click | Pick a target (both modes) |
| Tab | Next target |
| T | Torpedo aim: lanes follow the mouse, a lead marker shows where to aim, click to fire (T or Esc to cancel) |
| Z | Lay a smoke screen |
| V | Follow salvos on / off |
| C | Camera on the enemy target / back on your own ship |
| Space | Tactical pause |
| 1 / 2 / 3 | Slow ¼× / normal / fast 3× |
| Mouse wheel | Zoom; drag to look around (the camera unlocks); Esc locks it back on the ship |

## What's in this build
- Enemy AI that fights as a fleet: destroyer divisions keep formation, run in for
  torpedo attacks, break away under smoke and come back; a convoy escort screens its
  charges and drives off attackers; lone ships mix tactics (open range, zigzag, cross
  your bow, work for a torpedo shot, hide in smoke, pull back when hurt).
- Japanese destroyer character: faster and more agile than a Fletcher, lighter guns,
  Long Lance torpedoes fired from long range at night before you see them, then a
  high-speed turn away. They avoid gun duels while they still have torpedoes.
- Hit reports say what broke: "Hit aft: Mount 54 knocked out; flooding aft, starboard
  side". Misses and routine firing are no longer reported.
- Camera: "Camera on" picker (own ship / enemy target, key C); the camera stays locked
  on the chosen ship until you drag the view, Esc locks it back.
- Live 3D ships seen from above, built from the reference photos. Guns, torpedo
  tubes, director and light AA turn to their targets.
- Semi-realistic scale: 5-inch guns reach about 8 km, the enemy starts ~12 km away
  beyond sight, and the briefing tells you where they were reported.
- Gunnery: crew aim (solution improves with spotted salvos) or manual point and
  click with a range / time-of-flight reticle and a lead marker.
- Torpedoes (Mark 15 vs. Type 93 Long Lance), duds, wake warnings.
- Module damage, holes and flooding, list and trim, fires, crew losses lowering
  efficiency, rare magazine explosions (setting: Historical / Reduced / Off).
- Weather: clear, overcast, fog, night (star shells, gun flashes, radar).
- Effects: wakes, splashes, smoke, fires, oil slicks, floating debris.
- Smoke, gun smoke, fire and flash sprites from the **Kenney Smoke Particles** pack.
- Whitewater foam and water detail textures from the **Boujie Water Shader**.
- Ship fires and shell / torpedo / magazine explosions from **PYROLUX Lite**
  (switch them on and off with the "PYROLUX effects" button).
- Placeholder sounds made in code. Put real `gun`, `boom`, `splash`, `torp`,
  `alarm` .wav/.ogg files in `assets/sounds/` and they are used instead.

## Project layout
| Path | What it is |
|---|---|
| `scenes/battle.tscn` | Main scene (everything else is created by scripts) |
| `scripts/data.gd` | Ship classes, telegraph, weather — numbers to tune |
| `scripts/battle.gd` | Simulation: gunnery, torpedoes, damage, AI, camera |
| `scripts/ship.gd` | One ship's state and its 3D model |
| `scripts/hud.gd` | Instruments, markers, briefing, action report, input |
| `scripts/fx.gd` | Particles and lights |
| `scripts/sfx.gd` | Sounds |
| `shaders/` | Sea and particle shaders |
| `assets/models/` | Ship models (.glb) |

Design doc: https://claude.ai/artifact/6DsTxwe8UHnRugVtDqbLH2

## Third-party assets and licenses
| Asset | License | Notes |
|---|---|---|
| Kenney Smoke Particles (`assets/fx/kenney/`) | CC0 | Free for any use, credit optional |
| Boujie Water Shader textures (`assets/textures/boujie/`) | MIT | Keep `LICENSE.md` with the files |
| PYROLUX Lite (`addons/pyrolux_fx/`) | Free to use in the game; **do not share or resell the addon files** | Fine inside exported game builds. Before sharing this project folder, delete `addons/pyrolux_fx/`; the game runs without it and falls back to the built-in effects. |
