#!/bin/bash
set -eo pipefail

arch=$1
log=$GITHUB_WORKSPACE/build.log

active=$(sed -n '/^ *active *:/,/^ *non active/p' "$log" \
	| sed -e 's/^ *active *: *//' -e 's/^ *//' \
	| grep -E '^[a-z0-9_]+$' | sort -u)
if [ -z "$active" ]; then
	echo "FAIL  no programmer summary in the build log"
	exit 1
fi
echo "built: $(echo $active)"

fail=0

want() {
	local p
	for p in "$@"; do
		if ! echo "$active" | grep -qx "$p"; then
			echo "FAIL  $p is missing"
			fail=1
		fi
	done
}

lack() {
	local p
	for p in "$@"; do
		if echo "$active" | grep -qx "$p"; then
			echo "FAIL  $p was built"
			fail=1
		fi
	done
}

want buspirate_spi ch341a_spi ch347_spi dediprog developerbox_spi \
	digilent_spi dirtyjtag_spi dummy ft2232_spi ft4222_spi jlink_spi \
	linux_mtd linux_spi pickit2_spi pony_spi serprog stlinkv3_spi \
	usbblaster_spi
lack atahpt atapromise linux_gpio_spi mstarddc_spi nicnatsemi

pci="atavia drkaiser gfxnvidia internal it8212 nic3com nicintel
	nicintel_eeprom nicintel_spi nicrealtek ogp_spi rayer_spi satamv
	satasii"

case $arch in
i386_*|x86_64)
	want $pci
	;;
*)
	lack $pci
	;;
esac

pkg=$(find sdk/bin -type f -name 'flashprog[-_]*' | head -1)
if [ -z "$pkg" ]; then
	echo "FAIL  no package was produced"
	exit 1
fi
echo "package: $(basename "$pkg")"

case $pkg in
*.ipk)
	meta=$(tar -xzOf "$pkg" ./control.tar.gz | tar -xzO ./control)
	deps=$(echo "$meta" | sed -n 's/^Depends: //p' | tr -d ' ' | tr ',' ' ')
	size=$(tar -xzOf "$pkg" ./data.tar.gz | tar -tvz \
		| awk '$NF == "./usr/bin/flashprog" { print $3 }')
	if tar -xzOf "$pkg" ./data.tar.gz | tar -tz | grep -q '^\./usr/bin/flashprog$'; then
		binary=y
	fi
	;;
*.apk)
	meta=$(sdk/staging_dir/host/bin/apk adbdump "$pkg")
	deps=$(echo "$meta" | sed -n '/^  depends:/,/^  [a-z]/p' | sed -n 's/^ *- //p')
	size=$(echo "$meta" | awk '
		/^  - name: usr\/bin$/ { f = 1; next }
		/^  - name: / { f = 0 }
		f && /^      - name: flashprog$/ { g = 1; next }
		g && /^ *size: / { print $2; exit }')
	if echo "$meta" | awk '
		/^  - name: usr\/bin$/ { f = 1; next }
		/^  - name: / { f = 0 }
		f && /^      - name: flashprog$/ { found = 1 }
		END { exit !found }'; then
		binary=y
	fi
	;;
esac
deps=$(echo "$deps" | tr '\n' ' ')
echo "depends: $deps"
echo "size: $size"

pkgsize() {
	local f=$1
	case $f in
	*.ipk)
		tar -xzOf "$f" ./data.tar.gz | tar -tvz \
			| awk '$1 !~ /^d/ { s += $3 } END { print s + 0 }'
		;;
	*.apk)
		sdk/staging_dir/host/bin/apk adbdump "$f" \
			| awk '/^  installed-size:/ { print $2; exit }'
		;;
	esac
}

total=$size
report=
for d in $deps; do
	[ "$d" = libc ] && continue
	df=$(find sdk/bin -type f \( -name "$d-[0-9]*" -o -name "${d}_[0-9]*" \) \
		| head -1)
	if [ -z "$df" ]; then
		report="$report $d=?"
		continue
	fi
	ds=$(pkgsize "$df")
	report="$report $d=$ds"
	total=$((total + ds))
done
echo "libs:$report"
echo "total: $total"

if [ "$binary" != y ]; then
	echo "FAIL  usr/bin/flashprog is not in the package"
	fail=1
fi

for d in libftdi1 libjaylink libusb-1.0; do
	case " $deps " in
	*" $d "*|*" $d-0 "*) ;;
	*)
		echo "FAIL  $d is not a dependency"
		fail=1
		;;
	esac
done

case " $deps " in
*" libpci "*) haspci=y ;;
*) haspci=n ;;
esac

case $arch in
i386_*|x86_64)
	if [ "$haspci" = n ]; then
		echo "FAIL  libpci is not a dependency on $arch"
		fail=1
	fi
	;;
*)
	if [ "$haspci" = y ]; then
		echo "FAIL  libpci is a dependency on $arch"
		fail=1
	fi
	;;
esac

exit $fail
