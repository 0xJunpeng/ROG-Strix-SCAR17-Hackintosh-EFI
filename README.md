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

## 使用说明

1. ⚠️ **config.plist 中的 SMBIOS 序列号 / MLB / UUID / ROM 已脱敏**（替换为 `REMOVED-FOR-PRIVACY`）。使用前请用 [GenSMBIOS](https://github.com/corpnewt/GenSMBIOS) 生成自己的序列号填入 `PlatformInfo > Generic`。
2. EFI 放到分区（ESP）的 `EFI/OC/` 目录。
3. 独显传感器需要本仓库提到的 SMCNvidiaGPU.kext（已包含在 Kexts 里）。

## 已知限制

- 笔记本风扇由 EC 控制，显卡不上报转速（菜单栏程序自动回退读系统 SMC 风扇）
- NVIDIA 独显无法读取电压和 VBIOS 版本（驱动层限制）

## 致谢

- [OpenCorePkg](https://github.com/acidanthera/OpenCorePkg)、[Lilu](https://github.com/acidanthera/Lilu)、[VirtualSMC](https://github.com/acidanthera/VirtualSMC)
- [nullmoth/nvidia-macos-driver](https://github.com/nullmoth/nvidia-macos-driver)、[zzzyy678/SMCNvidiaGPU](https://github.com/zzzyy678/SMCNvidiaGPU)
- 黑苹果社区所有人的踩坑记录
