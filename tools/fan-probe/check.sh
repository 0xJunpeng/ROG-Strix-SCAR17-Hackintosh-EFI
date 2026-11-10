#!/bin/bash
# check.sh — 读取 NvFanProbe 的结果（不需要 sudo）
#
#   ./check.sh              读取结果
#   ./check.sh --off        从 OpenCore config.plist 里移除探针条目（可回滚，需 ESP 已挂载）
#
# ESP 路径默认自动探测（在 /Volumes/* 里找 EFI/OC/config.plist），
# 也可手动指定：ESP=/Volumes/SYSTEM ./check.sh
set -u

# ---------- 自动探测 ESP ----------
find_esp() {
    if [ -n "${ESP:-}" ]; then echo "$ESP"; return; fi
    for v in /Volumes/*; do
        if [ -f "$v/EFI/OC/config.plist" ]; then echo "$v"; return; fi
    done
}

ESP_DIR=$(find_esp)

if [ "${1:-}" = "--off" ]; then
    [ -n "$ESP_DIR" ] || { echo "STOP: 找不到已挂载的 ESP，先 sudo diskutil mount <EFI 分区>"; exit 1; }
    echo "ESP: $ESP_DIR"
    /usr/bin/python3 - "$ESP_DIR" <<'PY'
import plistlib, shutil, datetime, sys, os
esp = sys.argv[1]
p = os.path.join(esp, "EFI/OC/config.plist")
d = plistlib.load(open(p, "rb"))
bak = p + ".before-fanprobe-remove-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
shutil.copy2(p, bak)
add = d["Kernel"]["Add"]
before = len(add)
add[:] = [e for e in add if e.get("BundlePath") != "NvFanProbe.kext"]
plistlib.dump(d, open(p, "wb"), sort_keys=False)
print(f"已移除 NvFanProbe 条目（{before} -> {len(add)}），备份：{os.path.basename(bak)}")
PY
    echo "彻底删除 kext：sudo rm -rf \"$ESP_DIR/EFI/OC/Kexts/NvFanProbe.kext\""
    exit 0
fi

echo "== 1. kext 是否已加载"
kmutil showloaded --list-only 2>/dev/null | grep -i nvfanprobe || echo "   (未加载)"

echo "== 2. ioreg 中的探针结果"
ioreg -l 2>/dev/null | grep -o '"nvfanprobe" = "[^"]*"' | head -3 || echo "   (没有 nvfanprobe 属性)"

echo "== 3. 内核日志"
log show --last boot --predicate 'process == "kernel"' 2>/dev/null \
    | grep -E "NvFanProbe:" | tail -20 || echo "   (日志里没有)"
