#!/bin/zsh
# Static validation only: never launches an app or helper.
set -euo pipefail

app_bundle=${1:?Usage: verify-macos-architectures.sh /path/to/Otto.app [architecture ...]}
shift
architectures=("$@")
(( ${#architectures} )) || architectures=(arm64 x86_64)
for architecture in "${architectures[@]}"; do
  case $architecture in
    arm64|x86_64) ;;
    *) print -u2 "Unsupported macOS architecture: $architecture"; exit 2 ;;
  esac
done

for executable in Otto ottoctl otto-mcp otto-hermes-bridge otto-openai-agent otto-hookd ottod; do
  [[ -x $app_bundle/Contents/MacOS/$executable ]] || {
    print -u2 "Missing executable: $executable"
    exit 1
  }
done
# Check libraries too: a universal main binary cannot load an ARM-only dependency on Intel.
binaries=("$app_bundle"/Contents/MacOS/*(.))
for binary in "${binaries[@]}"; do
  for architecture in "${architectures[@]}"; do
    /usr/bin/lipo "$binary" -verify_arch "$architecture" || {
      print -u2 "${binary:t} is missing the required $architecture slice"
      exit 1
    }
  done
done
print "Verified macOS slices: ${architectures[*]}"
