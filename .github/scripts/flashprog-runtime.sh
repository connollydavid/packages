#!/bin/sh
# Runtime check for one variant, $1. Installs only that variant into the
# stock rootfs, exercises the shared /usr/bin/flashprog command through the
# package's own test.sh, then asserts that every other variant refuses to
# install beside it: they all own the same command and provide the same
# flashprog-bin name, so a second install is a conflict by design.
set -e

me=$1
mkdir -p /var/lock

myapk=$(ls /pkgs/${me}-[0-9]*.apk)
ver=$(apk adbdump "$myapk" | sed -n 's/^  version: //p' | head -1)
ver=${ver%-r*}
if [ -z "$ver" ]; then
	echo "FAIL  could not read the package version"
	exit 1
fi

apk add --allow-untrusted "$myapk"
command -v flashprog > /dev/null || {
	echo "FAIL  /usr/bin/flashprog is not on PATH after installing $me"
	exit 1
}
flashprog --version | head -1

sh /overlay/utils/flashprog/test.sh "$me" "$ver"
echo "test.sh: pass for $me"

for other in flashprog flashprog-external flashprog-pci flashprog-spi; do
	[ "$other" = "$me" ] && continue
	oapk=$(ls /pkgs/${other}-[0-9]*.apk)
	out=$(apk add --allow-untrusted "$oapk" 2>&1) && {
		echo "FAIL  $other installed beside $me"
		exit 1
	}
	echo "$out" | grep -qiE 'conflict|same package name|provides' || {
		echo "FAIL  $other failed to install beside $me for a non-conflict reason:"
		echo "$out"
		exit 1
	}
	echo "ok    $other refuses to install beside $me"
done
echo "$me: install, roundtrip and all three conflicts verified"
