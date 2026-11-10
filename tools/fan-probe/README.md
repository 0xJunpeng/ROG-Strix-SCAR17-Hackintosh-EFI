# NvFanProbe — 华硕笔记本 EC 风扇转速只读探针

一个**只读**的内核扩展，用来验证本机 ACPI 里的 EC RAM 内存窗口能否在 macOS 下直接读取，
并把风扇转速字段的值打印出来。

> 为什么需要它：这台机器（ROG Strix SCAR 17 / 枪神 6 Plus，主板 G733ZM）在 macOS 下
> **没有任何风扇数据源**——`SMCNvidiaGPU` 报告 `kern.nvgpufancount = 0`（NVIDIA 驱动不上报
> 笔记本风扇），VirtualSMC 的 `FNum = 0`（系统 SMC 里根本没有风扇键）。所以 iStat Menus
> 和菜单栏程序都读不到转速。

## 结论：EC 内存窗口是可读的，转速是真的

在本机实测（RTX 3060 Laptop + macOS 26.7.2）读到：

```
"nvfanprobe" = "FA1=3000 FA2=0x0BF4(3060) FA2alt=267 cand=+0x02=3000 +0x24=3060 ..."
```

- **风扇 1 = 3000 RPM**
- **风扇 2 = 3060 RPM**

两个风扇都拿到了真实值（不是 0，也不是 0xFF），说明 `0xFE700600` 这段
`SystemMemory` 映射在 macOS 下**直接可读**——不需要 AppleACPIEC、不需要 EC 端口 bit-bang、
不需要改 ACPI、不需要动 boot-args。

## 数据源是怎么找到的

用 OpenCore 的 `Misc > Debug > SysReport = true` 让引导器把 ACPI 表 dump 到 ESP 根目录，
再用 ACPICA 的 `iasl` 反编译 `DSDT.aml`，在 DSDT 里找到：

```asl
OperationRegion (IT55, SystemMemory, 0xFE700600, 0x100)
    FA1L @ +0x02,  FA1H @ +0x03     // 风扇 1 转速（低字节 / 高字节）
    FA2L @ +0x24,  FA2H @ +0x25     // 风扇 2 转速
```

与之对应的是 ASUS WMI 方法 `0x00110013` / `0x00110014`：

```asl
Local0 = FA1L;  Local1 = FA1H;  Local1 *= 0x100;  Local0 += Local1
Divide (Local0, 0x64, Local1, Local0)       // 除以 100
Return (0x00010000 + Local0)                // 返回值单位 = 100 RPM
```

也就是原始寄存器值就是 RPM，`/100` 只是 WMI 返回格式的打包。探针读到的 3000 / 3060
与 Windows 下 Armoury Crate 显示的值一致。

> 注意：这台机器的 DSDT/SSDT 里**没有** `Device (FAN0)` / `_FST` 之类的标准 ACPI 风扇设备，
> 也没有 EC 字段区的风扇寄存器——数据只在这段 `SystemMemory` 映射里。所以按常规
> "给 ACPI 风扇写驱动" 的思路是走不通的。

## 用法

```bash
# 1. 构建（只要 Command Line Tools，不需要 Xcode / KDK）
./build.sh

# 2a. 运行时加载（macOS 11+ 通常要求重启，此路一般走不通，但值得先试）
sudo ./run-probe.sh

# 2b. 走 OpenCore 注入（推荐：重启一次即生效，回滚只需禁用一条配置）
sudo ./inject-oc.sh              # 自动探测已挂载的 ESP
sudo ./inject-oc.sh /Volumes/SYSTEM   # 或手动指定

# 3. 重启后读结果
./check.sh

# 回滚
sudo ./check.sh --off
```

`check.sh` 输出示例：

```
== 1. kext 是否已加载
   21  0  ...  org.hackintosh.NvFanProbe (0.1) ...
== 2. ioreg 中的探针结果
"nvfanprobe" = "FA1=3000 FA2=0x0BF4(3060) ..."
== 3. 内核日志
NvFanProbe: IT55 dump @0xFE700600:
00 0B B8 0B ...
NvFanProbe: FA1(+0x02)=0x0BB8 (3000)  FA2(+0x24)=0x0BF4 (3060)  FA2alt(+0x25)=0x010B (267)
```

## 它做什么 / 不做什么

**做**：映射 `0xFE700600` 共 256 字节 → 读出来 → 解 `FA1`/`FA2` → 扫一遍 16-bit 小端值找
500~9000 之间的可疑转速 → 结果同时写到 `IOLog` 和 provider 属性 `nvfanprobe`（方便 `ioreg` 直接看）
→ `start()` 返回 `false` **不占用设备**。

**不做**：不写内存、不碰风扇控制、不注册任何 SMC 键、不改 `config.plist` 以外的任何东西。

所以即使装上，**iStat Menus 里依然看不到风扇**——要让转速出现在 SMC 里，还需要再写一个
VirtualSMC 插件把读到的值发布成 `FNum` / `F0Ac` / `F0Mn` / `F0Mx`。这个探针只负责
回答"数据源到底有没有货"，而答案是：**有**。

## 风险

| 项 | 说明 |
|---|---|
| 读未映射的 MMIO | 通常返回 `0xFFFFFFFF`，不会崩；但这个地址在 macOS 下**确实**映射成功并返回了合理数值 |
| 最坏情况 | 内核 panic（可重启恢复，探针不写任何持久化数据） |
| 无法开机 | 在另一个系统（如 Windows）里把 `config.plist` 中 `NvFanProbe.kext` 那条的 `Enabled` 改成 `false`，或用 `config.plist.before-fanprobe-*` 备份覆盖回去 |

## 适用性

只在 **ROG Strix SCAR 17 / 枪神 6 Plus（G733ZM）** 上验证过。其他机型：

- 先反编译自己的 DSDT，确认存在 `OperationRegion (IT55, SystemMemory, 0xFE700600, ...)`
  以及 `FA1L` / `FA2L` 字段——不同机型的基址和偏移都不一样
- 改 `NvFanProbe.cpp` 顶部的 `NVFAN_BASE` / `NVFAN_LEN` 与字段偏移，再 `./build.sh`

## 许可

MIT，与主仓库一致。
