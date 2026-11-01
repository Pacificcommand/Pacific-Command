# Pacific Command (build 0.14)

WWII Pacific naval game for PC, made in **Godot 4.7.2**.

**Campaign:** from the main menu, start a campaign in December 1941, August 1942,
November 1943 or October 1944. Every career starts in a PT boat; rank earned in battle
unlocks bigger commands, requested in port. The operations map shows the Pacific from
Pearl Harbor to Japan: sea zones held by either side, bases, and **groups moving like
you do** - our convoys, destroyer patrols, task forces and submarines (blue), and the
Japanese Tokyo Express runs, convoys, task forces, barges and submarines (red, once
radar, aircraft or a friendly ship has found them). Groups that meet fight each other,
and the fight is marked on the map for a few hours: sail to it and join, intercept an
enemy group yourself, or sail with a friendly convoy as its escort and fight when it is
attacked. **Islands are the objectives.** Twenty-three real islands and bases (Wake, Tarawa, Kwajalein,
Truk, Rabaul, Guadalcanal, Munda, Saipan, Guam, Peleliu, Leyte, Iwo Jima, Okinawa...) fly a
flag and have coastal batteries. Drive off the guard fleet, then assault: a bombardment
action on a map shaped like the real island, batteries that shoot back; silence them and the
flag changes. A captured island spots for you, its base is yours, and a key island brings its
whole sea zone. Both AIs land on weakly held islands at the front and take them back when
they can; garrisons dig in a battery a month. Japanese torpedo-boat sections, picket boats
and barge columns are the common small fry for a young PT skipper; everything grows as
the war goes on. The map has real coastlines and islands and ships steer round them.
In a friendly port you repair, refit, request a new command and **recruit
ships for your squadron with reputation**; they sail with you and fight under your
orders until they are sunk. Click the sea to set a course, run the clock (pause / 1 h
per 3 s / fast / very fast). Historical operations (Savo, Midway, Guadalcanal,
Leyte...) arrive on their dates and offer you a part. Your results nudge the war. After
the surrender the Pacific stays open for patrols.

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
| Left click | Crew aim: pick a target. Manual aim: fire ONE gun where you click; click twice quickly for the full salvo. The reticle shows a reload ring per gun and a countdown, so you know when they are up |
| Right drag | Move the camera (it unlocks; Home locks it back). A plain right click picks a target. Settings can swap this to the left button |
| Tab | Next target |
| T | Torpedo aim: lanes follow the mouse, a lead marker shows where to aim, click to fire (T or Esc to cancel) |
| Z | Lay a smoke screen |
| I | Fire a star shell over the target (night and fog): everything under it is lit for half a minute |
| V | Follow salvos on / off |
| C | Camera on the enemy target / back on your own ship |
| Space | Tactical pause |
| 1 / 2 / 3 | Slow ¼× / normal / fast 3× |
| Mouse wheel | Zoom |
| L | Carriers and ships with floatplanes: launch an air strike at your target |
| X / E | Submarines: dive (periscope depth, then deep) / come up |
| G / H | Drop depth charges / fire the hedgehog |
| Esc | Pause menu: resume, save, load, settings, main menu |

All keys can be changed in Settings › Controls.

## What's in this build
- Story layer: campaign briefings arrive as naval dispatches; newsreel cards for the
  war's big days (Doolittle Raid, Midway, Yamamoto, Iwo Jima, the surrender...);
  letters home and diary entries from your officers after battles (Mail on the map);
  after-action reports written like the originals, kept with the ship's log.
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
  ownership dates, 21 bases, 23 operations on the 1941-45 timeline; friendly and enemy
  groups sail between bases and the front, hunt each other, fight (resolved by weight of
  metal when you are not there) and can be joined; detection by radar, friendly ships,
  air search and coastwatchers; time compression; campaign saved to user://campaign.json.
- Islands with beaches you can run aground on, coastal gun batteries that shoot back,
  Liberty ships, life rafts; threat ratings (Low to Extreme) from the enemy force;
  reputation earned by results and spent in port on ships for your squadron (PT boats
  to carriers), limited by rank; in single battles support is bought on the briefing.
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
- Survivors: when a friendly ship goes down her crew takes to rafts; come alongside slowly
  to take them aboard and they fill the gaps in your own crew. Your consorts keep station
  on you while cruising and fight independently under their senior ship once the action
  starts, so you can hang back or run in as you like.
- The ship is alive: a representative crew walks the decks while cruising, runs to the
  open gun mounts and the rails at general quarters, repair parties fight the fires, and
  when she goes down the men go to the side and over.
- Detection plate (top left): your concealment by sea (and how far your gun flashes are seen
  at night), how far your lookouts see a PT boat / destroyer / battleship in this weather,
  radar, main gun, secondary, AA, torpedo and sonar ranges, and a DETECTED / Not detected
  flag. Zoomed out, the overlay draws rings for concealment, main guns, secondaries, AA and
  radar. Small ships hide better (concealment scales with size); firing in the dark gives you
  away for three seconds, fires and star shells for longer.
- Your own main-battery shells are big and bright with long tails; secondaries and enemy
  shells are thinner and dimmer, so your salvo stands out.
- Orders to the ships in company (left side): Follow me, Engage at will, Fall back, Rescue
  survivors, Attack my target (ships or shore batteries) - for all ships or one at a time;
  click an order again to release the ship to its own judgement.
- Ship dial (bottom left, World of Warships style): your ship from above with every mount drawn where it points and coloured by state (ready, loading, cannot bear, knocked out), torpedo tubes with their count, the internal modules (engines to port, magazines to starboard, bridge, steering) by health, holes at the waterline, fires on deck and flooding filling the hull; a bearing ring with the target wedge; the telegraph beside it and crew / flooding / efficiency / list / fires underneath. One plate for the whole ship. Secondaries and AA always fire themselves; manual aim controls only the main battery.
- Effects: wakes, splashes, smoke, fires, oil slicks, floating debris.
- Smoke, gun smoke, fire and flash sprites from the **Kenney Smoke Particles** pack.
- Whitewater foam and water detail textures from the **Boujie Water Shader**.
- Ship fires and shell / torpedo / magazine explosions from **PYROLUX Lite**
  (switch them on and off with the "PYROLUX effects" button).
- Sound and music, all synthesised by the game itself (no audio files, nothing to
  license): gunfire by calibre, bursts, splashes, torpedoes, depth charges, sonar, flak,
  engines, fire, sea and wind beds by weather, a radio chime for dispatches, and five
  music tracks (title, operations map, battle, victory, defeat) that cross-fade as the
  action changes. Built on first run (a few seconds) and cached. Real recordings can
  replace any of them: see `assets/sounds/README.md`. Volumes in Settings.

## Project layout
| Path | What it is |
|---|---|
| `scenes/battle.tscn` | Main scene (everything else is created by scripts) |
| `scripts/data.gd` | Ship classes, telegraph, weather — numbers to tune |
| `scripts/battle.gd` | Simulation: gunnery, torpedoes, damage, AI, camera |
| `scripts/ship.gd` | One ship's state and its 3D model |
| `scripts/hud.gd` | Instruments, markers, briefing, action report, input |
| `scripts/fx.gd` | Particles and lights |
| `scripts/audio.gd` | Autoload `Audio`: synthesised sounds and music, ambience loops, cross-fades |
| `scripts/sfx.gd` | The battle's sound hooks (positions, weather, planes, fires, sonar) |
| `shaders/` | Sea and particle shaders |
| `assets/models/` | Ship models (.glb) |

## Skill tree
The Career screen opens on the skill tree: your own column first (a skill point per captain
level, in tiers by ship type plus general skills), then one column per department head -
executive, gunnery, torpedo, engineering, navigator, damage control, air group. Officers
earn XP doing their own job and a skill point every two levels; higher tiers need level
and a skill from the tier below. Everything learned feeds the battle through modifiers.

## Encyclopedia
From the main menu, the pause menu or the operations map: the real history of every ship
class in the game (with a turning 3D model and the game's figures), the aircraft, the
weapons and gear (guns, the Long Lance, radar, sonar, the torpedo scandal) and 25 battles
of the Pacific war from Pearl Harbor to Tokyo Bay.

## Windows build and Steam
`Project > Export > Windows Desktop` (or `tools\export_windows.bat`) makes a single
`build/windows/PacificCommand.exe`. `docs/STEAM.md` has the whole Steam checklist:
Steamworks setup, store assets, GodotSteam install, achievements (16, tracked in the
career even without Steam), cloud saves, and the SteamPipe upload scripts in `tools/steam/`.

Design doc: https://claude.ai/artifact/6DsTxwe8UHnRugVtDqbLH2

## Third-party assets and licenses
| Asset | License | Notes |
|---|---|---|
| Kenney Smoke Particles (`assets/fx/kenney/`) | CC0 | Free for any use, credit optional |
| Boujie Water Shader textures (`assets/textures/boujie/`) | MIT | Keep `LICENSE.md` with the files |
| PYROLUX Lite (`addons/pyrolux_fx/`) | Free to use in the game; **do not share or resell the addon files** | Fine inside exported game builds. Before sharing this project folder, delete `addons/pyrolux_fx/`; the game runs without it and falls back to the built-in effects. |
