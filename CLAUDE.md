# Pacific Command: notes for AI assistants

WWII Pacific naval game for PC (Steam), Godot **4.7.2**, GDScript. Owner: Matt (no programming
experience; explain in plain words, he tests by playing). Top-down 3D view of live 3D ships.

## Source of truth
- **Design doc** (all decisions, build plan, Build log with the next-build checklist):
  https://claude.ai/artifact/6DsTxwe8UHnRugVtDqbLH2 (a Claude Docs document). Read it first;
  record new decisions and tick off checklist items there.
- **Reference photos** for every ship class: `docs/Ship Reference Photos.pdf` (44 pages, with
  notes on which photos are uncertain). Build models to match these.
- Matt's working copy: `C:\Users\mattwhodak\Documents\Pacific Command` on his Windows PC.
  He opens it in Godot 4.7.2 and presses F5. Deliver every build there AND push it here.

## Layout
| Path | What it is |
|---|---|
| `scenes/menu.tscn` + `scripts/menu.gd` | Main scene: title screen (3D ship + menu); jumps to the battle when test flags are given |
| `scenes/battle.tscn` | The battle; everything in it is built by scripts |
| `scripts/game.gd` | Autoload `Game`: settings (user://settings.cfg), key bindings (InputMap actions), save slots (user://saves) |
| `scripts/ui.gd` | Static UI builders (panels, buttons, sliders) shared by menu, settings, pause and slot panels |
| `scripts/settings_panel.gd`, `slot_panel.gd` | Settings screen; save/load slot picker |
| `scripts/ai.gd` | Ship AI: fleets, roles, solo tactics, Japanese destroyer doctrine, PT boats, transports, submarines, escorts hunting |
| `scenes/ops.tscn` + `scripts/ops.gd` | Operations map: campaign state (`Game.campaign`: groups, fights, squadron, attached, intercept), sailing, moving friendly/enemy groups (`_spawn_group`, `_hunt`, `_meet`, `_resolve_fights`), detection (`_detect`), join/intercept/attach, port menus (repair, refit, command, recruit squadron), engage -> battle via `Missions.encounter` (`Game.mission`), results back (`Game.last_result` incl. `lost_friends`). Islands: `C.islands[id] = {side, garrison, grow}`, `_capture`, `_ai_captures`, `_spawn_guards`, `_assault` -> `Missions.island_assault`; `C.zone_owner`/`C.base_owner` override history (War.owner reads zone_owner). Tests: `--ops=PNG --days=N [--engage|--joinfight|--assault ...battle flags]` |
| `scripts/geo.gd` | Map geography: LAND coastline polygons, DOTS small islands, ISLANDS (capturable: zone, base, garrison, key, bombardment shape), `on_land`, `track_blocked`. The map steers round land (`_advance` in ops.gd) |
| `scripts/war.gd` | War data: zones (jp/us dates), bases, OPERATIONS timeline, owner/activity by day, date helpers (day 0 = 7 Dec 1941) |
| `scripts/career.gd` + `career_panel.gd` | Career rules: officers, crew training, refits, difficulty. MEDALS replace XP and skill trees: `MEDAL_DEFS` (real WWII USN decorations, who earns each, the deed, the buff per award, max awards = gold stars, ribbon colours), `_award_medals` reads the battle `tally` in `apply_battle`; `Career.mod(key)` = refits + the captain's medals + each fit officer's medals. Rank comes from reputation (`RANK_REP`, never goes down); each promotion queues `c.offers` -> a letter on the map (`ops._check_offers`) offering ships for the squadron (`OFFERS`, `in_service` swaps classes not yet built). `career_panel.gd` = the service record (decorations, ship, officers, log, all medals) |
| `scripts/dock.gd` | `DockPanel`: the home base in port (opens on arriving at a friendly port, "Go to the dock", or Career in port). Own 3D world in a SubViewport: the ship model moored bow +x with the quay to port, deck heights rasterised from the model's triangles (`height_at`), cartoon sailors (`_figure` look dicts; tasks haul/mop/sight/stroll), crane, sheds, palms; the captain and officers in a line (`LOOKS` per post), the bottom bar pans the camera to each, they salute, ribbons drawn over the head. Port business (repair, refit, new command) calls back into ops. Test: `--dock=PNG [--docksel=N] [--dockship=type] [--medals] [--frames=N]` on `res://scenes/ops.tscn`; `--offer=RANK` with `--ops=PNG` shows a promotion letter |
| `scripts/encyclopedia.gd` + `encyclopedia_panel.gd` | In-game encyclopedia: real history of every ship class (SHIPS by type_id), BATTLES, AIRCRAFT, WEAPONS; the panel (menu, pause, map) shows the article with a turning 3D model and the game's figures from Data.TYPES. Test: `--menushot=x.png --encyclopedia --cat=0..4` |
| `scripts/story.gd` | Story layer: dispatch briefings, EVENTS newsreel cards, letters/diaries, after-action reports |
| `scripts/missions.gd` | Mission plans (convoy escort, shore bombardment, rescue), threat rating, reputation rewards, rank caps, support-ship catalogue; `build()` turns a plan into a battle (the operations map uses it) |
| `scripts/terrain.gd` | Islands: `height_at(x, z)` for grounding, shore targets and shells on the beach |
| `scripts/air.gd` | Air war: squadrons (launch, strike, CAP, scout, return, rearm), flak, dogfights, carrier AI. `Data.AIRCRAFT` has the plane stats. Carrier flight decks (`decks`, the deck section at the end): the whole air group is parked on deck (as many as fit, `T.fdeck` from specs: rows of folded planes, fighters forward), launches from the front of the pack (taxi, spread wings, roll, off the bow), respots rows forward for recovery and aft for launches, landings catch a wire and park forward, lost planes come back from the hangar every `REPLACE_T` s while spares last (`dk.spares`, 20% of the deck park). Player orders per squadron: `command(sq, attack|patrol|land, ship)`, `can`, `status` (the HUD air group panel, K; `hud.air_pick` = waiting for a target click); states add `hold` (circling the carrier); bombers drop once (`armed`) and must land to rearm; player's fighters stay up until recalled; fighters escort bombers going for the same ship (`_escortee`). Attack runs fly each plane separately (`_start_run`/`_step_runs`/`_end_run`: dive push-over in turn, torpedo anvil from both bows, strafing passes; bombs and torpedoes are objects in `bombs`); planes shot down fall (`_kill_plane`, `falling`: fates spin, flamer, breakup, ditch (low planes; settles and sinks); `fx.plane_splash`; sounds plane_hit, plane_dive, crash); formations are vics / finger-fours (`_slot`), props spin (`Prop` node). `--decktrace` prints the player's deck. Floatplanes keep the catapult (`Float` nodes) |
| `scripts/data.gd` | GUNS, ARCS, TYPES (ship classes), TELE, WEATHER: the numbers to tune |
| `scripts/battle.gd` | Simulation: missions (`_setup_*`), gunnery, torpedoes, damage, AI, camera, test flags |
| `scripts/ship.gd` | One ship: state, geometry helpers, model sync (mounts rotate on glb nodes) |
| `scripts/hud.gd` | All UI (built in code), overlay markers, briefing, action report, input |
| `scripts/fx.gd` | Particles (MultiMesh layers) and lights. Lasting battle smoke: `gun_smoke`, `hit_smoke`, `plume` (burning ships), `funnel_smoke` (power and engine damage), `oil_fire` (wrecks; battle.gd `wrecks`), `flak_burst` (heavy 5-inch bursts and light self-destruct puffs; air.gd `_flak`), `shell_splash(x,z,size)` (water columns by gun size factor: 5-inch 1.0 ~18 m, 8-inch 1.7 ~35 m, 16-inch 2.6 ~70 m; SPLASH particles with vy rise and fall at `SPRAY_G`); smoke has its own ceiling (`top`) and greys as it ages; `billboard` turns puffs to face the camera (tracers stay flat). Budget: `CAP` 12000, wake foam capped at `FOAM_MAX`; the sea layer redraws every 3rd frame, smoke every 2nd. `--fxprof` prints the render cost |
| `scripts/crew.gd` | The visible crew: small figures per ship (MultiMesh) that stroll when cruising, run to open mounts/rails at GQ, fight fires, and go over the side when sinking. Deck height from mount bases (`m.deck_y`, `m.lz` set in `Ship.load_model`) |
| `scripts/audio.gd` | Autoload `Audio`: ALL sound and music, synthesised in code on first run and cached in user://audio_cache (bump CACHE_VERSION after changing a sound). `Audio.at/ui/loop/ambience/music`. Files in assets/sounds|music override by name (see assets/sounds/README.md). `--audiotest` builds the bank synchronously in headless |
| `scripts/steam.gd` | Autoload `SteamHook`: achievements (tracked in the career; sent to Steam when the GodotSteam GDExtension is installed), rich presence. `check_battle(B)` on settle, `check_day` on the map |
| `export_presets.cfg`, `tools/export_windows.*`, `tools/steam/*.vdf`, `docs/STEAM.md` | Windows .exe export (one embedded-pck exe, icon.ico) and the Steam upload/checklist. Templates: `Godot_v4.7.2-stable_export_templates.tpz` from the GitHub release, only `windows_*_x86_64.exe` needed in `~/.local/share/godot/export_templates/4.7.2.stable/`; then `godot --headless --export-release "Windows Desktop" build/windows/PacificCommand.exe` |
| `scripts/sfx.gd` | Battle sound hooks: gun by calibre, per-frame ambience/fire/plane drone/sonar pings |
| `shaders/` | Ocean and particle shaders |
| `assets/models/*.glb` | Ship models, built by `tools/ship_builder` |
| `tools/ship_builder/` | Python (numpy) mesh builder: `geom.py` primitives; hand-built classes one file each (fletcher, kagero, pt_elco, daihatsu, merchant); `warship.py` parametric parts + `specs.py` (one spec dict per class, with its game DATA); `detail.py` surface detail shared by every class (`Paint`: plating shades, rust, Measure 32 dazzle via `Mesh.paint`; portholes, doors, ladders, hatches, lockers, rafts, rigging, railings); `build_all.py` builds every .glb (US classes also as `NAME_m22.glb` in dazzle; floatplanes are nodes `Float1..`; carrier deck planes are spawned by air.gd); `aircraft_models.py` the detailed carrier aircraft, one per type at real size (fuselage loft, cowling, propeller, framed canopy, gear, markings, wing folds as the real type folded): `plane_<t>.glb` flying, `_deck` wheels down, `_folded` parked; `parked_width` feeds `park_w` in Data.AIRCRAFT; `gen_data.py` writes `scripts/ship_types.gd` from specs.DATA; `preview.py NAME` renders /tmp/previews/NAME.png (top + oblique) to check against the photos; `closeup.py NAME [x] [dazzle]` a close oblique for detail checks |
| `scripts/ship_types.gd` | GENERATED ship classes (do not edit; change specs.py and run gen_data.py). `Data.TYPES` merges these with the hand-built `Data.BASE_TYPES` |
| `addons/pyrolux_fx/` | PYROLUX Lite fire/explosion addon (license: do NOT redistribute; repo must stay private) |

## Conventions
- World: x east, z south, y up. Headings clockwise radians from north (-z). Ship local: lx forward,
  lz starboard. Models: internal x fwd/y up/z stbd, exported to glTF with forward = -Z.
- Each turning part of a model is its own named group/node (Mount51, Torpedo1, ...) with its pivot;
  `TYPES[...].mounts[].g` must match. Mount `stow` = rotation the mesh was built at; `arc` from `ARCS`.
- Semi-realistic scale: gun, radar and spotting ranges are about half of real; ship speeds real;
  torpedoes 1.6x real (`Data.TORP_SPEED`). Battles 10-15 min, big ones ~30.
- Messages: only noteworthy events (hits with what was damaged, fires, flooding, contacts, sinkings).
- Keep the game runnable without PYROLUX (`fx.has_pyro()`).

## Testing (headless works; there is no GPU, use the compatibility renderer for screenshots)
```
godot --headless --path . --import
godot --headless --path . --quit-after 3 -- --scenario=barges --auto --start --run=600 --fire --trace
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-method gl_compatibility \
  --rendering-driver opengl3 -- --scenario=convoy --start --run=300 --view=wide --shot=out.png --quit
```
Flags: `--scenario=dd|barges|convoy|cruisers|bbs|fleet|carriers|subpatrol|subhunt|escort|bombard|rescue --strike (launch the player's strike at t=20) --weather=clear|overcast|fog|night --start --run=SECONDS
--fire --auto (AI drives the player too) --trace (prints messages and ship states) --view=close|ship|wide|tac
--cam=player|target --nofollow --aim=manual --torpaim=DEG --save=SLOT (after the run) --load=SLOT
--pause (open the pause menu) --shot=PNG --frames=N --quit`. Recording/trailer flags: `--seed=N` (repeatable battle; rendered runs repeat each other but not headless ones), `--focus=Ship_Name` (camera on any ship), `--height=M`, `--tilt=DEG --yaw=DEG --orbit=SPEED` (angled cinematic camera), `--nohud`, `--scenario=duel [--duelrange=M]` (Washington vs Kirishima alone), `--scenario=ddcv [--cvrange=M] --torpat=SECONDS` (Johnston and Hoel torpedo Shokaku; the carrier steams straight, holds fire, has no planes), `--mid=Ship_A,Ship_B` (camera halfway between two ships), `--chase=dive|torpedo|fighter [--chaseatk --chasedist=M --chaseyaw=DEG --chaseelev=DEG]` (ride with the player's squadron), `--airorders [--airpick]` (test: separate squadron orders, land and refit), `--chase=falling` (follow planes going down to their splash), `--salvolive=T,SIZE,N[,Ship_Name]` (N splashes straddle a ship T s into a clip), `--crashlive=T[,fate]` (shoot down one of our planes T s in), `--splashtest [--splashat=S]` (5/8/16-inch splashes beside the player); these scenarios are not in the menu. Clips: add Godot's `--write-movie out.avi --fixed-fps 30 --quit-after FRAMES` (first ~3 frames are the menu). Menu screenshots: `--menushot=PNG [--settings] [--menufire]` (`--menufire` fires a salvo and saves PNG_0..3 during it). Career dry run: `--careertest`. Map test: `--ops=PNG` (`--career` opens the career panel first) (runs the map fast, screenshots; add `--engage` plus battle flags to fight the first contact).
Keys in hud.gd go through `Game.pressed(e, "action")`, never raw keycodes; add new actions to `Game.ACTIONS`. Godot 4.7.2 Linux binary:
https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
Watch for "Cannot infer the type" parse errors (use `=` not `:=` when the value is a Variant).

## Adding a ship class
1. Add `spec('name', ...)` and `DATA['name']` in `tools/ship_builder/specs.py` (positions in m, x forward, y up, z starboard).
2. `python3 preview.py name` and compare with the PDF; then `python3 build_all.py && python3 gen_data.py`.
3. `godot --headless --path . --import` so the new .glb is imported. Weapon group names in the spec = `mounts[].g` in DATA.

## Commits
Commit each playable step with a clear message; push to `main`. Keep the README controls table current.

## Dev update video (Matt's standing rule, 3 Nov 2026)
For every change worth noting (new content, visual updates, new features; not plain bug fixes), make a
**20-30 second dev update video** showing the changes, with **burnt-in captions** saying what changed, and send it
to Matt with the build. Record clips with Movie Maker (`--write-movie x.avi --fixed-fps 30 --quit-after FRAMES`,
drop the first few menu frames) using `--nohud --weather=clear --seed=N` and the camera flags; the cinematic
camera is `--view=cine` with `--cinezoom=K --cineelev=DEG --cineyaw=DEG` (yaw relative to the ship's heading),
`--scheme=m22` shows the dazzle models. One clip per change (4-6 s each), a caption panel lower left (title +
one line), a small "DEV UPDATE" tag, an end card; 1920x1080, 30 fps, H.264.
