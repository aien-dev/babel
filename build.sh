#!/bin/sh
# Build build/babel from src/*.om with the pinned OM-2 compiler.
# usage: OMEGA_MV=<aien-dev/omega-mv clone> ./build.sh
# Pins (aien-dev/omega-mv 0b77e6ea2, both Apache-2.0):
#   omc        = seed/out/omc            sha256 2c824805...029f
#   sha256 unit = om/sha256/sha256-om2.om sha256 dbf002dd...94bb (FIPS 180-4 SHA-256 in OM-2)
set -eu
: "${OMEGA_MV:?set OMEGA_MV to an aien-dev/omega-mv clone}"
cd "$(dirname "$0")"
mkdir -p build
git -C "$OMEGA_MV" show 0b77e6ea2:seed/out/omc > build/omc
git -C "$OMEGA_MV" show 0b77e6ea2:om/sha256/sha256-om2.om > build/sha256-om2.om
sha256sum -c - <<EOF
2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f  build/omc
dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb  build/sha256-om2.om
EOF
chmod +x build/omc
# sha256-om2.om carries the `om2` header line, so it goes first. Its four `export fn` entries are
# library-mode markers, refused next to `fn main` (error 9); babel calls them as ordinary functions,
# so the marker is dropped and nothing else in the unit changes.
{ sed 's/^export fn /fn /' build/sha256-om2.om; cat src/*.om; } > build/babel.om
build/omc < build/babel.om > build/babel
chmod +x build/babel
sha256sum build/babel
