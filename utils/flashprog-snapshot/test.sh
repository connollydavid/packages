#!/bin/sh

set -e

case "$1" in
flashprog-snapshot) bin=flashprog ;;
flashprog-spi-snapshot) bin=flashprog-spi ;;
*)
	echo "Untested package: $1" >&2
	exit 1
	;;
esac

"$bin" --version | grep "^flashprog v$2"
dd if=/dev/urandom of=/tmp/flashprog.in bs=1k count=4096
"$bin" -p dummy:emulate=SST25VF032B,image=/tmp/flashprog.rom -w /tmp/flashprog.in
"$bin" -p dummy:emulate=SST25VF032B,image=/tmp/flashprog.rom -r /tmp/flashprog.out
cmp /tmp/flashprog.in /tmp/flashprog.out
