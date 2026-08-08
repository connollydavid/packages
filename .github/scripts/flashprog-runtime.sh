#!/bin/sh
set -e

mkdir -p /var/lock
if command -v apk > /dev/null; then
	pkg=$(ls /pkgs/flashprog-*.apk)
	ver=$(apk adbdump "$pkg" | sed -n 's/^  version: //p')
	apk add --allow-untrusted "$pkg"
else
	pkg=$(ls /pkgs/flashprog_*.ipk)
	opkg update || echo "note    one or more feeds did not update"
	meta=$(opkg info "$pkg")
	ver=$(echo "$meta" | sed -n 's/^Version: //p')
	deps=$(echo "$meta" | sed -n 's/^Depends: //p' | tr -d ' ' | tr ',' ' ')
	echo "declared: $deps"
	for d in $deps; do
		if [ "$d" != libc ] && ! opkg list "$d" | grep -q .; then
			echo "FAIL  $d is not in the feed"
			exit 1
		fi
	done
	opkg install "$pkg"
fi
ver=${ver%-r*}
echo "installed: flashprog $ver"

flashprog --version | head -1

chip=dummy:emulate=W25Q128FV,image=/tmp/chip.rom
dd if=/dev/urandom of=/tmp/in.bin bs=1M count=16

flashprog -p "$chip" -w /tmp/in.bin | tail -2
flashprog -p "$chip" -v /tmp/in.bin | tail -1
flashprog -p "$chip" -r /tmp/out.bin | tail -1
cmp /tmp/in.bin /tmp/out.bin
echo "roundtrip: identical"
flashprog -p "$chip" -E | tail -1

sh /overlay/utils/flashprog/test.sh flashprog "$ver"
echo "test.sh: pass"
