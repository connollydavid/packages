#!/bin/sh
set -e

mkdir -p /var/lock
if command -v apk > /dev/null; then
	apk add --allow-untrusted /pkgs/flashprog-*.apk
else
	opkg update || echo "note    one or more feeds did not update"
	deps=$(opkg info /pkgs/flashprog_*.ipk \
		| sed -n 's/^Depends: //p' | tr -d ' ' | tr ',' ' ')
	echo "declared: $deps"
	for d in $deps; do
		if [ "$d" != libc ] && ! opkg list "$d" | grep -q .; then
			echo "FAIL  $d is not in the feed"
			exit 1
		fi
	done
	opkg install /pkgs/flashprog_*.ipk
fi

flashprog --version | head -1

chip=dummy:emulate=W25Q128FV,image=/tmp/chip.rom
dd if=/dev/urandom of=/tmp/in.bin bs=1M count=16 2>/dev/null

flashprog -p "$chip" -w /tmp/in.bin | tail -2
flashprog -p "$chip" -v /tmp/in.bin | tail -1
flashprog -p "$chip" -r /tmp/out.bin | tail -1
cmp /tmp/in.bin /tmp/out.bin
echo "roundtrip: identical"
flashprog -p "$chip" -E | tail -1
