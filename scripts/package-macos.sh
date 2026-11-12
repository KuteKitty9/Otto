#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repository_root=${script_dir:h}
configuration=${OTTO_BUILD_CONFIGURATION:-${MUSE_BUILD_CONFIGURATION:-release}}
version=${OTTO_VERSION:-${MUSE_VERSION:-0.1.0}}
build_number=${OTTO_BUILD_NUMBER:-${MUSE_BUILD_NUMBER:-1}}
signing_identity=${OTTO_CODESIGN_IDENTITY:-${MUSE_CODESIGN_IDENTITY:--}}
distribution_dir=${OTTO_DISTRIBUTION_DIR:-${MUSE_DISTRIBUTION_DIR:-$repository_root/.build/distribution}}
archive=$distribution_dir/Otto-$version.zip
staging_dir=$(mktemp -d /tmp/otto-package.XXXXXX)
app_bundle=$staging_dir/Otto.app
trap '/bin/rm -rf "$staging_dir"' EXIT

case $distribution_dir in
  $repository_root/.build/*) ;;
  *)
    print -u2 "OTTO_DISTRIBUTION_DIR must be inside $repository_root/.build"
    exit 2
    ;;
esac

# Build each slice with SwiftPM's native build system. This preserves the resource
# bundles and avoids switching to a different build system for universal output.
architectures=(arm64 x86_64)
executables=(Otto ottoctl otto-mcp otto-hermes-bridge otto-openai-agent otto-hookd ottod)
typeset -A binary_dirs
for architecture in "${architectures[@]}"; do
  "$script_dir/otto-swift" build \
    -c "$configuration" --arch "$architecture" \
    -Xswiftc -warnings-as-errors
  binary_dirs[$architecture]=$("$script_dir/otto-swift" build \
    -c "$configuration" --arch "$architecture" \
    --show-bin-path | /usr/bin/tail -n 1)
  [[ -d ${binary_dirs[$architecture]} ]] || {
    print -u2 "Could not locate the $architecture SwiftPM product directory."
    exit 2
  }
done
# Resources are architecture-independent; use the native build's bundles.
binary_dir=${binary_dirs[$(/usr/bin/uname -m)]}

/bin/mkdir -p "$distribution_dir"
/bin/mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
for executable in "${executables[@]}"; do
  slices=()
  for architecture in "${architectures[@]}"; do
    slices+=("${binary_dirs[$architecture]}/$executable")
  done
  /usr/bin/lipo -create "${slices[@]}" -output "$app_bundle/Contents/MacOS/$executable"
  /bin/chmod 755 "$app_bundle/Contents/MacOS/$executable"
done

# Newer toolchains link back-deployment libraries such as libswiftCompatibilitySpan
# through @rpath. macOS 26+ ships them, older supported systems need the bundled copy.
toolchain_swift_dir=$(/usr/bin/xcrun --find swift)
toolchain_swift_dir=${toolchain_swift_dir:h:h}/lib
for executable in "$app_bundle"/Contents/MacOS/*(.); do
  for library in ${(f)"$(/usr/bin/otool -L "$executable" | /usr/bin/awk '$1 ~ /^@rpath\/libswift.*\.dylib$/ { sub("@rpath/", "", $1); print $1 }')"}; do
    [[ -f $app_bundle/Contents/MacOS/$library ]] && continue
    source_library=( "$toolchain_swift_dir"/swift-*/macosx/$library(N) )
    (( ${#source_library} )) || {
      print -u2 "${executable:t} needs $library, which is not in the toolchain at $toolchain_swift_dir"
      exit 2
    }
    /usr/bin/install -m 755 "${source_library[-1]}" "$app_bundle/Contents/MacOS/$library"
  done
  # Drop rpaths that only exist on the build machine (Xcode, Metal toolchain cryptex).
  for rpath in ${(f)"$(/usr/bin/otool -l "$executable" | /usr/bin/awk '/cmd LC_RPATH/ { getline; getline; print $2 }' | /usr/bin/sort -u)"}; do
    [[ $rpath == @* || $rpath == /usr/lib/* ]] && continue
    /usr/bin/install_name_tool -delete_rpath "$rpath" "$executable"
  done
done

# Include back-deployment libraries in the architecture check before signing.
"$script_dir/verify-macos-architectures.sh" "$app_bundle"

/usr/bin/install -m 644 "$repository_root/packaging/Info.plist" "$app_bundle/Contents/Info.plist"
/usr/bin/install -m 644 "$repository_root/packaging/AppIcon.icns" \
  "$app_bundle/Contents/Resources/AppIcon.icns"
/usr/bin/install -m 644 "$repository_root/packaging/THIRD_PARTY_NOTICES.md" "$app_bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
for resource_bundle in "$binary_dir/SwiftTerm_SwiftTerm.bundle" "$binary_dir/Otto_OttoApp.bundle" "$binary_dir/Otto_OttoServices.bundle"; do
  [[ -d $resource_bundle ]] || {
    print -u2 "Missing required resource bundle: $resource_bundle"
    exit 2
  }
  /usr/bin/ditto --norsrc "$resource_bundle" "$app_bundle/Contents/Resources/${resource_bundle:t}"
done
/bin/chmod -R u+w "$app_bundle"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$app_bundle/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$build_number" "$app_bundle/Contents/Info.plist"
"$repository_root/scripts/configure-private-phone" "$app_bundle/Contents/Info.plist"
"$repository_root/scripts/configure-google-app-client" "$app_bundle/Contents/Info.plist"
/usr/bin/plutil -lint "$app_bundle/Contents/Info.plist"
/usr/bin/xattr -cr "$app_bundle"

if [[ $signing_identity == - ]]; then
  codesign_options=(--force --sign - --timestamp=none)
else
  codesign_options=(--force --sign "$signing_identity" --timestamp --options runtime)
fi

for library in "$app_bundle"/Contents/MacOS/*.dylib(N); do
  /usr/bin/codesign "${codesign_options[@]}" "$library"
done
/usr/bin/codesign "${codesign_options[@]}" "$app_bundle/Contents/MacOS/ottoctl"
/usr/bin/codesign "${codesign_options[@]}" "$app_bundle/Contents/MacOS/otto-mcp"
/usr/bin/codesign "${codesign_options[@]}" "$app_bundle/Contents/MacOS/otto-hermes-bridge"
/usr/bin/codesign "${codesign_options[@]}" "$app_bundle/Contents/MacOS/otto-openai-agent"
/usr/bin/codesign "${codesign_options[@]}" "$app_bundle/Contents/MacOS/otto-hookd"
/usr/bin/codesign "${codesign_options[@]}" "$app_bundle/Contents/MacOS/ottod"
/usr/bin/codesign "${codesign_options[@]}" --entitlements "$repository_root/packaging/Otto.entitlements" "$app_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_bundle"

/bin/rm -f "$archive"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc -c -k --keepParent "$app_bundle" "$archive"
/usr/bin/shasum -a 256 "$archive" > "$archive.sha256"

print "$archive"
