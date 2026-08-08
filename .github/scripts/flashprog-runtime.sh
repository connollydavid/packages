#!/bin/sh
set -e

mkdir -p /var/lock

install_pkg() {
	if command -v apk > /dev/null; then
		apk add --allow-untrusted "$1"
	else
		opkg install "$1"
	fi
}

remove_pkg() {
	if command -v apk > /dev/null; then
		apk del "$1"
	else
		opkg remove "$1"
	fi
}

if command -v apk > /dev/null; then
	full=$(ls /pkgs/flashprog-[0-9]*.apk)
	spi=$(ls /pkgs/flashprog-spi-[0-9]*.apk)
	ver=$(apk adbdump "$full" | sed -n 's/^  version: //p')
else
	full=$(ls /pkgs/flashprog_[0-9]*.ipk)
	spi=$(ls /pkgs/flashprog-spi_[0-9]*.ipk)
	opkg update || echo "note    one or more feeds did not update"
	meta=$(tar -xzOf "$full" ./control.tar.gz | tar -xzO ./control)
	ver=$(echo "$meta" | sed -n 's/^Version: //p')
	deps=$(echo "$meta" | sed -n 's/^Depends: //p' | tr -d ' ' | tr ',' ' ')
	echo "declared: $deps"
	for d in $deps; do
		if [ "$d" != libc ] && ! opkg list "$d" | grep -q .; then
			echo "FAIL  $d is not in the feed"
			exit 1
		fi
	done
fi
ver=${ver%-r*}
if [ -z "$ver" ]; then
	echo "FAIL  could not read the package version"
	exit 1
fi

install_pkg "$full"
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
echo "test.sh: pass for flashprog"

if install_pkg "$spi" > /dev/null 2>&1; then
	echo "FAIL  both variants installed together"
	exit 1
fi
echo "ok    the second variant was refused"

remove_pkg flashprog > /dev/null 2>&1
install_pkg "$spi" > /dev/null
echo "installed: flashprog-spi"
sh /overlay/utils/flashprog/test.sh flashprog-spi "$ver"
echo "test.sh: pass for flashprog-spi"

if flashprog -p ch341a_spi 2>&1 | grep -q "Unknown programmer"; then
	echo "ok    flashprog-spi carries no USB programmer"
else
	echo "FAIL  flashprog-spi carries a USB programmer"
	exit 1
fi
