#!/bin/bash
# 构建 NvFanProbe.kext（只读探针，无需 Xcode，只要 Command Line Tools）
# 产物固定输出到 out/NvFanProbe.kext（归当前用户；加载前由 run-probe.sh 改成 root:wheel）
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --show-sdk-path)
KHDR="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
KEXT=out/NvFanProbe.kext
BIN="$KEXT/Contents/MacOS/NvFanProbe"

[ -d "$KHDR" ] || { echo "STOP: 找不到内核头文件 $KHDR"; exit 1; }

rm -rf out
mkdir -p "$KEXT/Contents/MacOS"

echo "== 编译"
xcrun clang++ -arch x86_64 -fapple-kext -mkernel -nostdinc -I"$KHDR" \
    -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
    -std=c++17 -fno-rtti -fno-exceptions -fno-builtin -fno-common -O2 \
    -Wall -Wno-unused-parameter -Wno-ossharedptr-misuse -Wno-sign-conversion \
    -c NvFanProbe.cpp -o build-probe.o

echo "== 链接"
xcrun clang++ -arch x86_64 -fapple-kext -nostdlib -Xlinker -kext \
    -lkmodc++ -lkmod -lcc_kext \
    build-probe.o -o "$BIN"

rm -f build-probe.o
cp Info.plist "$KEXT/Contents/Info.plist"
chmod 755 "$KEXT" "$KEXT/Contents" "$KEXT/Contents/MacOS" "$BIN"
chmod 644 "$KEXT/Contents/Info.plist"
xattr -cr "$KEXT" 2>/dev/null || true

echo "== 签名（ad-hoc）"
codesign --force --sign - "$KEXT"
codesign --verify --strict "$KEXT" && echo "   签名 OK"

echo "== 检查 _kmod_info"
if nm -m "$BIN" | grep -q "_kmod_info"; then echo "   _kmod_info 存在 OK"; else echo "   !! 缺少 _kmod_info"; exit 1; fi

echo "OK: $PWD/$KEXT  ($(stat -f %z "$BIN") B)"
