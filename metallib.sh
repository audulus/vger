#!/bin/zsh
set -euo pipefail

# This script builds a metallib suitable for debugging. Unfortunately, SPM doesn't support compiling metal with debug symbols on.
# See https://forums.swift.org/t/cant-profile-metal-shaders-within-a-package/49607 

export MTL_ENABLE_DEBUG_INFO=INCLUDE_SOURCE
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

xcrun --sdk macosx metal -target air64-apple-macos12.1 -ffast-math -gline-tables-only -MO -o vger.metallib Sources/vger/vger.metal
