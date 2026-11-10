#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen-three-codes.py — 跨平台生成 / 写入黑苹果 OpenCore 三码（Serial、MLB、UUID、ROM）

支持 Windows、macOS、Linux，仅依赖 Python 3 标准库，无需编译任何东西。

用法：
    python gen-three-codes.py                         # 生成 1 组，只打印
    python gen-three-codes.py -n 3                    # 生成 3 组备选
    python gen-three-codes.py -m iMac20,1             # 指定机型（须与 config 的 SystemProductName 一致）
    python gen-three-codes.py --rom A1B2C3D4E5F6      # 手动指定 ROM（12 位十六进制）
    python gen-three-codes.py --apply EFI/OC/config.plist
                                                      # 生成并直接写入 config.plist（自动备份）

说明：
    * Serial / MLB 由 Acidanthera 官方 macserial 生成，符合 Apple 序列号算法，
      与指定机型的 SystemProductName 匹配，可用于登录 iCloud；
    * SystemUUID 随机生成；
    * ROM 默认取本机网卡 MAC（Apple 惯例），取不到则生成一个本地管理地址段的随机值；
    * 首次运行会自动从 OpenCore 官方 Release 下载 macserial 并缓存（各平台自动选对二进制）。
"""

import argparse
import csv
import io
import os
import plistlib
import random
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import uuid
import zipfile
from pathlib import Path

OC_REPO = "acidanthera/OpenCorePkg"
API_LATEST = f"https://api.github.com/repos/{OC_REPO}/releases/latest"
DEFAULT_MODEL = "MacBookPro16,2"


# ---------------------------------------------------------------- 基础工具
def cache_dir() -> Path:
    """各平台缓存目录（与 shell 版保持一致）。"""
    if sys.platform == "darwin":
        base = Path.home() / "Library" / "Caches"
    elif os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    else:
        base = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    d = base / "smbios-gen"
    d.mkdir(parents=True, exist_ok=True)
    return d


def binary_names() -> list:
    """OpenCore Release 里 macserial 的平台文件名，按优先级排列。"""
    if os.name == "nt":
        return ["macserial.exe", "macserial32.exe"]
    if sys.platform.startswith("linux"):
        return ["macserial.linux", "macserial.linux32", "macserial"]
    return ["macserial"]


def http_get(url: str, timeout: int = 60) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "gen-three-codes/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def latest_release_zip() -> str:
    import json

    data = json.loads(http_get(API_LATEST, timeout=30).decode("utf-8"))
    for asset in data.get("assets", []):
        name = asset.get("name", "")
        if name.endswith("-RELEASE.zip"):
            return asset["browser_download_url"]
    raise RuntimeError("未在 OpenCore 最新 Release 中找到 -RELEASE.zip")


# ---------------------------------------------------------------- macserial
def ensure_macserial(verbose: bool = True) -> Path:
    """返回可执行的 macserial 路径；缺失则从 OpenCore 官方 Release 下载。"""
    cdir = cache_dir()
    for name in binary_names():
        p = cdir / name
        if p.exists() and os.access(p, os.X_OK):
            return p

    if verbose:
        print("→ 首次运行：正在获取 macserial（来自 OpenCore 官方 Release）…", file=sys.stderr)
    url = latest_release_zip()
    if verbose:
        print(f"   下载 {url.split('/')[-1]} …", file=sys.stderr)

    blob = http_get(url, timeout=300)
    target = None
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        members = [n for n in z.namelist() if n.startswith("Utilities/macserial/")]
        for want in binary_names():
            for m in members:
                if m.endswith("/" + want):
                    target = (z, m, want)
                    break
            if target:
                break
        if not target:
            raise RuntimeError(
                "Release 包里没找到 macserial 二进制。已包含的候选：\n  "
                + "\n  ".join(members)
            )
        zf, member, want = target
        out = cdir / ("macserial.exe" if os.name == "nt" else "macserial")
        with zf.open(member) as src, open(out, "wb") as dst:
            shutil.copyfileobj(src, dst)

    if os.name != "nt":
        out.chmod(0o755)
    if verbose:
        print(f"→ macserial 已缓存：{out}", file=sys.stderr)
    return out


def run_macserial(bin_path: Path, model: str, count: int = 1) -> str:
    try:
        proc = subprocess.run(
            [str(bin_path), "-m", model, "-n", str(count)],
            capture_output=True, text=True, timeout=60,
        )
    except FileNotFoundError:
        raise RuntimeError(f"无法执行 {bin_path}（权限或格式问题）")
    if proc.returncode != 0:
        raise RuntimeError(f"macserial 执行失败：{proc.stderr.strip() or proc.stdout.strip()}")
    return proc.stdout


# ---------------------------------------------------------------- ROM
def _mac_from_system() -> str:
    """尽力读取本机网卡 MAC，失败返回空串。"""
    try:
        if sys.platform == "darwin":
            for iface in ("en0", "en1"):
                out = subprocess.run(["ifconfig", iface], capture_output=True, text=True, timeout=10).stdout
                m = re.search(r"ether\s+([0-9a-fA-F:]{17})", out)
                if m:
                    return m.group(1).replace(":", "").upper()
        elif sys.platform.startswith("linux"):
            for p in sorted(Path("/sys/class/net").iterdir()):
                if p.name == "lo":
                    continue
                addr = (p / "address").read_text().strip()
                if re.fullmatch(r"([0-9a-f]{2}:){5}[0-9a-f]{2}", addr) and addr != "00:00:00:00:00:00":
                    return addr.replace(":", "").upper()
        elif os.name == "nt":
            out = subprocess.run(["getmac", "/fo", "csv", "/nh"], capture_output=True, text=True, timeout=15).stdout
            for row in csv.reader(io.StringIO(out)):
                if row:
                    cand = row[0].replace("-", "").replace(":", "").upper()
                    if re.fullmatch(r"[0-9A-F]{12}", cand) and cand != "000000000000":
                        return cand
    except Exception:
        pass

    # 兜底：uuid.getnode()（可能是随机值，但仍可用）
    node = uuid.getnode()
    if not (node >> 40) & 1:  # 非多播位
        cand = f"{node:012X}"
        if cand != "000000000000":
            return cand
    return ""


def random_rom() -> str:
    """本地管理地址段的随机 MAC（第二字节低位=1 → 首字节 bit1 置 1），避免撞真实厂商 OUI。"""
    first = 0x02 | (random.randint(0, 63) << 2)
    return f"{first:02X}" + "".join(f"{random.randint(0, 255):02X}" for _ in range(5))


def resolve_rom(explicit: str) -> str:
    if explicit:
        rom = re.sub(r"[^0-9a-fA-F]", "", explicit).upper()
        if len(rom) != 12:
            raise SystemExit(f"错误：ROM 必须是 12 位十六进制（6 字节），当前：{explicit}")
        return rom
    return _mac_from_system() or random_rom()


# ---------------------------------------------------------------- 写入 config.plist
def apply_to_config(path: Path, serial: str, mlb: str, sys_uuid: str, rom: str) -> None:
    if not path.is_file():
        raise SystemExit(f"错误：找不到 {path}")
    with open(path, "rb") as f:
        data = plistlib.load(f)          # 同时支持 XML 与二进制 plist

    generic = data.get("PlatformInfo", {}).get("Generic")
    if generic is None:
        raise SystemExit("错误：config.plist 中没有 PlatformInfo > Generic")

    model = generic.get("SystemProductName", "?")
    generic["SystemSerialNumber"] = serial
    generic["MLB"] = mlb
    generic["SystemUUID"] = sys_uuid
    generic["ROM"] = bytes.fromhex(rom)

    backup = path.with_name(path.name + ".before-threecodes-" + __import__("datetime").datetime.now().strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(path, backup)

    with open(path, "wb") as f:
        plistlib.dump(data, f, sort_keys=False)

    print(f"   已写入 {path}")
    print(f"   机型 {model} 保持不变")
    print(f"   备份：{backup}")


# ---------------------------------------------------------------- 主流程
def main() -> int:
    ap = argparse.ArgumentParser(
        description="生成 / 写入黑苹果 OpenCore 三码（Serial、MLB、UUID、ROM），跨平台。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("-m", "--model", default=DEFAULT_MODEL,
                    help=f"机型，须与 config 的 SystemProductName 一致（默认 {DEFAULT_MODEL}）")
    ap.add_argument("-n", "--count", type=int, default=1, help="生成几组备选（默认 1）")
    ap.add_argument("--rom", default="", help="手动指定 ROM（12 位十六进制，如 A1B2C3D4E5F6）")
    ap.add_argument("--apply", default="", metavar="CONFIG",
                    help="生成后直接写入指定的 config.plist（自动备份）")
    args = ap.parse_args()

    if args.count < 1:
        raise SystemExit("错误：-n 至少为 1")

    rom = resolve_rom(args.rom)
    bin_path = ensure_macserial()

    # 校验机型
    try:
        run_macserial(bin_path, args.model, 1)
    except RuntimeError:
        raise SystemExit(
            f"错误：机型 {args.model} 不被 macserial 支持。\n"
            f"      可用机型可运行：{bin_path} --help"
        )

    print()
    print(f"机型（SystemProductName）：{args.model}")
    print(f"ROM：{rom}{' (手动指定)' if args.rom else ''}")
    print()

    first = None
    for i in range(args.count):
        out = run_macserial(bin_path, args.model, 1)
        line = next((l for l in out.splitlines() if "|" in l), "")
        if not line:
            raise SystemExit(f"错误：无法解析 macserial 输出：{out!r}")
        serial, mlb = [x.strip() for x in line.split("|")[:2]]
        su = str(uuid.uuid4()).upper()
        if first is None:
            first = (serial, mlb, su)

        print(f"── 第 {i + 1} 组 ─────────────────────────────")
        print(f"  SystemSerialNumber : {serial}")
        print(f"  MLB                : {mlb}")
        print(f"  SystemUUID         : {su}")
        print(f"  ROM                : {rom}")
        print()

    print("提示：Serial 与 MLB 必须成对使用（同一次生成），不能混用不同组的值。")
    print("      建议先在 https://checkcoverage.apple.com 查一下序列号是否已被占用。")
    print()

    if args.apply:
        apply_to_config(Path(args.apply).expanduser(), *first, rom)
        print("改完重启生效；若 iCloud 异常，用上面的备份还原。")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n已取消", file=sys.stderr)
        sys.exit(130)
    except Exception as exc:  # 网络/磁盘等运行时问题，给出人话提示
        print(f"错误：{exc}", file=sys.stderr)
        sys.exit(1)
