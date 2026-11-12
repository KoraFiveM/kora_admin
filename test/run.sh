#!/usr/bin/env bash
# Runs every kora_admin smoke test with plain Lua -- no FXServer, no database, no
# busted/luarocks dependency -- and exits non-zero if any of them failed.
#
# Each suite runs from the resource root because they dofile('config.lua') and
# the real server/client files under test by their in-resource paths.
set -uo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lua_bin="${LUA:-lua}"
status=0
suites=0

for file in "$dir"/smoke/*.lua; do
    echo "== $(basename "$file" .lua) =="
    suites=$((suites + 1))
    if ! ( cd "$dir/.." && "$lua_bin" "$file" ); then status=1; fi
    echo
done

echo "== discord transport =="
if ! ( cd "$dir/.." && node --test test/discord.test.js ); then status=1; fi

echo "-- ran $suites suite(s) --"
exit "$status"
