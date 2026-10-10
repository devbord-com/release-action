#!/bin/sh
# Uploads the function names of a native library to devbord, so addresses in a crash get a name.
#
#   DEVBORD_KEY=db_… ./upload-symbols.sh https://your.domain <project> <file or .dSYM folder> [more files…]
#
# Works for Mach-O (iOS, macOS: pass the .dSYM folder or the file inside it) and ELF (Linux, Android NDK: pass the .so file
# with debug symbols, so before strip). Needs nm, and where available dwarfdump (Apple) or readelf (Linux) to read the
# build ID. Without a build ID the file is matched by its name.
set -eu

[ -n "${DEVBORD_KEY:-}" ] || { echo "Put the API key in DEVBORD_KEY" >&2; exit 1; }
[ $# -ge 3 ] || { echo "Usage: upload-symbols.sh <address> <project> <file or .dSYM> [...]" >&2; exit 1; }
URL=${1%/}; PROJECT=$2; shift 2
# the uploads partly run in a subshell: a file records that one of them failed
FAILED=$(mktemp); rm -f "$FAILED"

demangle() {
  if command -v xcrun >/dev/null 2>&1 && xcrun --find swift-demangle >/dev/null 2>&1; then xcrun swift-demangle | { command -v c++filt >/dev/null 2>&1 && c++filt || cat; }
  elif command -v c++filt >/dev/null 2>&1; then c++filt
  else cat; fi
}

upload() { # file build-id name
  tmp=$(mktemp)
  nm -n --defined-only "$1" 2>/dev/null | demangle > "$tmp" || true
  if [ ! -s "$tmp" ]; then echo "  no symbols in $1" >&2; rm -f "$tmp"; return; fi
  query="type=symbols&name=$3"
  [ -n "$2" ] && query="$query&debug_id=$2"
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$URL/api/v1/boards/$PROJECT/debug-files?$query" \
    -H "Authorization: Bearer $DEVBORD_KEY" -H 'Content-Type: application/octet-stream' --data-binary @"$tmp")
  rm -f "$tmp"
  if [ "$code" = 200 ]; then echo "  $3 ${2:-(by name)}"; else echo "  $3 failed: HTTP $code" >&2; : > "$FAILED"; fi
}

for target in "$@"; do
  if [ -d "$target" ]; then files=$(find "$target/Contents/Resources/DWARF" -type f 2>/dev/null || true); else files=$target; fi
  [ -n "$files" ] || { echo "Nothing found in $target" >&2; continue; }
  echo "$target"
  for f in $files; do
    name=$(basename "$f")
    if command -v dwarfdump >/dev/null 2>&1 && dwarfdump --uuid "$f" >/dev/null 2>&1; then
      # a file for several architectures has its own build ID per architecture
      dwarfdump --uuid "$f" | while read -r _ uuid arch _; do
        arch=$(echo "$arch" | tr -d '()')
        tmp=$(mktemp)
        nm -n --defined-only -arch "$arch" "$f" 2>/dev/null | demangle > "$tmp" || true
        if [ -s "$tmp" ]; then
          code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT "$URL/api/v1/boards/$PROJECT/debug-files?type=symbols&name=$name&debug_id=$uuid" \
            -H "Authorization: Bearer $DEVBORD_KEY" -H 'Content-Type: application/octet-stream' --data-binary @"$tmp")
          if [ "$code" = 200 ]; then echo "  $name $arch $uuid"; else echo "  $name $arch failed: HTTP $code" >&2; : > "$FAILED"; fi
        fi
        rm -f "$tmp"
      done
    else
      id=""
      if command -v readelf >/dev/null 2>&1; then id=$(readelf -n "$f" 2>/dev/null | sed -n 's/.*Build ID: *\([0-9a-f]*\).*/\1/p' | head -1); fi
      upload "$f" "$id" "$name"
    fi
  done
done
if [ -e "$FAILED" ]; then rm -f "$FAILED"; exit 1; fi
