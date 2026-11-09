#!/bin/sh
# Builds mbedTLS 3.6.7 for modern iOS (arm64, iOS 15+) into out/modern. Needs macOS with Xcode.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
VER=3.6.7
"$HERE/fetch.sh" --verify-only
TARBALL="$HERE/download/mbedtls-$VER.tar.bz2"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos -f clang)"
AR="$(xcrun --sdk iphoneos -f ar)"
RANLIB="$(xcrun --sdk iphoneos -f ranlib)"
J="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

WORK="$HERE/build/modern"
SRC="$WORK/mbedtls-$VER"
rm -rf "$WORK" && mkdir -p "$WORK"
tar -xjf "$TARBALL" -C "$WORK"
CFLAGS="-Os -arch arm64 -isysroot $SDK -miphoneos-version-min=15.0 -I$SRC/include -I$HERE -include $HERE/mbedtls_ios6_predef.h"
make -C "$SRC/library" -j"$J" CC="$CC" AR="$AR" RANLIB="$RANLIB" CFLAGS="$CFLAGS" \
     libmbedcrypto.a libmbedx509.a libmbedtls.a
"$CC" $CFLAGS -c "$HERE/mbedtls_ios6_alt.c" -o "$WORK/mbedtls_ios6_alt.o"
OUT="$HERE/out/modern"
rm -rf "$OUT" && mkdir -p "$OUT/lib"
cp "$SRC/library/libmbedtls.a" "$SRC/library/libmbedx509.a" "$SRC/library/libmbedcrypto.a" "$OUT/lib/"
"$AR" rcs "$OUT/lib/libmbedcrypto.a" "$WORK/mbedtls_ios6_alt.o"
"$RANLIB" "$OUT/lib/libmbedcrypto.a"
cp -R "$SRC/include" "$OUT/include"
cp "$HERE/mbedtls_ios6_config.h" "$HERE/mbedtls_ios6_predef.h" "$OUT/include/"
echo "built $OUT"
