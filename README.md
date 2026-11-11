# ROG 枪神 6 Plus（ROG Strix SCAR 17）Hackintosh EFI

华硕 ROG 枪神 6 Plus（2022 款，ROG Strix SCAR 17）的黑苹果 OpenCore 引导配置，可日常使用。

## 硬件配置

| 部件 | 型号 | 状态 |
|---|---|---|
| CPU | Intel Core i9-12900H（Alder Lake） | ✅ 完整支持 |
| GPU | NVIDIA GeForce RTX 3060 Laptop GPU（GA106） | ✅ Metal 4，含传感器监控 |
| 核显 | Intel Iris Xe（UHD Graphics） | ✅ 驱动显示输出 |
| 无线网卡 | Intel Wi-Fi 6（AirportItlwm + itlwm 备用） | ✅ |
| 蓝牙 | Intel（IntelBluetoothFirmware + BlueToolFixup） | ✅ |
| 触控板 | I2C HID（VoodooI2C + VoodooI2CHID） | ✅ |

## 软件版本

- **macOS 26.7.2**（Tahoe）
- **OpenCore** DBG-109
- **NVIDIA 驱动**：[NullMoth NVRM 2.8.1](https://github.com/nullmoth/nvidia-macos-driver)（NVIDIA 620.70.06）
- **SMCNvidiaGPU 1.9.2**：[zzzyy678/SMCNvidiaGPU](https://github.com/zzzyy678/SMCNvidiaGPU) —— 把 GPU 温度、功耗、频率等暴露给 iStat Menus / 菜单栏监控

## 主要 kext

- Lilu、VirtualSMC 全家桶（SMCProcessor / SMCSuperIO / SMCBatteryManager / SMCLightSensor）
- **SMCNvidiaGPU**（NVIDIA GPU 传感器，VirtualSMC 插件）
- AirportItlwm（Wi-Fi）、IntelBluetoothFirmware + BlueToolFixup + IntelBTPatcher（蓝牙）
- VoodooI2C / VoodooI2CHID（触控板）、VoodooPS2Controller（键盘）
- WhateverXe（核显）、NVMeFix、USBToolBox + UTBDefault
- CpuTscSync + CpuTopologyRebuild（Alder Lake 混合架构核心调度）
- RestrictEvents、AMFIPass（NVIDIA 驱动所需）
- **NvFanProbe 0.3**（自研，见下文）

## 🌡️ 自研传感器驱动：NvFanProbe

macOS Tahoe 26 起，`AppleSMC` 的用户态私有接口对第三方进程一律返回 `kIOReturnBadArgument`，且 `SMCProcessor` 在本机不会实例化 —— CPU 温度在用户态彻底拿不到。

**NvFanProbe.kext**（`EFI/OC/Kexts/`，源码在 `tools/NvFanProbe/`）在内核层直接读 MSR：

- `IA32_TEMPERATURE_TARGET`（0x1A2）取 TjMax
- `IA32_PACKAGE_THERM_STATUS`（0x1B1，失败时退到核心级 0x19C）计算封装温度
- 每秒刷新，以 IORegistry 属性 `CPUTempC` 发布，用户态无需 root 读取

配套控制台 App（菜单栏监控 + 驱动中心，驱动中心里可离线一键安装本 kext）：
[0xJunpeng/ROG-Control-Center](https://github.com/0xJunpeng/ROG-Control-Center)

## 关键 boot-args

```
debug=0x100 keepsyms=1 -allow3d -disablegfxfirmware -igfxdvmt -vi2c-force-polling
ctrsmt=full -ibtcompatbeta revpatch=sbvmm nvfb=1 nvaccel=1 nvfbheads=4
-nvkmsnosmooth amfi_get_out_of_my_way=0x1 amfi=0x80 ipc_control_port_options=0
nvrmacpibl=1
```

## ⚠️ 三码配置（使用前必读）

本仓库的 `config.plist` 中 **SMBIOS 三码已置为占位符**，直接使用会导致 iCloud / iMessage / App Store 无法登录（严重时被 Apple 锁定账号）。请务必替换为你自己的三码：

| 字段（`PlatformInfo > Generic`） | 当前值 | 说明 |
|---|---|---|
| `SystemSerialNumber` | `REPLACE-ME-SERIAL` | 机器序列号（12 位） |
| `MLB` | `REPLACE-ME-MLB` | 主板序列号（17 位） |
| `SystemUUID` | `00000000-0000-0000-0000-000000000000` | 系统 UUID（36 位，带连字符） |
| `ROM` | `112233445566` | 网卡 MAC 地址（6 字节） |
| `SystemProductName` | `MacBookPro16,2` | **保持不动**（与本 EFI 的 CPU 电源管理、核显配置绑定） |

### 方法一：Python 脚本（跨平台，推荐）

`tools/gen-three-codes.py` —— **Windows / macOS / Linux 通用**，只需 Python 3（系统自带或从 [python.org](https://www.python.org/downloads/) 安装），不依赖任何第三方库，也不用编译。脚本调用 Acidanthera 官方 `macserial` 生成合法的 Serial / MLB 配对，并可直接写入 config.plist。

```bash
# Windows 用 python，macOS / Linux 用 python3

# 只生成看结果（不修改任何文件）
python tools/gen-three-codes.py

# 生成 3 组备选
python tools/gen-three-codes.py -n 3

# 生成并直接写入 config.plist（自动备份原文件）
python tools/gen-three-codes.py --apply EFI/OC/config.plist

# 指定机型 / 手动指定 ROM
python tools/gen-three-codes.py -m MacBookPro16,2 --rom A1B2C3D4E5F6
```

参数说明：

| 参数 | 作用 |
|---|---|
| `-m, --model` | 机型，必须与 config.plist 的 `SystemProductName` 一致（默认 `MacBookPro16,2`） |
| `-n, --count` | 生成几组备选（默认 1） |
| `--rom` | 手动指定 ROM（12 位十六进制，可带 `:`） |
| `--apply CONFIG` | 生成后直接写入指定 config.plist，只改三码、不动机型，写前自动备份 |

首次运行会自动从 OpenCore 官方 Release 下载对应平台的 `macserial` 并缓存（macOS：`~/Library/Caches/smbios-gen/`；Windows：`%LOCALAPPDATA%\smbios-gen\`；Linux：`~/.cache/smbios-gen/`），约 10 MB，只下一次。

### 方法二：Shell 脚本（macOS / Linux）

`tools/gen-three-codes.sh` —— 功能与 Python 版相同，适合不想装 Python 的类 Unix 环境（需要 curl、unzip）：

```bash
./tools/gen-three-codes.sh                                   # 生成 1 组
./tools/gen-three-codes.sh -n 3                              # 生成 3 组备选
./tools/gen-three-codes.sh --apply EFI/OC/config.plist       # 生成并写入
./tools/gen-three-codes.sh -m MacBookPro16,2 --rom A1B2C3D4E5F6
```

### 方法三：GenSMBIOS（手动）

```bash
git clone https://github.com/corpnewt/GenSMBIOS
cd GenSMBIOS && chmod +x GenSMBIOS.command && ./GenSMBIOS.command
```

1. 选 `3. Generate SMBIOS`（部分版本是 `2`）
2. 机型输入 **`MacBookPro16,2`**（必须与 `SystemProductName` 一致）
3. 输出形如 `MacBookPro16,2 | C02XXXXXXXXXX | C02XXXXXXXXXXXXXXX | ...`，依次对应 **Serial | MLB**
4. `SystemUUID` 用 `uuidgen` 生成即可：终端执行 `uuidgen`
5. `ROM` 取本机网卡 MAC 去掉冒号（终端 `ifconfig en0 | grep ether`），或随意填 6 字节十六进制

### 方法四：OCAT（图形化）

OpenCore Auxiliary Tools → 打开 `config.plist` → 左侧 `PlatformInfo` → 点 **Generate** 按钮（机型选 MacBookPro16,2）→ 自动填充 Serial / MLB / UUID / ROM → 保存。

### 替换后的检查

- 三码必须**成对使用**（Serial 与 MLB 要来自同一次生成，不能混用）
- 改完务必**只保留你自己的三码**，不要提交回本仓库或公开分享
- 首次登录 iCloud 前先在「系统设置」里确认序列号已生效（`系统报告 → 硬件`）


## 使用说明

1. 按上一节替换三码（必做）。
2. 把 `EFI` 文件夹放到 ESP 分区的根目录（`EFI/OC/`）。
3. 本 EFI 内的 `SMCNvidiaGPU.kext` 依赖 [NullMoth NVIDIA 驱动](https://github.com/nullmoth/nvidia-macos-driver) 2.8.1，驱动版本不同需重新生成绑定表。


## 风扇转速（EC 探针）

这台机器在 macOS 下**出厂就没有风扇数据源**：NVIDIA 驱动报 `kern.nvgpufancount = 0`（笔记本显卡不上报风扇），
VirtualSMC 的 `FNum = 0`（系统 SMC 里没有风扇键），DSDT 里也没有标准的 `Device (FAN0)` / `_FST`。
所以 iStat Menus 和菜单栏程序读到的风扇值都是 0。

不过数据其实在 EC RAM 里，可以直接读。`tools/fan-probe/` 是一个只读探针，用来验证并读取它：

```bash
cd tools/fan-probe
./build.sh                  # 需要 Command Line Tools
sudo ./inject-oc.sh         # 注入 OpenCore（改 config.plist，自动备份）
# 重启后
./check.sh                  # 读结果；回滚用 sudo ./check.sh --off
```

实测输出：

```
"nvfanprobe" = "FA1=3000 FA2=0x0BF4(3060) ..."     → 风扇1 3000 RPM，风扇2 3060 RPM
```

数据源（来自反编译的 DSDT）：

```asl
OperationRegion (IT55, SystemMemory, 0xFE700600, 0x100)
    FA1L @ +0x02, FA1H @ +0x03     // 风扇 1
    FA2L @ +0x24, FA2H @ +0x25     // 风扇 2
```

细节、原理和适配其他机型的方法见 [`tools/fan-probe/README.md`](tools/fan-probe/README.md)。
探针本身**只读不写**，也不注册 SMC 键——要让转速出现在 iStat Menus 里，还需要再写一个 VirtualSMC
插件把它发布成 `FNum` / `F0Ac`。

## 已知限制

- 风扇转速需要上面的 EC 探针才能读到；不装探针时 iStat Menus 显示 0（不是故障）
- `SMCNvidiaGPU.kext` 的绑定表与 NVIDIA 驱动版本严格对应。本仓库的 kext 针对 **NVRM 2.8.1** 编译；驱动升级后
  `sysctl kern.nvgpustate` 会显示 `matches none of the N known builds`，所有读数变 0。处理方式：用
  `kext/nvrm_bindings.py` 按新驱动重新生成绑定表再 `kext/build.sh` 重编（作者提供的标准流程），或回退驱动版本
- NVIDIA 独显无法读取电压和 VBIOS 版本（驱动层限制）

## 致谢

- [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg)、[Lilu](https://github.com/acidanthera/Lilu)、[VirtualSMC](https://github.com/acidanthera/VirtualSMC)
- [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver)、[zzzyy678/SMCNvidiaGPU](https://github.com/zzzyy678/SMCNvidiaGPU)
- 黑苹果社区所有人的踩坑记录
