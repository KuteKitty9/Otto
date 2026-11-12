#!/bin/zsh
# Exercise slice verification without compiling or running Otto.
set -euo pipefail
script_dir=${0:A:h}
fixture=$(mktemp -d /tmp/otto-architecture-test.XXXXXX)
trap '/bin/rm -rf "$fixture"' EXIT
app=$fixture/Otto.app
/bin/mkdir -p "$app/Contents/MacOS"
host_arch=$(/usr/bin/uname -m)
for executable in Otto ottoctl otto-mcp otto-hermes-bridge otto-openai-agent otto-hookd ottod; do
  /usr/bin/lipo /bin/echo -extract_family "$host_arch" -output "$app/Contents/MacOS/$executable" 2>/dev/null \
    || /bin/cp /bin/echo "$app/Contents/MacOS/$executable"
  /bin/chmod 755 "$app/Contents/MacOS/$executable"
done
"$script_dir/verify-macos-architectures.sh" "$app" "$host_arch"
if "$script_dir/verify-macos-architectures.sh" "$app" >"$fixture/error" 2>&1; then
  print -u2 "A native-only app must not pass universal validation."
  exit 1
fi
/bin/rm "$app/Contents/MacOS/ottod"
if "$script_dir/verify-macos-architectures.sh" "$app" "$host_arch" >"$fixture/error" 2>&1; then
  print -u2 "An app missing ottod must fail validation."
  exit 1
fi
/usr/bin/grep -q "Missing executable: ottod" "$fixture/error"
/bin/cp "$app/Contents/MacOS/Otto" "$app/Contents/MacOS/ottod"
print 'invalid library' > "$app/Contents/MacOS/libBroken.dylib"
if "$script_dir/verify-macos-architectures.sh" "$app" "$host_arch" >"$fixture/error" 2>&1; then
  print -u2 "An app with an incompatible bundled library must fail validation."
  exit 1
fi
/usr/bin/grep -q "libBroken.dylib is missing" "$fixture/error"
print "Architecture verification regression checks passed."
