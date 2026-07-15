#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
limit=500

if ! find "$root" -type f \( -name '*.gd' -o -name '*.gdshader' \) \
	-not -path "$root/.godot/*" \
	-not -path "$root/android/build/*" \
	-not -path "$root/dist/*" \
	-not -path "$root/web/*" \
	-exec wc -l {} + | awk -v root="$root/" -v limit="$limit" '
		$2 == "total" { next }
		$1 > limit {
			path = $2
			sub("^" root, "", path)
			printf "ERROR: %s has %d lines (hard limit: %d)\n", path, $1, limit
			failed = 1
		}
		END { exit failed }
	'; then
	exit 1
fi

printf 'Source file size gate: PASS (all project source files <= %s lines)\n' "$limit"
