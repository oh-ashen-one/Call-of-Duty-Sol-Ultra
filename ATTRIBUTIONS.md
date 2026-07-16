# Project Breakwater asset record

Project Breakwater does not include paid assets or material copied from an existing game.

| Asset | Source | Use and terms |
| --- | --- | --- |
| `assets/ui/breakwater_station_menu.png` | Generated for this repository with OpenAI image generation on 2026-07-15 | Original menu/environment concept produced without reference images or third-party brands. Prompt summary: a cinematic, sunlit near-future coastal research station overlooking the ocean, rescue-coral details, sea-glass lighting, atmospheric mist, no text, logos, people, or recognizable commercial-game design. Usage rights: created as a Project Breakwater output and authorized for redistribution with this repository and its builds; no third-party asset license applies. |
| `assets/icon.svg` | Authored directly for this repository | Original sonar/breakwater mark. |
| Procedural meshes, materials, UI, and VFX | Generated at runtime by the GDScript source in this repository | Original code-native content; no external art pack is redistributed. |
| Original menu/match score, coastal ambience, UI cues, weapon reports, footsteps/jump/slide/landing, reload/pump cues, impacts, melee, grenade throws and explosions, weapon swaps, result stingers, and hit feedback | Synthesized at runtime by `src/audio/audio_director.gd` | Original code-generated audio; no samples, prerecorded music, or third-party sound libraries are included. |

The macOS system fonts requested by the UI (`Avenir Next`, `Helvetica Neue`, `SF Mono`, and fallbacks) are referenced through Godot's `SystemFont`; no font files are redistributed.
