# Hands Off

Multiplayer manhunt in Godot 4.7. Four modes, LAN or internet via a UDP tunnel.

## Modes

| Mode | Rules | Win |
|------|-------|-----|
| **Manhunt (Free-for-all)** | Everyone can tag everyone. Tagged = out. | Last one standing, or survivors when time runs out |
| **Hide & Seek** | Seekers tag hiders. Tagged hiders are out. 15 s head start. | Seekers: all hiders found. Hiders: clock runs out |
| **Tag (Infection)** | Tagged hiders become seekers. | Seekers: everyone converted. Hiders: anyone left at the end |
| **Cops & Robbers** | Cops jail robbers (teleported to the jail cell). Robbers tag jailed teammates to free them (3 s immunity). | Cops: every robber jailed. Robbers: clock runs out |

## Controls

WASD move, Shift sprint, Space jump, Left click or E to tag (Hany reaches out a hand), hold Alt or middle mouse to orbit
the camera around yourself, Esc frees the mouse, click locks it back, Esc again opens the pause menu.
Bunny hop: jump the moment you land while running to build speed; a well-timed tap beats holding Space. Holding Space
keeps you hopping. C or Ctrl crouches (hold), X rolls, F sticks you flat to a wall (hold), B holds your breath (hold,
8 s max, then a loud gasp), V is push-to-talk proximity voice. Stairs and small ledges are walked up, chest-high
blocks are vaulted when you jump into them, and jumping while touching a wall in the air kicks you off it.
Footsteps change with the block colour under you (grass, wood, metal, dirt, concrete) and everyone hears your
breathing get heavier when you sprint. Players who are out become free-fly spectators.

Handers start locked in the jail for the head start (host picks 1 to 5 minutes in the lobby). In Manhunt nobody can
tag during the opening grace period but everyone can move.

**Customize Hany** on the main menu sets your name and skin (saved in `user://profile.cfg`); hats and costumes plug in
there later. In the lobby you can volunteer as Hander: volunteers are picked first, earliest first, then random fill.

## Playing

1. Open the project in Godot 4.7, press Play (or run two instances to test locally).
2. **Host**: enter a name, pick the UDP port (default 7777), click Host. Choose the mode in the lobby and press Start.
3. **Join on LAN**: enter the host's LAN IP shown in the host's lobby, e.g. `192.168.1.20:7777`.
4. **Join over the internet (Playit.gg)**: the host runs the Playit agent, creates a **UDP** tunnel pointing at local port 7777, and shares the address Playit gives them (`something.playit.gg:12345`). Joiners paste that into the Join field.

Players who connect mid-round join as free-flying spectators and play from the next round. Round wins are
counted per player name, shown in the lobby and on the end screen, and saved by the host in `user://handsoff_wins.json`.

## Look and assets

Everything renders through one cel shader ([assets/shaders/toon.gdshader](assets/shaders/toon.gdshader), stepped lighting, rim, optional
world-space triplanar texturing blended with a flat colour) plus an inverted-hull outline pass. `scripts/toon.gd` is the
single place that builds materials; `Toon.convert_scene()` re-skins any imported GLB.

```
assets/characters/<skin>.glb   one file per colour; the lobby picker lists this folder automatically
assets/animations/             Quaternius Universal Animation Library (UAL1/UAL2) + rigged Mannequin_F placeholder
assets/shaders/                toon + outline (ours), Binbun stylized/water/transition/cloud-sky (reference, not wired yet)
assets/textures/<Category>/    curated SBS tiny textures (used via triplanar, so box size doesn't matter)
assets/skyboxes/               Kenney equirect skyboxes (day is the default)
assets/ui/                     Kenney UI pack 9-slices + Kenney Future fonts -> generated theme.tres
assets/icons/                  crosshairs, key prompts (HUD hint bar), game icons, cursors
assets/audio/ui, audio/sfx     Kenney sounds, played by the Sfx autoload (buttons hook up automatically)
assets/emotes/                 Kenney emotes, ready for an emote wheel later
assets/BinbunGrass, BinbunVFX_Vol2   grass shader (unused yet) and the fire VFX used for the jail torches
assets/licenses/               licence text for every pack
```

Regenerate the UI theme after editing `tools/build_theme.gd`:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tools/build_theme.gd
```

### Rigging (automated)
```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --python tools/rig_character.py -- assets/characters/unrigged/banana.glb assets/characters/banana.glb
```
The script imports the Quaternius armature, shrinks the character onto it, weights the body by nearest bone
(bone-heat fails on these dense subdivided meshes), pins eyes/nose/mouth to the Head bone and exports a GLB.
Unrigged exports live in `assets/characters/unrigged/`; rerun the script after re-exporting a skin from Blender.
Because the UAL clips bake a position track on every bone, Godot keeps only root/pelvis positions
(`player_model.gd`), so the character's own proportions survive. Arm length vs the rig is the one thing to
tune in Blender if hands hang too low.

### Character pipeline
- Export each colour as `assets/characters/<name>.glb`. The loader scales it to 1.8 m, puts the feet at y=0, hides any
  mesh named `Mannequin*` (the size reference left in the export), converts materials to toon and tints the outline with the team colour.
- When the model is rigged to the UAL armature (same bone names, armature named `Armature`), the loader finds the
  `Skeleton3D`, attaches the UAL1 animation library and the player plays Idle / Walk / Jog_Fwd / Sprint / Jump and
  Punch_Jab on tag. Until then the model stands still; the `mannequin` skin shows the animations working.
- Godot strips `_Loop` from clip names on import (`Idle_Loop` becomes `Idle`).

## Map editor and .hom files

Main menu, **Map editor**: fly with WASD and Q/E, hold the right mouse button to look, left click places the current
shape and colour (palette presets or a custom column/row), X removes, R rotates, `[` `]` cycle shapes. Zone tools place
the jail, the Hander spawn, Runner spawns and torches. **Save .hom** writes `user://maps/<name>.hom` (JSON, see
`scripts/map_data.gd`); share the file and anyone can drop it in their maps folder. The host picks the map in the lobby
and the file is sent to every client at round start, so only the host needs it. The built-in map is
`assets/maps/blockyard.hom`, regenerated with `tools/export_default_map.gd`.

## Maps from Blender

Model at 1 unit = 1 m. `assets/maps/_reference.glb` has Hany at game height (1.8 m), a 2 m block and a 1 m cube.
Export the map as GLB (+Y up, apply transforms) into `assets/maps/`; it shows up in the lobby map list. Every
mesh gets collision. Add empties named `JailCenter`, `HanderSpawn`, `RunnerSpawn1..n`, `Torch1..n`. Material or
object names containing grass, wood, metal, dirt or sand set the footstep sound. Files starting with `_` are ignored.

Movement numbers for layout: jump reaches about 1.1 m, climb grabs ledges between 0.85 and 1.35 m, stairs up to
0.55 m per step are walked, cells are 2 m, Hany needs a 1 m gap to pass.

## Building the map out of blocks

The arena loads [scenes/maps/main.tscn](scenes/maps/main.tscn) (a starter layout) and falls back to the code greybox if that
file is missing. Blocks are `StaticBody3D` nodes with [scripts/block.gd](scripts/block.gd): pick **Shape** (Cube, Slab,
Platform, Wall, Ramp, Stairs, Corner, Pillar, Column), pick **Block** (a named palette strip, or `custom` with a
column/row), and stretch box shapes with **cells**. Every block is a 2 m cell centred on the node, so set translate snap
to 2. Markers under `Map/Markers` drive gameplay: `JailCenter`, `SeekerSpawn`, `HiderSpawn*`, `Torch*`.

All blocks share one palette texture (`assets/blocks/palette.png`, 36 columns x 6 rows of vertical gradient strips),
exactly like the hand-exported block GLBs but without the 540 KB texture embedded in each file. The palette index
page lists every strip with its colours and the preset names. Add presets in `Blocks.TYPES` and the matching
`@export_enum` in `block.gd`.

Catalog render (all shapes and presets):
```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --write-movie /tmp/cat/f.png --fixed-fps 10 --resolution 1280x720 res://tests/catalog.tscn
```

## Project layout

```
scripts/net.gd              ENet host/join, lobby roster (autoload "Net")
scripts/game.gd             server-authoritative state, phases, timer, tag resolution (autoload "Game")
scripts/modes/game_mode.gd  base rules class
scripts/modes/mode_*.gd     one class per mode: team assignment, can_tag, on_tag, check_winner
scripts/player.gd + scenes/player.tscn   third-person controller, synced via MultiplayerSynchronizer
scripts/arena.gd + scenes/arena.tscn     code-built greybox arena (floor, walls, cover, jail, spawns)
scripts/player_model.gd     loads a skin GLB, fits it, toon-converts it, drives UAL animations
scripts/skins.gd            skin list / paths
scripts/toon.gd             material factory for the cel look
scripts/sfx.gd              sound autoload (UI + gameplay events via Game.fx)
scripts/blocks.gd           procedural block shapes + palette-strip materials
scripts/block.gd            editor-placeable Block node (@tool)
scripts/hud.gd              in-game overlay
scripts/lobby.gd, scripts/main_menu.gd   menus
tests/                      headless tests (see below)
```

Swapping in real assets:
- **Character model**: add it under `Mesh` in `scenes/player.tscn` (keep the capsule collider), and point `player.gd`'s material override at the new mesh or remove the colour tinting.
- **Map**: replace the geometry in `arena.gd::_build_geometry()` with your modelled scene, keeping `spawn_players`, `get_player_node`, `remove_player`, `jail_position` and the `Players` child node.

Networking is isolated in `net.gd` so EOS can replace ENet later without touching game logic.

## Tests

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/smoke.tscn
```
Plays every mode through with fake peers in one process.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/net_test.tscn -- host & \
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/net_test.tscn -- client
```
Two real processes talking over UDP on localhost: lobby, mode sync, spawn, position replication, tag, round end.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/model_test.tscn
```
Checks skin loading, scaling, toon conversion and that UAL clips actually move the mannequin's bones.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --write-movie /tmp/frames/f.png --fixed-fps 10 --resolution 1280x720 res://tests/visual.tscn
```
Renders a few seconds of a round with every skin lined up, so you can eyeball the look without playing.

`zip assets/` holds raw downloads and is ignored by Godot (`.gdignore`).

## Releases

`export_presets.cfg` has six presets: macOS universal / Apple Silicon / Intel and Windows x86_64 / ARM64 / x86_32.
The single-architecture macOS presets need thinned templates: run `tools/make_mac_templates.sh` and set the
produced zips as the preset's custom release template. Then:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "macOS Universal"
```
Outputs land in `builds/`. Windows exe icons: `python3 tools/win_icon.py builds/win-x86_64/HandsOff.exe assets/icon/icon1024.png assets/icon/icon256.png` (patches the exe in place, no rcedit). macOS builds are ad-hoc signed only (right-click, Open on first launch).
