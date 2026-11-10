#!/bin/bash
# gen-three-codes.sh — 为黑苹果 OpenCore 生成/写入三码（Serial / MLB / UUID / ROM）
#
# 用法：
#   ./tools/gen-three-codes.sh                      # 按默认机型生成 1 组，只打印
#   ./tools/gen-three-codes.sh -n 3                 # 生成 3 组备选
#   ./tools/gen-three-codes.sh -m iMac20,1          # 指定机型
#   ./tools/gen-three-codes.sh --apply EFI/OC/config.plist
#                                                   # 直接写入 config.plist（自动备份）
#   ./tools/gen-three-codes.sh --rom A1B2C3D4E5F6   # 手动指定 ROM（6 字节十六进制）
#
# 说明：
#   * Serial/MLB 由 Acidanthera 官方 macserial 生成，与 SystemProductName 机型必须匹配；
#   * SystemUUID 用 uuidgen 随机生成；
#   * ROM 默认取本机 en0 的 MAC 地址（Apple 的惯例），取不到则随机；
#   * 首次运行会自动下载 OpenCore 官方 Release 并缓存 macserial（约 10 MB，仅一次）。
set -uo pipefail

MODEL="MacBookPro16,2"
COUNT=1
APPLY=""
ROM_OVERRIDE=""
REPO_OC="acidanthera/OpenCorePkg"

say()  { printf '%s\n' "$*"; }
err()  { printf '错误: %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,20p' "$0"; exit 0; }

while [ $# -gt 0 ]; do
    case "$1" in
        -m|--model)  MODEL=${2:-}; shift 2 ;;
        -n|--count)  COUNT=${2:-}; shift 2 ;;
        --rom)       ROM_OVERRIDE=${2:-}; shift 2 ;;
        --apply)     APPLY=${2:-}; shift 2 ;;
        -h|--help)   usage ;;
        *) err "未知参数：$1（-h 查看用法）" ;;
    esac
done

# ---------- macserial：优先用缓存，缺失则从 OpenCore 官方 Release 下载 ----------
CACHE="${HOME}/Library/Caches/smbios-gen"
mkdir -p "$CACHE"

get_macserial() {
    local bin="$CACHE/macserial"
    if [ -x "$bin" ]; then printf '%s\n' "$bin"; return 0; fi

    say "→ 首次运行：正在获取 macserial（从 OpenCore 官方 Release）…" >&2
    local url zip tmp
    url=$(curl -s --max-time 30 "https://api.github.com/repos/${REPO_OC}/releases/latest" \
        | /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin)
for a in d.get("assets",[]):
    if a["name"].endswith("-RELEASE.zip"):
        print(a["browser_download_url"]); break
')
    [ -n "$url" ] || err "无法获取 OpenCore 最新 Release 地址（检查网络/代理）"

    tmp=$(mktemp -d) || err "mktemp 失败"
    zip="$tmp/oc.zip"
    curl -# -L --max-time 300 -o "$zip" "$url" || err "下载 OpenCore Release 失败"
    (cd "$tmp" && unzip -q -o "$zip" "Utilities/macserial/macserial" && cp "Utilities/macserial/macserial" "$bin") \
        || err "从 Release 中提取 macserial 失败"
    chmod +x "$bin"
    rm -rf "$tmp"
    say "→ macserial 已缓存到 $bin" >&2
    printf '%s\n' "$bin"
}

MACSERIAL=$(get_macserial) || exit 1

# 校验机型是否被 macserial 支持
"$MACSERIAL" -m "$MODEL" -n 1 >/dev/null 2>&1 \
    || err "机型 $MODEL 不被 macserial 支持（用 ./macserial --help 查看可用机型列表）"

# ---------- ROM：默认取 en0 的 MAC，取不到则随机 ----------
random_rom() {
    /usr/bin/python3 -c '
import random
# 本地管理地址位（第一字节 bit1=1，多播位=0），避免与真实厂商 OUI 冲突
b = [0x02 | (random.randint(0,63) << 2), random.randint(0,255), random.randint(0,255),
     random.randint(0,255), random.randint(0,255), random.randint(0,255)]
print("".join(f"{x:02X}" for x in b))
'
}

detect_rom() {
    local mac
    mac=$(ifconfig en0 2>/dev/null | awk '/ether/{print $2}' | head -1 | tr -d ':')
    if [ ${#mac} -eq 12 ]; then printf '%s\n' "$(printf '%s' "$mac" | tr 'a-f' 'A-F')"; else random_rom; fi
}

if [ -n "$ROM_OVERRIDE" ]; then
    ROM=$(printf '%s' "$ROM_OVERRIDE" | tr -d ':' | tr 'a-f' 'A-F')
else
    ROM=$(detect_rom)
fi
[ ${#ROM} -eq 12 ] || err "ROM 必须是 12 位十六进制（6 字节），当前：$ROM"

# ---------- 生成 ----------
say ""
say "机型（SystemProductName）：$MODEL"
say "ROM：$ROM$([ -n "$ROM_OVERRIDE" ] && echo ' (手动指定)' || echo ' (en0 MAC 或随机)')"
say ""

i=0
FIRST=""
while [ $i -lt "$COUNT" ]; do
    line=$("$MACSERIAL" -m "$MODEL" -n 1) || err "macserial 生成失败"
    serial=$(printf '%s' "$line" | cut -d'|' -f1 | tr -d ' ')
    mlb=$(printf '%s' "$line" | cut -d'|' -f2 | tr -d ' ')
    uuid=$(uuidgen | tr 'a-f' 'A-F')
    [ -n "$FIRST" ] || FIRST="$serial|$mlb|$uuid"

    say "── 第 $((i+1)) 组 ─────────────────────────────"
    say "  SystemSerialNumber : $serial"
    say "  MLB                : $mlb"
    say "  SystemUUID         : $uuid"
    say "  ROM                : $ROM"
    say ""
    i=$((i+1))
done

say "提示：Serial 与 MLB 必须成对使用（同一次生成），不能混用不同组的值。"
say "      建议先在 https://checkcoverage.apple.com 查一下序列号是否已被占用。"
say ""

# ---------- 写入 config.plist ----------
if [ -n "$APPLY" ]; then
    [ -f "$APPLY" ] || err "找不到 $APPLY"
    IFS='|' read -r S M U <<< "$FIRST"
    backup="$APPLY.before-threecodes-$(date +%Y%m%d-%H%M%S)"
    cp -p "$APPLY" "$backup" || err "备份失败"
    /usr/bin/python3 - "$APPLY" "$S" "$M" "$U" "$ROM" <<'PY' || err "写入 config.plist 失败"
import plistlib, sys
path, serial, mlb, uuid, rom = sys.argv[1:6]
with open(path, "rb") as f:
    d = plistlib.load(f)
pi = d.get("PlatformInfo", {})
g = pi.get("Generic")
if g is None:
    sys.exit("config.plist 里没有 PlatformInfo > Generic")
model = g.get("SystemProductName", "?")
g["SystemSerialNumber"] = serial
g["MLB"] = mlb
g["SystemUUID"] = uuid
g["ROM"] = bytes.fromhex(rom)
with open(path, "wb") as f:
    plistlib.dump(d, f, sort_keys=False)
print("   已写入 %s" % path)
print("   机型 %s 保持不变" % model)
PY
    say "备份已保存：$backup"
    say "改完记得重启生效；若登录 iCloud 异常，用备份还原。"
fi
