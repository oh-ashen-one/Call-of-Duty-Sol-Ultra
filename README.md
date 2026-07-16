# Call of Duty Sol Ultra

> **Repository note:** “Call of Duty Sol Ultra” is the private repository label requested by the owner. The game itself is **Project Breakwater**, an original work that is not affiliated with, endorsed by, or built from the assets, code, branding, characters, maps, audio, or UI of Call of Duty or Activision.

Project Breakwater is a complete offline Godot 4.7 arena FPS: title screen, local “Practice Matchmaking” presentation, eight-combatant free-for-all with seven autonomous bots, first-to-30 victory or defeat, results, rematch, loadouts, cosmetics, persistent settings, and an original procedural coastal map called Breakwater Station.

![Project Breakwater title screen](screenshots/01_title.png)

## Quick start

Requirements: macOS, Godot 4.7.x, and a keyboard/mouse or standard gamepad. Install Godot only if it is missing:

```bash
brew install --cask godot
godot --path .
```

The normal journey is **Title → Home → Play → Practice Matchmaking → Loading → Free-for-All → Results**. Practice Matchmaking is explicitly an offline simulation; this project has no networking or remote matchmaking service.

Run the complete non-windowed release verifier with:

```bash
GODOT_BIN=/opt/homebrew/bin/godot ./scripts/verify_breakwater.sh
```

## Core controls

| Keyboard / mouse | Action | Controller |
| --- | --- | --- |
| `W A S D` / mouse | Move / look | Left / right stick |
| `Shift`, `Space`, `Ctrl` | Sprint, jump, crouch/slide | L3, A, B |
| Left / right mouse | Fire / aim | Right / left trigger |
| `R`, `E`, `V`, `1` | Reload, interact, melee, swap | X, X, R3, Y |
| `G`, `Q` | Frag / tactical grenade | RB / LB |
| `Tab`, `Esc` | Scoreboard / pause | Back / Start |

Keyboard, mouse, and controller gameplay actions can be rebound in Settings.

## High-level build rationale and process

This is the project-level design record—not private scratchpad reasoning. The build strategy was to capture the responsiveness and match readability of a modern military-arcade shooter while keeping every concrete expression original:

1. **Protect the originality boundary.** The map, weapon names, UI language, operators, camos, procedural models, effects, music, and sounds were created for Breakwater rather than copied or traced from a commercial game.
2. **Make combat data-driven.** Six weapon definitions own damage, falloff, cadence, spread, recoil, magazine, reload, reserve, and handling values. Player and bot controllers consume the same combat contracts.
3. **Finish one complete journey first.** Title-to-results flow, exact score limits, death/respawn, and autonomous scoring were established before expanding cosmetics and presentation.
4. **Treat bots as real free-for-all participants.** Bots select any opponent, traverse all three routes, use range-appropriate weapons and grenades, collect useful pickups, avoid unsafe spawns, and continue fighting when the player is idle.
5. **Use original procedural production assets.** Breakwater Station, weapons, operators, VFX, ambience, music, and gameplay cues are generated from GDScript geometry, materials, and synthesis. The generated menu image is documented in `ATTRIBUTIONS.md`.
6. **Convert regressions into executable contracts.** Tests now cover lifecycle edges such as winning shots inside physics callbacks, grenade final kills, reload interruption, GUI-owned controller input, rematch HUD cleanup, real bot-vs-bot telemetry, input rebinding, settings application, export contents, signing, and archived-app startup.

The strongest engineering lesson was that presentation and correctness meet at lifecycle boundaries. A match can finish inside a weapon or grenade callback; a persistent HUD can carry stale state into a rematch; and a broad bot score is not sufficient proof that bots fought one another. Those cases now have explicit guards and regression tests.

## Time invested

The tracked Codex build goal recorded **11,465 seconds (3 hours, 11 minutes, 5 seconds)** of active building and verification through the main release-hardening milestone. The four primary playable-to-hardened milestones spanned **2 hours, 31 minutes, 35 seconds** by commit timestamps. The final documentation, additional audit fixes, and private-GitHub publication happened afterward and are not included in the 11,465-second measurement.

These are tooling/goal and commit-window measurements, not an estimate of how long a human studio production would take.

## Verification snapshot

Verified headlessly on an Apple M5 Mac with Godot 4.7.1:

- Godot import and GDScript parsing: pass
- Gameplay suite: **215 assertions**
- Integration suite: **278 assertions**
- Combined automated coverage: **493 assertions**
- Unattended 300-second simulation: **265 bot eliminations**, including **246 genuine bot-vs-bot** and 19 bot-vs-player eliminations, 14 bot grenades, 19 pickups, and one completed first-to-30 round
- Scoped exported-PCK allowlist: **81 Breakwater-only files**
- Universal macOS export: arm64 and x86_64
- Ad-hoc signing, strict verification, ZIP extraction, and extracted signature/architecture checks: pass
- Archived executable 60-second simulation: 52 bot eliminations, including 51 bot-vs-bot eliminations, 3 grenades, and 5 pickups
- Separate accelerated five-minute logic simulation: **0.94 seconds wall time** and about **312 MB maximum RSS**

The verifier creates `build/Project Breakwater-macOS.zip`, but build output is deliberately ignored by Git.

## Repository map

| Path | Purpose |
| --- | --- |
| `project.godot`, `scenes/main.tscn` | Godot 4.7 project and boot scene |
| `src/gameplay/` | Weapons, player, bots, damage, scoring, pickups, grenades |
| `src/game/` | Match composition, HUD telemetry, results, viewmodel |
| `src/world/` | Procedural Breakwater Station and bot route graph |
| `src/ui/` | Menus, settings, HUD, matchmaking presentation, results |
| `src/audio/`, `src/vfx/` | Original synthesized audio and procedural effects |
| `tests/` | Gameplay and end-to-end integration suites |
| `scripts/verify_breakwater.sh` | Full headless test/export/sign/archive verification |

## Build notes and honest limitations

- The project favors cohesive stylized procedural geometry over external high-poly character and weapon packs.
- Automated tests dispatch the keyboard/mouse combat path and validate analog-stick, trigger, face-button, D-pad, rebinding, persistence, and dead-zone behavior. A final physical-controller right-stick comfort and vibration pass is still required.
- At the owner’s request, the latest build was not opened during final hardening. Headless logic throughput is not proof of rendered 1920×1080 at 60 FPS, and the checked-in rendered screenshots predate the latest polish.
- The verified ZIP is ad-hoc signed for local testing; it is not Developer ID-signed or notarized for public distribution.
- Practice Matchmaking is deliberately local and offline.

See [BREAKWATER.md](BREAKWATER.md) for full controls, architecture, settings, tests, export instructions, screenshot provenance, and limitations. See [ATTRIBUTIONS.md](ATTRIBUTIONS.md) for asset provenance and redistribution notes.
