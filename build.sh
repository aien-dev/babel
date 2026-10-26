#!/bin/sh
# Build build/babel from src/*.om with the pinned OM-2 compiler.
# usage: OMEGA_MV=<aien-dev/omega-mv clone> ./build.sh
# Pins: omc = omega-mv 0b77e6ea2:seed/out/omc (sha256 2c824805...029f);
#       sha256.om = omega-mv 4d414574:src/source-aware/vendor/sha256.om (AGPL-3.0-or-later).
set -eu
: "${OMEGA_MV:?set OMEGA_MV to an aien-dev/omega-mv clone}"
cd "$(dirname "$0")"
mkdir -p build
git -C "$OMEGA_MV" show 0b77e6ea2:seed/out/omc > build/omc
git -C "$OMEGA_MV" show 4d41457466c42ccb52f405915fd95da469a439e3:src/source-aware/vendor/sha256.om > build/sha256.om
echo "2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f  build/omc" | sha256sum -c -
chmod +x build/omc
{ echo om2; cat build/sha256.om src/*.om; } > build/babel.om
build/omc < build/babel.om > build/babel
chmod +x build/babel
sha256sum build/babel
