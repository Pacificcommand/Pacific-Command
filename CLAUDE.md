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
| `scenes/ops.tscn` + `scripts/ops.gd` | Operations map: campaign state (`Game.campaign`), sailing, contacts, operations cards, engage -> battle (`Game.mission`), results back (`Game.last_result`) |
| `scripts/war.gd` | War data: zones (jp/us dates), bases, OPERATIONS timeline, owner/activity by day, date helpers (day 0 = 7 Dec 1941) |
| `scripts/career.gd` + `career_panel.gd` | Career rules: officers, crew training, captain XP/rank/skills, refits, medals, difficulty; `Career.mod(key)` gives the battle its modifiers; the career screen |
| `scripts/story.gd` | Story layer: dispatch briefings, EVENTS newsreel cards, letters/diaries, after-action reports |
| `scripts/missions.gd` | Mission plans (convoy escort, shore bombardment, rescue), threat rating, reputation rewards, rank caps, support-ship catalogue; `build()` turns a plan into a battle (the operations map uses it) |
| `scripts/terrain.gd` | Islands: `height_at(x, z)` for grounding, shore targets and shells on the beach |
| `scripts/air.gd` | Air war: squadrons (launch, strike, CAP, scout, return, rearm), flak, dogfights, carrier AI. `Data.AIRCRAFT` has the plane stats |
| `scripts/data.gd` | GUNS, ARCS, TYPES (ship classes), TELE, WEATHER: the numbers to tune |
| `scripts/battle.gd` | Simulation: missions (`_setup_*`), gunnery, torpedoes, damage, AI, camera, test flags |
| `scripts/ship.gd` | One ship: state, geometry helpers, model sync (mounts rotate on glb nodes) |
| `scripts/hud.gd` | All UI (built in code), overlay markers, briefing, action report, input |
| `scripts/fx.gd` / `sfx.gd` | Particles (MultiMesh layers) and lights / placeholder sounds |
| `shaders/` | Ocean and particle shaders |
| `assets/models/*.glb` | Ship models, built by `tools/ship_builder` |
| `tools/ship_builder/` | Python (numpy) mesh builder: `geom.py` primitives; hand-built classes one file each (fletcher, kagero, pt_elco, daihatsu, merchant); `warship.py` parametric parts + `specs.py` (one spec dict per class, with its game DATA); `build_all.py` builds every .glb; `gen_data.py` writes `scripts/ship_types.gd` from specs.DATA; `preview.py NAME` renders /tmp/previews/NAME.png (top + oblique) to check against the photos |
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
--pause (open the pause menu) --shot=PNG --frames=N --quit`. Menu screenshots: `--menushot=PNG [--settings]`. Career dry run: `--careertest`. Map test: `--ops=PNG` (`--career` opens the career panel first) (runs the map fast, screenshots; add `--engage` plus battle flags to fight the first contact).
Keys in hud.gd go through `Game.pressed(e, "action")`, never raw keycodes; add new actions to `Game.ACTIONS`. Godot 4.7.2 Linux binary:
https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
Watch for "Cannot infer the type" parse errors (use `=` not `:=` when the value is a Variant).

## Adding a ship class
1. Add `spec('name', ...)` and `DATA['name']` in `tools/ship_builder/specs.py` (positions in m, x forward, y up, z starboard).
2. `python3 preview.py name` and compare with the PDF; then `python3 build_all.py && python3 gen_data.py`.
3. `godot --headless --path . --import` so the new .glb is imported. Weapon group names in the spec = `mounts[].g` in DATA.

## Commits
Commit each playable step with a clear message; push to `main`. Keep the README controls table current.
