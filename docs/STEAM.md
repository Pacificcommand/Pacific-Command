# Pacific Command: Windows build and Steam

## 1. Building the Windows .exe

The project has a ready export preset (`export_presets.cfg`, "Windows Desktop"): one
64-bit `.exe` with everything embedded, icon and version info set, PYROLUX included
(the licence allows it inside a compiled game; the source stays in the private repo).

In the Godot editor: **Project > Export... > Windows Desktop > Export Project**, save as
`build/windows/PacificCommand.exe`. The first time, Godot asks to download the export
templates for 4.7.2 (about 1 GB): click **Manage Export Templates > Download and Install**.
For the icon and version info to be written into the .exe on Windows, Godot needs
**rcedit**: download `rcedit-x64.exe` from https://github.com/electron/rcedit/releases and
set its path in **Editor > Editor Settings > Export > Windows > rcedit**. Without it the
game still exports and runs; it just has the default Godot icon.

Or from a terminal: `tools\export_windows.bat` (same thing).

Test the .exe on a clean PC (no Godot installed). First run makes the audio cache
(`%APPDATA%\Godot\app_userdata\Pacific Command\audio_cache`) - a few seconds on the title
screen. Settings and saves live in the same folder.

### Code signing (recommended before release)
An unsigned .exe triggers Windows SmartScreen ("Windows protected your PC"). Steam itself
does not require signing, and SmartScreen does not apply to games launched through Steam,
so this can wait. For a signed build buy an OV/EV code-signing certificate (Sectigo,
DigiCert, Certum - from about $70/yr for an open-source-style OV) and fill in the
`codesign/*` options in the export preset.

## 2. Steam checklist

1. **Steamworks account and app**: https://partner.steamgames.com - pay the $100 app fee
   (recouped after $1,000 in sales), fill in company/tax forms, create the app. Note the
   **App ID** and the Windows **Depot ID** (usually App ID + 1).
2. **Store page**: see the asset list below. Needs a trailer or at least 5 screenshots
   (1920x1080), a short and a long description, tags (Naval, Simulation, WWII, Strategy,
   Historical), system requirements, and content survey (war violence, no blood/gore).
   The store page must be public for at least 2 weeks before release ("Coming soon").
3. **Build**: export the .exe (section 1), then upload with `tools/steam/upload.bat`
   after filling in App/Depot IDs in `tools/steam/app_build.vdf` and
   `tools/steam/depot_build.vdf`. The upload goes to the Builds page; set it live on the
   `default` branch there (or use a `beta` branch for testers with a password).
4. **Launch options** (Steamworks > Installation > General): executable
   `PacificCommand.exe`, Windows 64-bit.
5. **Steam features now supported by the code**:
   - *Achievements*: `scripts/steam.gd` defines 16 (list below); they are tracked in the
     career with or without Steam. Create them on the Steamworks **Achievements** page with
     the same API names (`first_blood`, `tin_can`, ...). Each needs a 64x64 unlocked and
     locked icon.
   - *Rich presence*: `SteamHook.presence("...")` - add tokens on the Rich Presence page
     (`#Status_Menu`, `#Status_Custom` with `{#text}`).
   - *Cloud saves*: enable Steam Cloud with **Auto-Cloud** for the root
     `%APPDATA%/Godot/app_userdata/Pacific Command` folder (WinAppDataRoaming), 50 MB,
     excluding `audio_cache/`.
6. **GodotSteam** (the bridge between Godot and the Steam client): download the
   **GDExtension** build for Godot 4.7 from https://godotsteam.com/ (or
   https://github.com/GodotSteam/GodotSteam/releases, the `gdextension` zip) and unzip it
   into `addons/godotsteam/` so that `addons/godotsteam/godotsteam.gdextension` exists.
   Put `steam_api64.dll` from the Steamworks SDK (`redistributable_bin/win64/`) next to
   the .exe (GodotSteam's zip includes it). While testing outside Steam, put a
   `steam_appid.txt` containing the App ID next to the .exe (the depot script excludes it
   from uploads). Set `APP_ID` in `scripts/steam.gd`. Nothing else changes: the game
   detects the extension at run time.
7. **Steam Deck**: the game runs on Proton (Godot 4 + OpenGL/Vulkan). For a Deck Verified
   badge add controller support (the Input Map actions in `Game.ACTIONS` make this a matter
   of adding joypad events) and make sure the UI reads at 1280x800 (the UI scale setting
   helps). A native Linux export can be added later from the same preset file.
8. **Legal**: the EULA page can use Steam's default. The credits must list the
   third-party assets in `README.md` (Kenney CC0, Boujie water shader, PYROLUX Lite) and
   anything added to `assets/sounds/CREDITS.txt`. Historical names (ships, officers,
   operations) are facts and free to use; do not use Navy insignia or the Steam Deck logo
   in your own branding.
9. **Early Access** is a fit for this game: describe what works (campaign to 1945,
   30+ ship classes, air and submarine warfare) and what is planned (voice, more ship
   models, multiplayer or not). Steam requires the Early Access description to be honest
   about the state of the game and updated as it changes.

### Store assets to prepare
| Asset | Size |
|---|---|
| Header capsule | 920x430 |
| Small capsule | 462x174 |
| Main capsule | 1232x706 |
| Vertical capsule | 748x896 |
| Library capsule | 600x900 |
| Library hero | 3840x1240 |
| Library logo | 1280x720 PNG, transparent |
| Screenshots | 1920x1080, at least 5 (the `--shot=` flag makes clean ones) |
| Trailer | 1920x1080, 30 s - 2 min, mp4 |
| Client icon | 32x32 .jpg + .ico |
| Achievement icons | 64x64, locked + unlocked |

### Achievements
| API name | Name | How |
|---|---|---|
| first_blood | First Blood | Sink an enemy ship |
| tin_can | Tin Can Sailor | Win a destroyer action |
| convoy_through | The Convoy Got Through | Escort mission won with no merchant lost |
| big_game | Big Game | Sink a battleship or carrier |
| sub_hunter | Sub Hunter | Sink a submarine |
| silent_service | Silent Service | Sink a ship with a submarine |
| ten_kills | Ace of the Slot | Ten ships sunk in one career |
| navy_cross | Navy Cross | Awarded the Navy Cross |
| four_stripes | Four Stripes | Rank of Captain |
| flag_rank | Flag Rank | Rank of Rear Admiral |
| survivor | Survivor | Come home with over half the crew lost |
| rescuer | Shipmates | Rescue survivors |
| night_fighter | Night Fighter | Win a night battle |
| home_by_christmas | Home by Christmas | At sea on 25 December |
| to_tokyo_bay | Tokyo Bay | Reach 2 September 1945 |
| ironman | Ironman | Reach the surrender on Ironman |
