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
| `scenes/battle.tscn` | Main scene; everything else is built by scripts |
| `scripts/data.gd` | GUNS, ARCS, TYPES (ship classes), TELE, WEATHER: the numbers to tune |
| `scripts/battle.gd` | Simulation: missions (`_setup_*`), gunnery, torpedoes, damage, AI, camera, test flags |
| `scripts/ship.gd` | One ship: state, geometry helpers, model sync (mounts rotate on glb nodes) |
| `scripts/hud.gd` | All UI (built in code), overlay markers, briefing, action report, input |
| `scripts/fx.gd` / `sfx.gd` | Particles (MultiMesh layers) and lights / placeholder sounds |
| `shaders/` | Ocean and particle shaders |
| `assets/models/*.glb` | Ship models, built by `tools/ship_builder` |
| `tools/ship_builder/` | Python (numpy) mesh builder: `geom.py` primitives, one file per class, `build_all.py` |
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
Flags: `--scenario=dd|barges|convoy --weather=clear|overcast|fog|night --start --run=SECONDS
--fire --auto (AI drives the player too) --trace --view=close|ship|wide|tac --nofollow
--aim=manual --torpaim=DEG --shot=PNG --frames=N --quit`. Godot 4.7.2 Linux binary:
https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
Watch for "Cannot infer the type" parse errors (use `=` not `:=` when the value is a Variant).

## Commits
Commit each playable step with a clear message; push to `main`. Keep the README controls table current.
