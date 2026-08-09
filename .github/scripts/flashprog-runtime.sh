#!/bin/sh
set -e

mkdir -p /var/lock

full=$(ls /pkgs/flashprog-[0-9]*.apk)
ext=$(ls /pkgs/flashprog-external-[0-9]*.apk)
pci=$(ls /pkgs/flashprog-pci-[0-9]*.apk)
spi=$(ls /pkgs/flashprog-spi-[0-9]*.apk)

ver=$(apk adbdump "$full" | sed -n 's/^  version: //p')
ver=${ver%-r*}
if [ -z "$ver" ]; then
	echo "FAIL  could not read the package version"
	exit 1
fi

for p in "$full" "$ext" "$pci" "$spi"; do
	apk add --allow-untrusted "$p"
done
echo "installed: flashprog $ver, all four variants together"
for b in flashprog flashprog-external flashprog-pci flashprog-spi; do
	"$b" --version | head -1
done

chip=dummy:emulate=W25Q128FV,image=/tmp/chip.rom
dd if=/dev/urandom of=/tmp/in.bin bs=1M count=16
flashprog -p "$chip" -w /tmp/in.bin | tail -2
flashprog -p "$chip" -v /tmp/in.bin | tail -1
flashprog -p "$chip" -r /tmp/out.bin | tail -1
cmp /tmp/in.bin /tmp/out.bin
echo "roundtrip: identical"
flashprog -p "$chip" -E | tail -1

for p in flashprog flashprog-external flashprog-pci flashprog-spi; do
	sh /overlay/utils/flashprog/test.sh "$p" "$ver"
	echo "test.sh: pass for $p"
done

for p in flashprog-pci flashprog-spi; do
	if "$p" -p ch341a_spi 2>&1 | grep "Unknown programmer"; then
		echo "ok    $p carries no USB programmer"
	else
		echo "FAIL  $p carries a USB programmer"
		exit 1
	fi
done

for p in flashprog-external flashprog-spi; do
	if "$p" -p internal 2>&1 | grep "Unknown programmer"; then
		echo "ok    $p carries no internal programmer"
	else
		echo "FAIL  $p carries the internal programmer"
		exit 1
	fi
done
