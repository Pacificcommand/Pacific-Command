# Sounds and music

**As shipped, the game needs no audio files.** Every effect and every music track is
synthesised by `scripts/audio.gd` the first time the game runs (about 5-10 s, on a
background thread while the title screen is up) and cached under
`user://audio_cache/`. Nothing in that audio is third-party, so there is nothing to
license or credit. See `CREDITS.txt`.

## Replacing a sound with a recording

Drop a file in this folder with one of the names below (`.wav` or `.ogg`) and it is used
instead of the synthesised one. Several takes of the same sound can be given as `name_1`,
`name_2`, ... and one is picked at random each time (the gun reports work this way). Music goes in `assets/music/` as `menu`, `map`, `battle`,
`victory`, `defeat` (`.ogg` preferred). Loops must be seamless. Then add a line to
`CREDITS.txt` for each file: title, author, source link, licence.

| Name | What it is | Length |
|---|---|---|
| `gun_small` | 20-40 mm or 3-inch gun report | ~0.7 s |
| `gun_medium` | 5-inch / 14 cm gun report | ~1 s |
| `gun_large` | 8-inch and bigger, battleship salvo | ~2 s |
| `boom` | Shell burst on a ship | ~2 s |
| `boom_big` | Torpedo hit, magazine explosion | ~4 s |
| `bomb` | Aerial bomb hit | ~2.5 s |
| `splash` | Shell splash | ~1 s |
| `torp` | Torpedo launch (compressed air) | ~1.3 s |
| `alarm` | General quarters alarm | ~1.6 s |
| `flak` | Heavy AA burst (5-inch) heard at a distance | ~0.9 s |
| `aa_bofors` | Bofors four-round clip | ~0.8 s |
| `aa_mg` | Machine-gun burst (20 mm / .50 cal) | ~0.55 s |
| `mg` | Strafing machine guns | ~0.6 s |
| `dc` | Depth charge, heard through the hull | ~3 s |
| `ping` | Sonar ping | ~1.4 s |
| `click` | Button click | short |
| `radio` | Radio static and message beeps (dispatches, cards) | ~1 s |
| `creak` | Hull groan of a sinking ship | ~3.5 s |
| `bell` | Ship's bell | ~2.5 s |
| `plane` | Radial engine drone, **loop** | 2 s |
| `fire` | Fire crackle, **loop** | 3 s |
| `ocean` | Sea, **loop** | 8 s |
| `wind` | Wind, **loop** | 8 s |
| `rain` | Rain, **loop** | 4 s |

Only use recordings whose licence allows commercial use without a fee: **CC0**, or
royalty-free packs that permit games on Steam. Avoid CC-BY-NC and anything "for
personal use". Keep each download's licence text.

## Where to look (free, commercial-OK)

These sites could not be reached from the build environment, so these are the places to
start rather than verified file names. Download into your Downloads folder, pick and trim
in Audacity (free), export as `.ogg` or 16-bit `.wav`, rename to the names above.

- **Sonniss GDC bundles**: https://sonniss.com/gameaudiogdc - tens of GB of professional
  libraries, free for commercial games (royalty-free licence included). Search the
  bundles for "cannon", "artillery", "explosion", "ocean", "wind", "radial engine",
  "sonar". The best single source for a game like this.
- **Kenney**: https://kenney.nl/assets/impact-sounds and
  https://kenney.nl/assets/interface-sounds (CC0): impacts and UI clicks.
- **freesound.org**: search with the licence filter set to Creative Commons 0, e.g.
  https://freesound.org/search/?q=naval+gun&f=license:%22Creative+Commons+0%22 ;
  likewise "depth charge", "sonar ping", "ocean waves loop", "radial engine", "ship bell",
  "morse code".
- **OpenGameArt**: https://opengameart.org/art-search-advanced?keys=explosion&field_art_licenses_tid[]=4
  (CC0 filter) for explosions, ambience and music.
- **Music**: Kevin MacLeod at https://incompetech.com is CC-BY (needs a credit line,
  which `CREDITS.txt` is for); https://opengameart.org has CC0 orchestral tracks. WWII-era
  recordings themselves (service songs, period broadcasts) are usually NOT free to use -
  leave them out.
