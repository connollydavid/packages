#!/bin/bash
set -eo pipefail

mode=$1
arch=$2
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

want buspirate_spi dummy linux_mtd linux_spi pony_spi serprog
lack atahpt atapromise linux_gpio_spi mstarddc_spi nicnatsemi

case $arch in
i386_*|x86_64)
	want rayer_spi
	;;
*)
	lack rayer_spi
	;;
esac

if [ "$mode" = minimal ]; then
	lack atavia ch341a_spi dediprog ft2232_spi ft4222_spi internal \
		jlink_spi satasii stlinkv3_spi usbblaster_spi
else
	want atavia ch341a_spi ch347_spi dediprog developerbox_spi \
		digilent_spi dirtyjtag_spi ft2232_spi ft4222_spi jlink_spi \
		pickit2_spi stlinkv3_spi usbblaster_spi
	case $arch in
	riscv64_*|loongarch64_*)
		lack drkaiser gfxnvidia internal it8212 nicintel \
			nicintel_eeprom nicintel_spi ogp_spi satasii
		;;
	i386_*|x86_64)
		want drkaiser gfxnvidia internal it8212 nic3com nicintel \
			nicintel_eeprom nicintel_spi nicrealtek ogp_spi \
			satamv satasii
		;;
	*)
		want drkaiser gfxnvidia internal it8212 nicintel \
			nicintel_eeprom nicintel_spi ogp_spi satasii
		lack nic3com nicrealtek satamv
		;;
	esac
fi

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
	if tar -xzOf "$pkg" ./data.tar.gz | tar -tz | grep -q '^\./usr/bin/flashprog$'; then
		binary=y
	fi
	;;
*.apk)
	meta=$(sdk/staging_dir/host/bin/apk adbdump "$pkg")
	deps=$(echo "$meta" | sed -n '/^  depends:/,/^  [a-z]/p' | sed -n 's/^ *- //p')
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

if [ "$binary" != y ]; then
	echo "FAIL  usr/bin/flashprog is not in the package"
	fail=1
fi

for d in libftdi1 libjaylink libpci; do
	case " $deps " in
	*" $d "*) has=y ;;
	*) has=n ;;
	esac
	if [ "$mode" = minimal ] && [ "$has" = y ]; then
		echo "FAIL  $d is a dependency of the minimal build"
		fail=1
	fi
	if [ "$mode" != minimal ] && [ "$has" = n ]; then
		echo "FAIL  $d is not a dependency of the default build"
		fail=1
	fi
done

exit $fail
