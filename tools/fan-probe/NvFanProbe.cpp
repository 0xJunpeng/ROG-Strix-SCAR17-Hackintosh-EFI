// NvFanProbe — 只读探针 kext（不发布任何 SMC 键，读完立即返回 false 不占用设备）
//
// 目的：验证 DSDT 中 OperationRegion (IT55, SystemMemory, 0xFE700600, 0x100) 这段
//       eSPI/EC RAM 内存映射在 macOS 下是否可读，并找出风扇转速字段的实际值。
//
// DSDT 中的字段（来自反编译结果）：
//   FA1L @ IT55+0x02, FA1H @ IT55+0x03   -> 风扇1 转速（WMI 0x00110013 = (FA1H<<8|FA1L)/100）
//   FA2L @ IT55+0x24, FA2H @ IT55+0x25   -> 风扇2 转速（WMI 0x00110014）
//
// 结果同时通过 IOLog 和 provider 属性 "nvfanprobe" 输出，用 ioreg 即可查看。

#include <IOKit/IOService.h>
#include <IOKit/IOMemoryDescriptor.h>
#include <IOKit/IOLib.h>

#define NVFAN_BASE 0xFE700600ULL
#define NVFAN_LEN  0x100

class NvFanProbe : public IOService {
    OSDeclareDefaultStructors(NvFanProbe)
public:
    bool start(IOService *provider) override;
};

OSDefineMetaClassAndStructors(NvFanProbe, IOService)

bool NvFanProbe::start(IOService *provider)
{
    if (!IOService::start(provider)) {
        return false;
    }

    OSPtr<IOMemoryDescriptor> md =
        IOMemoryDescriptor::withPhysicalAddress((IOPhysicalAddress)NVFAN_BASE,
                                               NVFAN_LEN, kIODirectionIn);
    if (!md) {
        IOLog("NvFanProbe: withPhysicalAddress(0x%llx) failed\n", NVFAN_BASE);
        return false;
    }

    OSPtr<IOMemoryMap> map = md->map(kIOMapAnywhere | kIOMapReadOnly);
    if (!map) {
        IOLog("NvFanProbe: map(0x%llx) failed\n", NVFAN_BASE);
        return false;
    }

    volatile UInt8 *p = (volatile UInt8 *)map->getVirtualAddress();
    if (!p) {
        IOLog("NvFanProbe: getVirtualAddress failed\n");
        return false;
    }

    UInt8 buf[NVFAN_LEN];
    for (int i = 0; i < NVFAN_LEN; i++) {
        buf[i] = p[i];
    }

    // 1) 原始 hex dump（0x00~0x5F，足够覆盖 FA1/FA2 与 RCPU）
    char hex[512];
    int  n = 0;
    for (int i = 0; i < 0x60 && n < (int)sizeof(hex) - 8; i++) {
        n += snprintf(hex + n, sizeof(hex) - n, "%02X%s", buf[i], ((i & 15) == 15) ? " " : "");
        if ((i & 15) == 15) hex[n++] = '\n';
    }
    hex[n] = '\0';
    IOLog("NvFanProbe: IT55 dump @0xFE700600:\n%s", hex);

    // 2) 关键字段解码
    UInt16 fa1 = (UInt16)(buf[0x02] | (buf[0x03] << 8));
    UInt16 fa2 = (UInt16)(buf[0x24] | (buf[0x25] << 8));
    UInt16 fa2b = (UInt16)(buf[0x25] | (buf[0x26] << 8)); // 偏移猜错时的备选
    IOLog("NvFanProbe: FA1(+0x02)=0x%04X (%u)  FA2(+0x24)=0x%04X (%u)  FA2alt(+0x25)=0x%04X (%u)\n",
          fa1, fa1, fa2, fa2, fa2b, fa2b);

    // 3) 扫一遍前 0x60 字节的 16-bit 小端组合，方便找出真实转速（2000~7000 之间最可疑）
    char scan[512];
    n = 0;
    for (int i = 0; i + 1 < 0x60 && n < (int)sizeof(scan) - 32; i++) {
        UInt16 v = (UInt16)(buf[i] | (buf[i + 1] << 8));
        if (v >= 500 && v <= 9000) {
            n += snprintf(scan + n, sizeof(scan) - n, "+0x%02X=%u ", i, v);
        }
    }
    scan[n] = '\0';
    IOLog("NvFanProbe: 疑似转速候选: %s\n", n ? scan : "(none)");

    // 4) 结果挂到 provider 属性上，方便用 ioreg 直接读，不必翻系统日志
    char summary[256];
    snprintf(summary, sizeof(summary),
             "FA1=%u FA2=0x%04X(%u) FA2alt=%u cand=%s", fa1, fa2, fa2, fa2b, n ? scan : "none");
    if (provider) {
        provider->setProperty("nvfanprobe", summary);
    }

    // 不占用设备：读完即退出（kext 仍驻留，可用 kmutil unload 卸载）
    return false;
}

// kext 必须提供 _kmod_info（否则 kmutil 报 "kexts must have a _kmod_info symbol"）
#include <mach/kmod.h>
extern "C" kern_return_t _start(kmod_info_t *ki, void *d);
extern "C" kern_return_t _stop(kmod_info_t *ki, void *d);
extern "C" { KMOD_EXPLICIT_DECL(org.hackintosh.NvFanProbe, "0.1", _start, _stop) }
extern "C" kern_return_t _start(kmod_info_t *ki, void *d) { return KERN_SUCCESS; }
extern "C" kern_return_t _stop(kmod_info_t *ki, void *d) { return KERN_SUCCESS; }
