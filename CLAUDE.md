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

## Source File Size And Modularity

- Project-authored source files should target 300 physical lines or fewer and must not exceed 500 physical lines.
- Split growing features into cohesive folders and clearly named modules before they cross the hard limit.
- Do not satisfy the limit by compressing formatting, placing multiple statements on one line, adding generated indirection, or moving unrelated code into a generic dumping-ground utility.
- Prefer narrow, stable module interfaces, high cohesion within a feature, and low coupling between features. Avoid shared mutable state where practical.
- Tests are subject to the same 500-line hard limit and should be split by subsystem or behavior.
- Generated/vendor paths `.godot/`, `android/build/`, `dist/`, and `web/` are excluded.
- Run `tools/check_file_size.sh` as the authoritative repository size gate.
