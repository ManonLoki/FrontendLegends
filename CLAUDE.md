# CLAUDE.md

See `AGENTS.md` for the current Godot project architecture, commands, and repository rules.

## Mandatory Frozen-Scene Rule

Do not modify any of these protected files without a separate, explicit second confirmation from the user:

- `scenes/splash.tscn`
- `scripts/splash.gd`
- `scenes/character_creation.tscn`
- `scripts/character_creation.gd`
- `scripts/game_battle_ui.gd`
- `scripts/ui_progress_meter.gd`
- HUD panel/layout code in `scripts/game.gd`: the `@onready` HUD node references and any function whose name starts with `_layout_`, plus `_build_detail_huds` and `_use_detail_hud`. This does not cover the world/player rendering `_draw()` function or any other non-HUD logic in `scripts/game.gd` (movement, combat resolution, save/load, survival ticking, animation, etc.).

The user's initial request to modify a protected file is not confirmation. Before editing, stop, identify the exact protected files and intended changes, and ask the user to confirm unlocking them for that one change. Only an affirmative response in a subsequent user message authorizes the edit. Confirmation is one-time and applies only to the files and changes listed; every later protected-file change requires a new second confirmation. Read-only inspection and testing are allowed.
