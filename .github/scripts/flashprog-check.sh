#!/bin/bash
set -eo pipefail

arch=$1
log=$GITHUB_WORKSPACE/build.log
fail=0

case $arch in
i386_*|x86_64) x86=y ;;
*) x86=n ;;
esac

NOLIB="buspirate_spi dummy linux_mtd linux_spi pony_spi serprog"
USB="ch341a_spi ch347_spi dediprog developerbox_spi digilent_spi
	dirtyjtag_spi ft2232_spi ft4222_spi jlink_spi pickit2_spi
	stlinkv3_spi usbblaster_spi"
PCI="atavia drkaiser gfxnvidia internal it8212 nic3com nicintel
	nicintel_eeprom nicintel_spi nicrealtek ogp_spi satamv satasii"
OFF="atahpt atapromise linux_gpio_spi mstarddc_spi nicnatsemi"

active_for() {
	awk -v want="$1" '
		match($0, /flashprog-(full|spi)\//) {
			v = substr($0, RSTART + 10, RLENGTH - 11)
		}
		v == want && /^ *active +:/ { f = 1 }
		v == want && f && /^ *non active/ { f = 0 }
		v == want && f {
			sub(/^ *active *: */, "")
			sub(/^ */, "")
			if ($0 ~ /^[a-z0-9_]+$/) print
		}
	' "$log" | sort -u
}

pkgmeta() {
	case $1 in
	*.ipk)
		tar -xzOf "$1" ./control.tar.gz | tar -xzO ./control
		;;
	*.apk)
		sdk/staging_dir/host/bin/apk adbdump "$1"
		;;
	esac
}

pkgsize() {
	case $1 in
	*.ipk)
		tar -xzOf "$1" ./data.tar.gz | tar -tvz \
			| awk '$1 !~ /^d/ { s += $3 } END { print s + 0 }'
		;;
	*.apk)
		sdk/staging_dir/host/bin/apk adbdump "$1" \
			| awk '/^  installed-size:/ { print $2; exit }'
		;;
	esac
}

check_variant() {
	local variant=$1 pkg=$2 present=$3 absent=$4 wantlibs=$5
	local active p

	active=$(active_for "$variant")
	if [ -z "$active" ]; then
		echo "FAIL  $pkg: no programmer summary in the build log"
		fail=1
		return
	fi
	echo "$pkg built: $(echo $active)"

	for p in $present; do
		if ! echo "$active" | grep -qx "$p"; then
			echo "FAIL  $pkg: $p is missing"
			fail=1
		fi
	done
	for p in $absent; do
		if echo "$active" | grep -qx "$p"; then
			echo "FAIL  $pkg: $p was built"
			fail=1
		fi
	done

	local f
	f=$(find sdk/bin -type f \
		\( -name "$pkg-[0-9]*" -o -name "${pkg}_[0-9]*" \) | head -1)
	if [ -z "$f" ]; then
		echo "FAIL  $pkg: no package was produced"
		fail=1
		return
	fi

	local meta deps size
	meta=$(pkgmeta "$f")
	size=$(pkgsize "$f")
	case $f in
	*.ipk)
		deps=$(echo "$meta" | sed -n 's/^Depends: //p' | tr -d ' ' | tr ',' ' ')
		;;
	*.apk)
		deps=$(echo "$meta" | sed -n '/^  depends:/,/^  [a-z]/p' \
			| sed -n 's/^ *- //p' | tr '\n' ' ')
		;;
	esac
	echo "$pkg: $(basename "$f")  size $size  depends: $deps"

	local binary=n
	case $f in
	*.ipk)
		if tar -xzOf "$f" ./data.tar.gz | tar -tz \
			| grep -qx '\./usr/bin/flashprog'; then
			binary=y
		fi
		;;
	*.apk)
		if echo "$meta" | awk '
			/^  - name: usr\/bin$/ { f = 1; next }
			/^  - name: / { f = 0 }
			f && /^      - name: flashprog$/ { found = 1 }
			END { exit !found }'; then
			binary=y
		fi
		;;
	esac
	if [ "$binary" != y ]; then
		echo "FAIL  $pkg: /usr/bin/flashprog is not in the package"
		fail=1
	fi

	local total=$size d df ds
	for d in $wantlibs; do
		case " $deps " in
		*" $d "*|*" $d-0 "*) ;;
		*)
			echo "FAIL  $pkg: $d is not a dependency"
			fail=1
			continue
			;;
		esac
	done
	for d in $deps; do
		[ "$d" = libc ] && continue
		case " $wantlibs " in
		*" ${d%-0} "*) ;;
		*)
			echo "FAIL  $pkg: unexpected dependency $d"
			fail=1
			;;
		esac
		df=$(find sdk/bin -type f \
			\( -name "$d-[0-9]*" -o -name "${d}_[0-9]*" \) | head -1)
		[ -z "$df" ] && continue
		ds=$(pkgsize "$df")
		total=$((total + ds))
		echo "  lib $d $ds"
	done
	echo "$pkg total: $total"
}

full_present="$NOLIB $USB"
full_absent="$OFF"
full_libs="libftdi1 libjaylink libusb-1.0"
spi_present="$NOLIB"
spi_absent="$OFF $USB"

if [ "$x86" = y ]; then
	full_present="$full_present $PCI rayer_spi"
	full_libs="$full_libs libpci"
	spi_present="$spi_present rayer_spi"
	spi_absent="$spi_absent $PCI"
else
	full_absent="$full_absent $PCI rayer_spi"
	spi_absent="$spi_absent $PCI rayer_spi"
fi

check_variant full flashprog "$full_present" "$full_absent" "$full_libs"
check_variant spi flashprog-spi "$spi_present" "$spi_absent" ""

exit $fail
