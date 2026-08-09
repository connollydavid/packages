#!/bin/bash
set -eo pipefail

arch=$1
log=$GITHUB_WORKSPACE/build.log
fail=0

case $arch in
x86_64)        fam=x86_64 ;;
i386_*)        fam=x86 ;;
aarch64_*)     fam=aarch64 ;;
arm_*|armeb_*) fam=arm ;;
mips64*)       fam=mips64 ;;
mips_*|mipsel_*) fam=mips ;;
powerpc64*)    fam=ppc64 ;;
powerpc_*)     fam=ppc ;;
riscv64_*)     fam=riscv64 ;;
loongarch64_*) fam=loongarch64 ;;
*)
	echo "FAIL  unknown architecture $arch"
	exit 1
	;;
esac

BASE="dummy linux_mtd linux_spi mstarddc_spi"
EXT="buspirate_spi ch341a_spi ch347_spi dediprog developerbox_spi digilent_spi
	dirtyjtag_spi ft2232_spi ft4222_spi jlink_spi linux_gpio_spi pickit2_spi
	pony_spi serprog stlinkv3_spi usbblaster_spi"
PCI_ANY="atavia"
PCI_RAW="drkaiser gfxnvidia internal it8212 nicintel nicintel_eeprom
	nicintel_spi ogp_spi satasii"
PCI_PORT="atahpt atapromise nic3com nicnatsemi nicrealtek rayer_spi satamv"
OFF="mediatek_i2c_spi parade_lspcon raiden_debug_spi realtek_mst_i2c_spi"

case $fam in
x86|x86_64)
	PCI="$PCI_ANY $PCI_RAW $PCI_PORT"
	PCI_ABSENT=""
	;;
aarch64|arm|mips|mips64|ppc|ppc64)
	PCI="$PCI_ANY $PCI_RAW"
	PCI_ABSENT="$PCI_PORT"
	;;
*)
	PCI="$PCI_ANY"
	PCI_ABSENT="$PCI_RAW $PCI_PORT"
	;;
esac

echo "architecture $arch maps to cpu family $fam"

active_for() {
	awk -v want="$1" '
		match($0, /flashprog-(full|pci|spi|external)\//) {
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
	sdk/staging_dir/host/bin/apk adbdump "$1"
}

pkgsize() {
	sdk/staging_dir/host/bin/apk adbdump "$1" \
		| awk '/^  installed-size:/ { print $2; exit }'
}

check_variant() {
	local variant=$1 pkg=$2 bin=$3 present=$4 absent=$5 wantlibs=$6
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
	f=$(find sdk/bin -type f -name "$pkg-[0-9]*.apk" | head -1)
	if [ -z "$f" ]; then
		echo "FAIL  $pkg: no package was produced"
		fail=1
		return
	fi

	local meta deps size
	meta=$(pkgmeta "$f")
	size=$(pkgsize "$f")
	deps=$(echo "$meta" | sed -n '/^  depends:/,/^  [a-z]/p' \
		| sed -n 's/^ *- //p' | tr '\n' ' ')
	echo "$pkg: $(basename "$f")  size $size  depends: $deps"

	if ! echo "$meta" | awk -v bin="$bin" '
		/^  - name: usr\/bin$/ { f = 1; next }
		/^  - name: / { f = 0 }
		f && $0 == "      - name: " bin { found = 1 }
		END { exit !found }'; then
		echo "FAIL  $pkg: /usr/bin/$bin is not in the package"
		fail=1
	fi

	local total=$size d df ds
	for d in $wantlibs; do
		case " $deps " in
		*" $d "*|*" $d-0 "*) ;;
		*)
			echo "FAIL  $pkg: $d is not a dependency"
			fail=1
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
		df=$(find sdk/bin -type f -name "$d-[0-9]*.apk" | head -1)
		[ -z "$df" ] && continue
		ds=$(pkgsize "$df")
		total=$((total + ds))
		echo "  lib $d $ds"
	done
	echo "$pkg total: $total"
}

check_variant full flashprog flashprog \
	"$BASE $EXT $PCI" "$OFF $PCI_ABSENT" \
	"libftdi1 libgpiod libjaylink libpci libusb-1.0"
check_variant pci flashprog-pci flashprog-pci \
	"$BASE $PCI" "$OFF $EXT $PCI_ABSENT" \
	"libpci"
check_variant external flashprog-external flashprog-external \
	"$BASE $EXT" "$OFF $PCI_ANY $PCI_RAW $PCI_PORT" \
	"libftdi1 libgpiod libjaylink libusb-1.0"
check_variant spi flashprog-spi flashprog-spi \
	"$BASE" "$OFF $EXT $PCI_ANY $PCI_RAW $PCI_PORT" \
	""

exit $fail
