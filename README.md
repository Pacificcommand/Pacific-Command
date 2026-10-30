# Pacific Command (build 0.9)

WWII Pacific naval game for PC, made in **Godot 4.7.2**.

**Campaign:** from the main menu, start a campaign in December 1941, August 1942,
November 1943 or October 1944 with the ship of your choice. The operations map shows
the Pacific from Pearl Harbor to Japan: sea zones held by either side, bases, and
contacts (Tokyo Express runs, convoys, barges, submarines, task forces, carrier
forces, bombardment requests, rescues, convoys to escort) that appear where the war
is busy. Click the sea to set a course, run the clock (pause / 1 h per 3 s / fast /
very fast), sail within 60 nm of a contact and engage it: the battle opens with the
contact's force and the weather of the hour. Historical operations (Savo, Midway,
Guadalcanal, Leyte...) arrive on their dates and offer you a part. Your results nudge
the war: wins bring the Allied advance forward, losses hold it back. After the
surrender the Pacific stays open for patrols.

**Single battle:** twelve stand-alone missions picked on the briefing screen (most
let you choose your ship), each with a threat rating; reputation buys support ships
before the battle, capped by rank:

- **Convoy escort:** keep four Liberty ships alive against three raiding destroyers and
  a submarine. **Shore bombardment:** silence two coastal batteries and a supply dump
  on an island (mind the shoals). **Rescue:** pick up three rafts of survivors off an
  enemy coast before a Japanese destroyer arrives.

- **Carrier strike:** Essex, Enterprise or Bataan with a screen against Shokaku, Zuikaku
  and Zuiho 30 km away. Launch your strike (L), keep fighters up, set the AA priority.
- **Submarine patrol:** USS Wahoo against an escorted convoy: dive (X), shoot from
  periscope depth, go deep and slip away from the depth charges.
- **Submarine hunt:** a destroyer escort screening an escort carrier against two
  I-boats: sonar, hedgehog (H) and depth charges (G).

- **Cruiser night action:** a light cruiser (Cleveland, Helena or Atlanta) and two
  Fletchers against a Tokyo Express led by the cruiser Jintsu with four destroyers.
- **Battleship action:** Washington or South Dakota, with the other astern and four
  destroyers, against Kirishima, Atago, Takao, Nagara and escorts off Savo at night.
- **Fleet action:** Iowa (or Massachusetts, North Carolina, Baltimore) leading a task
  force against Yamato, Nagato, Kongo, Tone, Haguro and a destroyer screen by day.

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
3. Press **F5** (or the ▶ Play button at the top right) to run the game. The main menu
   opens; **New battle** goes to the mission briefing, **Load battle** resumes a save.

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
| Mouse wheel | Zoom; drag to look around (the camera unlocks); Home locks it back on the ship |
| L | Carriers and ships with floatplanes: launch an air strike at your target |
| X / E | Submarines: dive (periscope depth, then deep) / come up |
| G / H | Drop depth charges / fire the hedgehog |
| Esc | Pause menu: resume, save, load, settings, main menu |

All keys can be changed in Settings › Controls.

## What's in this build
- Career: seven named officers who earn XP from their own jobs and level up (each
  level adds 3% in their department), can be wounded or killed; crew training (green
  to elite) and morale per ship, crews stay with their ship, former ships are frozen
  in reserve; captain XP (a cut of everything) drives rank and gives skill points for
  per-ship-type skills; refits bought with supply points at a base following the real
  timeline (SG radar 1942, fixed torpedoes 1943...), taking yard time; repairs take
  days; medals (Navy Cross, Silver Star, Bronze Star, Purple Heart); difficulty
  (Ensign, Officer, Veteran, Ironman) chosen with a new campaign. Career screen from
  the map and the pause menu.
- The operations map (scripts/ops.gd, scripts/war.gd): 18 sea zones with historical
  ownership dates, 21 bases, 23 operations on the 1941-45 timeline, contacts generated
  from zone activity, time compression, campaign saved to user://campaign.json.
- Islands with beaches you can run aground on, coastal gun batteries that shoot back,
  Liberty ships, life rafts; threat ratings (Low to Extreme) from the enemy force;
  reputation earned by results and spent on support ships (destroyers to carriers)
  on the briefing, limited by rank. Sandbox career: Captain with 900 reputation,
  saved in user://career.json until the career build replaces it.
- Aircraft as weapons: carriers launch and recover fighter, dive-bomber and torpedo
  squadrons that fly out visibly, attack, dogfight, take flak and come home to rearm;
  cruisers and battleships launch floatplane scouts that report what they find.
  Air-search radar warns of incoming raids; AA fire has priority settings.
- Submarines: surfaced, periscope depth and deep; battery; sonar contacts that fade;
  depth-charge patterns and hedgehog; escorts that hunt; submarines that stalk convoys.
- 37 new ship classes built with the parametric warship builder, matched to the
  reference photos: US Mahan, Benson, Buckley, Gato, Atlanta, Brooklyn, Cleveland,
  Northampton, New Orleans, Baltimore, North Carolina, South Dakota, Iowa, Texas,
  Yorktown, Essex, Independence, Casablanca; Japanese Fubuki, Akizuki, Nagara, Myoko,
  Takao, Mogami, Tone, Kongo, Fuso, Ise, Nagato, Yamato, Akagi, Kaga, Hiryu, Shokaku,
  Zuiho, I-boat, subchaser. Every turret, mount, tube and director turns.
- Guns from 3-inch to 18.1-inch with armour penetration: light shells only scratch a
  battleship; big turrets train at 4 degrees a second and reload in half a minute.
- Your own task force: consorts keep station on you and engage your target; your
  destroyers run in with torpedoes when the enemy closes.
- Main menu, pause menu (Esc), settings (quality preset, fullscreen/resolution/v-sync,
  UI scale, volumes for music/effects/radio, key rebinding) saved between sessions,
  and five save slots for battles in progress.
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
