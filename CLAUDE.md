# CLAUDE.md

See `AGENTS.md` for the current Godot project architecture, commands, and repository rules.

## Mandatory Frozen-Scene Rule

Do not modify any of these protected files without a separate, explicit second confirmation from the user:

- `scenes/splash.tscn`
- `scripts/splash.gd`
- `scenes/character_creation.tscn`
- `scripts/character_creation.gd`

The user's initial request to modify a protected file is not confirmation. Before editing, stop, identify the exact protected files and intended changes, and ask the user to confirm unlocking them for that one change. Only an affirmative response in a subsequent user message authorizes the edit. Confirmation is one-time and applies only to the files and changes listed; every later protected-file change requires a new second confirmation. Read-only inspection and testing are allowed.
