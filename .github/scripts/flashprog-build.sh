#!/bin/bash
set -eo pipefail

release=$1
arch=$2

map=$GITHUB_WORKSPACE/.github/scripts/flashprog-arch-map.tsv
target=$(awk -F'\t' -v a="$arch" '$1 == a { print $2 }' "$map")
if [ -z "$target" ]; then
	echo "FAIL  $arch is not in the architecture map"
	exit 1
fi

git clone --depth 1 --filter=blob:none --sparse --branch "$PKG_REF" "$PKG_REPO" pkg
git -C pkg sparse-checkout set utils/flashprog
mkdir -p overlay/utils
cp -r pkg/utils/flashprog overlay/utils/

if [ "$release" = main ]; then
	base="https://downloads.openwrt.org/snapshots/targets/$target"
else
	idx="https://downloads.openwrt.org/releases"
	ver=$(wget -qO- "$idx/" \
		| grep -oE "\"$release\.[0-9]+(-rc[0-9]+)?/\"" \
		| tr -d '"/' | sort -V | tail -1)
	if [ -z "$ver" ]; then
		echo "FAIL  no $release release found"
		exit 1
	fi
	base="$idx/$ver/targets/$target"
fi

matched=
for attempt in 1 2 3; do
	if ! wget -qO sha256sums "$base/sha256sums"; then
		echo "FAIL  $target has no SDK in $release ($base)"
		exit 1
	fi
	sdk=$(grep -oE 'openwrt-sdk[^*]+\.tar\.zst' sha256sums | head -1)
	if [ -z "$sdk" ]; then
		echo "FAIL  no SDK listed for $target in $release"
		exit 1
	fi
	wget -qO sdk.tar.zst "$base/$sdk"
	want=$(grep " \*\?$sdk\$" sha256sums | awk '{print $1}')
	got=$(sha256sum sdk.tar.zst | awk '{print $1}')
	if [ -n "$want" ] && [ "$want" = "$got" ]; then
		matched=y
		break
	fi
	echo "note    attempt $attempt saw $sdk change between the sums and the download"
	echo "        recorded $want"
	echo "        got      $got"
	sleep 30
done
if [ -z "$matched" ]; then
	echo "FAIL  SDK checksum mismatch for $sdk"
	exit 1
fi
echo "ok      sha256 $got  $sdk"
mkdir sdk
tar --zstd -xf sdk.tar.zst -C sdk --strip-components=1

if [ "$release" = main ]; then
	basebranch=main
	pkgbranch=master
else
	basebranch=openwrt-$release
	pkgbranch=openwrt-$release
fi

cd sdk
sed -E \
	-e 's#^src-git-full #src-git #' \
	-e "s#(base https://git\.openwrt\.org/openwrt/openwrt\.git).*#\1;$basebranch#" \
	-e "s#(packages https://git\.openwrt\.org/feed/packages\.git).*#\1;$pkgbranch#" \
	feeds.conf.default | grep -E ' (base|packages) ' > feeds.conf
echo "src-link flashprog $GITHUB_WORKSPACE/overlay" >> feeds.conf
cat feeds.conf

./scripts/feeds update -a
./scripts/feeds install flashprog flashprog-spi

make defconfig > /dev/null
for p in flashprog flashprog-spi; do
	echo "CONFIG_PACKAGE_$p=m" >> .config
done
make defconfig > /dev/null
for p in flashprog flashprog-spi; do
	if ! grep -q "^CONFIG_PACKAGE_$p=m" .config; then
		echo "FAIL  defconfig dropped CONFIG_PACKAGE_$p"
		exit 1
	fi
done
grep -E '^CONFIG_PACKAGE_flashprog' .config

make package/flashprog/compile -j"$(nproc)" V=s 2>&1 | tee "$GITHUB_WORKSPACE/build.log"
