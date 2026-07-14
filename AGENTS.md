# AGENTS.md

## Project

FrontendLegends is a Godot 4.7 2D top-down tile RPG written in GDScript.

- Main project: `project.godot`
- Scenes: `scenes/splash.tscn`, `scenes/character_creation.tscn`, `scenes/game.tscn`
- Runtime code: `scripts/*.gd`
- Data: `assets/Data/*.json`
- Maps: Tiled TMX files under `assets/Map/maps/LoreWorld/`
- Tilesets: Tiled TSX XML files under `assets/Map/tilesets/`
- Design resolution: 640 x 480; tile size: 16 x 16 px

`.tsx` files in this repository are required Tiled XML tileset definitions.

## Run And Test

Open the repository root in Godot 4.7, or run:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --editor
```

Headless verification:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/scene_smoke.gd
```

## Architecture

- `scripts/game.gd`: main scene coordinator, movement, interaction, HUD state, map transitions, and battle presentation
- `scripts/game_state.gd`: profile, save data, survival state, and game clock
- `scripts/data_registry.gd`: JSON registries and map discovery
- `scripts/tiled_map_loader.gd`: runtime TMX/TSX parsing and map queries
- `scripts/tiled_map_renderer.gd`: runtime tile rendering
- `scripts/inventory_system.gd`: inventory, equipment, consumables, and trade
- `scripts/skill_system.gd`: skills, training, sect membership, and learning
- `scripts/quest_system.gd`: quest runtime and generated targets
- `scripts/npc_system.gd`: NPC registry merge, sprites, defeated state, and drops
- `scripts/combat_system.gd`: combat sessions and formulas
- `scripts/battle_resolve.gd`: battle settlement
- `scripts/virtual_controls.gd`: mobile controls

Autoload registrations are defined in `project.godot`.

## Rules

1. Treat the Godot scenes and GDScript runtime as the only implementation source of truth.
2. Preserve TMX/TSX files and their relative paths; maps load them directly at runtime.
3. Keep logic compatible with headless tests. Add focused coverage to `tests/smoke.gd` or `tests/scene_smoke.gd` for behavior changes.
4. Do not commit `.godot/`; it is generated and ignored.
5. Node scripts under `tools/` are standalone data/version utilities, not part of the game runtime.
