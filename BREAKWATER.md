# Project Breakwater

Project Breakwater is an original, offline 3D arena FPS built with Godot 4.7 and GDScript. A complete session runs from the title screen through an explicitly simulated **Practice Matchmaking** presentation into an eight-combatant free-for-all on Breakwater Station. The player and seven autonomous bots race to 30 eliminations, then continue to a victory/defeat results screen with rematch and menu options.

The game is inspired by the responsiveness and readability of modern military-arcade shooters, but all names, map design, UI, procedural models, effects, audio, and branding are original. It does not contain Call of Duty assets or reproduce an existing map.

## Requirements

- macOS on Apple Silicon or Intel
- Godot 4.7.x (verified with 4.7.1)
- 1920×1080 display recommended
- Keyboard and mouse, or a standard gamepad

Install Godot with Homebrew if needed:

```bash
brew install --cask godot
```

Godot's macOS export templates are only needed to produce the `.app`; running from the project and all source-level tests work without them. Install templates from **Editor → Manage Export Templates** or place the official 4.7.1 template archive in Godot's export-template directory.

## Run

From this repository:

```bash
godot --path .
```

To launch directly into a local practice match:

```bash
godot --path . -- --autoplay
```

The normal journey is **Title → Home → Play → Practice Matchmaking → Loading → Free-for-All → Results**. Practice Matchmaking is presentation only: all eight combatants run locally and no networking, accounts, telemetry service, or remote lobby is used.

## Controls

| Keyboard / mouse | Action | Controller |
| --- | --- | --- |
| `W A S D` | Move | Left stick |
| Mouse | Look | Right stick |
| `Shift` | Sprint | Left-stick press |
| `Space` | Jump | South / A |
| `Ctrl` | Crouch; crouch while sprinting to slide | East / B |
| Left mouse | Hip fire / fire | Right trigger |
| Right mouse | Aim down sights | Left trigger |
| `R` | Reload | West / X |
| `E` | Pick up weapon | West / X |
| `V` | Melee | Right-stick press |
| `G` | Throw frag grenade | Right shoulder |
| `Q` | Throw selected flash or concussion grenade | Left shoulder |
| `1` | Swap weapon | North / Y |
| `Tab` | Hold scoreboard | Back / Select |
| `Esc` | Pause | Start |

Keyboard/mouse and gamepad actions can both be reassigned in Settings. Rebinding one device class preserves the other, removes conflicting gameplay bindings, and persists modifier-assisted key or mouse chords. Reload and Interact intentionally share the default controller X button; a visible, in-range, line-of-sight-valid pickup takes contextual priority.

## Included gameplay

- Responsive first-person walking, sprinting, jumping, physical capsule crouching with a ceiling-clearance stand guard, sliding, sprint-to-fire transition, ADS, hip fire, recoil, interruptible reload, melee, weapon swapping, and view/line-of-sight-validated pickups.
- Six data-driven original weapons: VX-4 Carbine, Kestrel SMG, pump-action Breaker-12 shotgun, Helix DMR, Atlas LMG, and Sparrow pistol. Each has distinct damage, range, falloff, fire rate, spread, recoil, magazine, reload, reserve ammo, and handling values. The Breaker-12 has a timed pump cycle and interruptible shell-by-shell reload rather than behaving like a magazine-fed semi-automatic.
- Headshots, regenerating health, damage falloff, spawn protection, death, delayed respawn, line-of-sight/cover-aware safe-spawn scoring, hit and kill markers, muzzle flashes, impacts, authoritative per-pellet traces, recoil/bob/reload/pump animation, and original synthesized weapon, movement, reload/pump, impact, melee, grenade, weapon-swap, menu/UI, musical-score, and victory/defeat-stinger audio.
- Frag, Lumen flash, and Pulse concussion grenades with radial falloff, line-of-sight attenuation, visual feedback, and status effects shared by human and AI combatants.
- Four named loadout presets plus a custom field kit, with five primary platforms, configurable secondary weapons, frag lethal equipment, and either flash or concussion tactical equipment. Three original operator skins and three weapon camos are reflected by runtime materials.
- Seven bots that independently patrol, acquire any living opponent, fight one another and the player, vary weapons and behavior, display their equipped weapon and tactical status, throw equipment, collect useful pickups, avoid threatened respawns, die, respawn, and continue scoring while the player is idle.
- First-to-30 match rules: the first combatant to reach exactly 30 wins and additional scoring stops immediately.
- Full HUD with health and damage feedback, ammo, equipment, reticle, compass, tactical minimap, kill feed, leader/score-to-30 display, scoreboard, status effects, pickup prompt, respawn timer, and pause menu.

## Breakwater Station

Breakwater Station is a procedural, original coastal research base built entirely in GDScript. Its three linked routes—the ocean promenade, research interior, and raised service/gantry flank—are joined by cross-lanes, vertical overlooks, physical ramps, catwalk transitions, cover, and landmark sightlines. The scene includes a harbor and ocean horizon, seawalls, station modules, vegetation, mist, reflective materials, strong directional lighting, eight distributed spawn zones, patrol nodes, and 12 field pickup sites: six weapons plus ammunition, frag, flash, and concussion resupplies.

The map is assembled from reusable Godot primitives at startup, so no external environment pack or copied level geometry is required.

## Menus and settings

The front end includes title/home, play and offline matchmaking, configurable loadout, skins and camos, settings, controls, credits, loading, pause, scoreboard, and post-match screens. Loadout and appearance edits are staged: Equip/Apply commits them, while Back discards them. An original synthesized score, ambience, button cues, combat effects, movement cues, and result stingers cover the complete journey. Settings are applied at runtime and saved between launches to `user://breakwater_settings.cfg`.

Available settings:

- Master, music, SFX, and UI volume
- Mouse, ADS, and controller sensitivity
- Controller dead zone, vibration toggle, invert-Y, and input rebinding
- FOV, exclusive fullscreen/borderless/windowed mode, window resolution, 3D render scale, graphics quality, and VSync
- Camera-shake strength, hit-marker visibility, crosshair visibility, and crosshair color

Graphics quality presets apply more than anti-aliasing: they also scale dynamic sun shadows, atmospheric fog, the reflection probe, optional vegetation detail, transient VFX budgets, and dynamic effect lights. The low and high preset states are exercised by the integration suite.

## Architecture

| Path | Responsibility |
| --- | --- |
| `project.godot` | Godot 4.7 project, autoload, 1080p viewport, and rendering defaults |
| `scenes/main.tscn` | Minimal boot scene |
| `src/main.gd` | Application state flow, menu/match orchestration, rematch, CLI QA modes |
| `src/game/game_world.gd` | Match composition, player + seven bots, HUD telemetry, feedback, results, viewmodel |
| `src/game/content_catalog.gd` | Loadouts, operator skins, weapon camos, and bot identities |
| `src/gameplay/` | Weapons, combatants, player movement/input, bots, health, pickups, grenades, scoring |
| `src/world/world_builder.gd` | Procedural Breakwater Station environment, patrol waypoints, and authored route graph |
| `src/ui/` | Menus, matchmaking presentation, settings, HUD, minimap, scoreboard, pause, results |
| `src/audio/audio_director.gd` | Original synthesized menu, weapon, impact, melee, equipment, and UI audio |
| `src/vfx/vfx_director.gd` | Runtime muzzle, tracer, impact, explosion, and respawn effects |
| `tests/gameplay/run_tests.gd` | Focused weapon, reload interruption, health, scoring, grenade, supply/pickup, authoritative trace, physical stance, movement/input, recoil, safe spawn, melee, and bot-combat contracts |
| `tests/integration/run_tests.gd` | Exact score-30 wins, isolated persistence and modifier-aware rebinding, synthesized controller input, staged menus, idempotent matchmaking, graphics/VFX presets, all physical ramp routes, final-kill teardown, audio lifecycle, and complete app journey |
| `scripts/verify_breakwater.sh` | Headless import/tests, five-minute multi-round bot simulation, scoped PCK resource-tree allowlist, universal export, ad-hoc signing, ZIP extraction/signature checks, and archived-app gameplay test |
| `scripts/verify_export_pack.gd` | Rejects exported PCK entries outside the explicit Breakwater resource tree |

The combat layer is data-driven: `WeaponDefinition`, `GrenadeDefinition`, and their runtime state are independent from player and bot control. Both player and bots derive from `CombatantController`, so damage, equipment, pickups, death, and respawn follow the same contracts. Bots traverse an authored AStar route graph spanning the three main lanes and vertical connectors, with short-range collision steering and a `NavigationAgent3D` hook for compatible navigation maps.

## Headless verification

Run the complete non-interactive verifier; it does not open a game window:

```bash
./scripts/verify_breakwater.sh
```

Core source and test commands (the verifier script additionally performs manifest, signing, architecture, archive, and extracted-app checks):

```bash
godot --headless --path . --editor --quit
godot --headless --fixed-fps 60 --path . --script tests/gameplay/run_tests.gd
godot --headless --fixed-fps 60 --path . --script tests/integration/run_tests.gd
godot --headless --fixed-fps 60 --path . -- --bot-benchmark=300 --time-scale=12
godot --headless --path . --export-debug "macOS" "build/Project Breakwater.app"
```

Verified on an Apple M5 Mac with Godot 4.7.1:

- Godot import and GDScript parse: pass
- Gameplay suite: **215 assertions passed**
- Integration suite: **278 assertions passed**
- Combined automated coverage: **493 assertions passed**
- Latest unattended five-minute simulation: **265 bot eliminations, including 246 bot-versus-bot and 19 bot-versus-player eliminations, 14 grenade throws, and 19 field pickups collected** while the player remained idle. The benchmark completed one first-to-30 round, automatically started a fresh round, and aggregated activity through 300 simulated seconds.
- Separately recorded headless five-minute logic benchmark: **0.94 seconds wall time**, **312,279,040 bytes maximum resident memory** (about 312 MB, `/usr/bin/time -l`); this measures accelerated simulation throughput, not rendered FPS
- Exact player-at-30 victory, bot-at-30 defeat, results, rematch score reset, and return-to-menu journey: pass
- Exported PCK scoped resource-tree allowlist: pass with **81 Breakwater-only files**
- Universal macOS debug export: pass (arm64 + x86_64)
- Ad-hoc signing, strict signature verification, ZIP extraction, extracted signature/architecture verification, and executable launch from the archived deliverable: pass
- Exported application 60-second gameplay simulation: pass with **52 bot eliminations, including 51 bot-versus-bot eliminations, 3 grenade throws, and 5 pickups**

The unattended benchmark is simulation validation, not a GPU frame-rate measurement. Godot headless mode does not render frames, so it cannot validate final image quality, capture the post-match screen, or establish interactive 1080p performance. An earlier interactive build was captured successfully on this Mac, but the latest gameplay, lighting, viewmodel, audio, input, and menu polish has intentionally not been reopened because the current operator requested that no game window be opened on this laptop.

## Screenshots

- [Title screen](screenshots/01_title.png)
- [Breakwater Station combat](screenshots/03_breakwater_station.png)

The title capture is 1920×1080 and the combat capture is 3024×1701. Both were produced at the earlier `1ce808c` milestone, before the latest gameplay and presentation polish. They remain useful evidence of the rendered front end, HUD, map, and active bot kill feed. The attempted ready-deck capture duplicated the title image and was intentionally omitted; refreshed menu, combat, and results captures could not be produced after the operator requested that no game window be opened. These are not intended as final marketing captures.

## Export

With the official Godot 4.7.1 macOS export templates installed:

```bash
godot --headless --path . --export-debug "macOS" "build/Project Breakwater.app"
```

The preset produces the raw universal app at `build/Project Breakwater.app`. Its executable retains the official Godot template vendor signature, but the assembled bundle is not strictly validly signed for distribution. The complete verifier copies that bundle to a temporary non-File-Provider location, clears workspace metadata, applies an ad-hoc bundle signature, strictly verifies it, creates `build/Project Breakwater-macOS.zip`, extracts the ZIP, verifies the extracted signature and both architectures, then runs the archived executable headlessly. The current ZIP is approximately 63 MB.

Ad-hoc signing is suitable for this local verification workflow but is not an Apple Developer ID signature or notarization. Public distribution still requires the appropriate Apple identity and notarization process.

## Known limitations

- Project Breakwater is deliberately offline-only. Practice Matchmaking is clearly labeled as a local simulation.
- No physical controller was connected during the final automated run. Controller mappings, rebinding, and persistence are covered headlessly; the suites also inject D-pad menu input, exercise analog movement below and above the configured dead zone, and dispatch the keyboard/mouse combat path. This is not a substitute for a physical-device right-stick, sensitivity, vibration, and comfort pass.
- The environment and equipment use stylized procedural geometry rather than externally authored high-poly character and weapon assets.
- The headless benchmark validates game logic throughput and autonomous combat; it does not establish a measured 60 FPS GPU render trace or visually validate the latest presentation polish. A final on-device 1080p performance and screenshot pass remains manual QA when opening the game is permitted.
- The raw preset bundle is not strictly validly signed for distribution. The verified ZIP contains an ad-hoc-signed app, not an app signed with this project's Apple Developer ID or notarized for public distribution.

All external/generated asset provenance is recorded in [ATTRIBUTIONS.md](ATTRIBUTIONS.md).
