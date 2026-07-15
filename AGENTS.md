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
3. Keep runtime behavior compatible with Godot 4.7 headless execution. Tests must never share the production `user://` save path.
4. Do not commit `.godot/`; it is generated and ignored.
5. Node scripts under `tools/` are standalone data/version utilities, not part of the game runtime.
6. **Frozen Splash and CharacterCreation code:** Do not modify `scenes/splash.tscn`, `scripts/splash.gd`, `scenes/character_creation.tscn`, or `scripts/character_creation.gd` without a separate, explicit second confirmation from the user. The user's initial request to change any of these files does **not** count as confirmation. Before editing, stop and list the exact protected files and intended changes, then ask the user to confirm unlocking them for that one change. Only an affirmative reply in a subsequent user message authorizes the edit. That authorization is one-time and limited to the files and changes listed; all later changes require confirmation again. Reading, inspecting, and testing these files without modifying them remains allowed.
