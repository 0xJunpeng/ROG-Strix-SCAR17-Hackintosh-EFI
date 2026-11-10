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

### 方法一：GenSMBIOS（推荐）

```bash
git clone https://github.com/corpnewt/GenSMBIOS
cd GenSMBIOS && chmod +x GenSMBIOS.command && ./GenSMBIOS.command
```

1. 选 `3. Generate SMBIOS`（部分版本是 `2`）
2. 机型输入 **`MacBookPro16,2`**（必须与 `SystemProductName` 一致）
3. 输出形如 `MacBookPro16,2 | C02XXXXXXXXXX | C02XXXXXXXXXXXXXXX | ...`，依次对应 **Serial | MLB**
4. `SystemUUID` 用 `uuidgen` 生成即可：终端执行 `uuidgen`
5. `ROM` 取本机网卡 MAC 去掉冒号（终端 `ifconfig en0 | grep ether`），或随意填 6 字节十六进制

### 方法二：OCAT（图形化）

OpenCore Auxiliary Tools → 打开 `config.plist` → 左侧 `PlatformInfo` → 点 **Generate** 按钮（机型选 MacBookPro16,2）→ 自动填充 Serial / MLB / UUID / ROM → 保存。

### 替换后的检查

- 三码必须**成对使用**（Serial 与 MLB 要来自同一次生成，不能混用）
- 改完务必**只保留你自己的三码**，不要提交回本仓库或公开分享
- 首次登录 iCloud 前先在「系统设置」里确认序列号已生效（`系统报告 → 硬件`）


## 使用说明

1. 按上一节替换三码（必做）。
2. 把 `EFI` 文件夹放到 ESP 分区的根目录（`EFI/OC/`）。
3. 本 EFI 内的 `SMCNvidiaGPU.kext` 依赖 [NullMoth NVIDIA 驱动](https://github.com/nullmoth/nvidia-macos-driver) 2.8.1，驱动版本不同需重新生成绑定表。


## 已知限制

- 笔记本风扇由 EC 控制，显卡不上报转速（菜单栏程序自动回退读系统 SMC 风扇）
- NVIDIA 独显无法读取电压和 VBIOS 版本（驱动层限制）

## 致谢

- [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg)、[Lilu](https://github.com/acidanthera/Lilu)、[VirtualSMC](https://github.com/acidanthera/VirtualSMC)
- [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver)、[zzzyy678/SMCNvidiaGPU](https://github.com/zzzyy678/SMCNvidiaGPU)
- 黑苹果社区所有人的踩坑记录
