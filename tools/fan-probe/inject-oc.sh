#!/bin/bash
# inject-oc.sh — 把 out/NvFanProbe.kext 注入 OpenCore（拷贝进 Kexts + 在 config.plist 加启用条目）
#
#   sudo ./inject-oc.sh [ESP挂载点]
#
# 不传参数时自动探测已挂载的 ESP（在 /Volumes/* 里找 EFI/OC/config.plist）。
# 改动前会备份 config.plist；回滚用 ./check.sh --off
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
KEXT="$DIR/out/NvFanProbe.kext"
ENTRY="NvFanProbe.kext"

[ -d "$KEXT" ] || { echo "STOP: 找不到 $KEXT，先跑 ./build.sh"; exit 1; }
[ "$(id -u)" = "0" ] || { echo "STOP: 需要 sudo 运行（要写 ESP）"; exit 1; }

ESP_DIR="${1:-}"
if [ -z "$ESP_DIR" ]; then
    for v in /Volumes/*; do
        if [ -f "$v/EFI/OC/config.plist" ]; then ESP_DIR="$v"; break; fi
    done
fi
[ -n "$ESP_DIR" ] && [ -f "$ESP_DIR/EFI/OC/config.plist" ] || {
    echo "STOP: 找不到 OpenCore 配置；请先挂载 EFI 分区：sudo diskutil mount <分区>"
    echo "      或手动指定：sudo ./inject-oc.sh /Volumes/SYSTEM"
    exit 1
}

echo "ESP: $ESP_DIR"
echo "== 1. 拷贝 kext 到 EFI/OC/Kexts"
if mount | grep -q " on $ESP_DIR .*read-only"; then
    echo "STOP: $ESP_DIR 是只读挂载，先 sudo mount -uw $ESP_DIR"; exit 1
fi
rm -rf "$ESP_DIR/EFI/OC/Kexts/$ENTRY"
cp -R "$KEXT" "$ESP_DIR/EFI/OC/Kexts/$ENTRY"
chown -R 0:0 "$ESP_DIR/EFI/OC/Kexts/$ENTRY"
echo "   -> EFI/OC/Kexts/$ENTRY"

echo "== 2. 写入 config.plist 条目"
/usr/bin/python3 - "$ESP_DIR" <<'PY'
import plistlib, shutil, datetime, sys, os
esp = sys.argv[1]
p = os.path.join(esp, "EFI/OC/config.plist")
bak = p + ".before-fanprobe-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
shutil.copy2(p, bak)
d = plistlib.load(open(p, "rb"))
add = d["Kernel"]["Add"]
add[:] = [e for e in add if e.get("BundlePath") != "NvFanProbe.kext"]
idx = next((i for i, e in enumerate(add) if e.get("BundlePath") == "SMCNvidiaGPU.kext"), len(add) - 1) + 1
add.insert(idx, {
    "Arch": "x86_64",
    "BundlePath": "NvFanProbe.kext",
    "Comment": "EC fan probe (read-only, test only)",
    "Enabled": True,
    "ExecutablePath": "Contents/MacOS/NvFanProbe",
    "MaxKernel": "",
    "MinKernel": "",
    "PlistPath": "Contents/Info.plist",
})
plistlib.dump(d, open(p, "wb"), sort_keys=False)
print(f"   条目已加入，Kernel>Add 共 {len(add)} 条")
print(f"   备份：{os.path.basename(bak)}")
PY

echo "== 完成，重启后在 EFI/OC/Kexts/$ENTRY 生效"
echo "   重启后读结果：./check.sh"
echo "   回滚：sudo ./check.sh --off"
