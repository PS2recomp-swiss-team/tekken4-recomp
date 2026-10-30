// Tekken 4 (SCES-50878, PAL v2.00): fight-camera live dump. tools\stage_generated.cmd copies this in.
//
// TEKKEN4_CAMERA_LOG=<lines>: every 60th call (and the first 3) of the per-frame eye / look-at, plus the
// VU1 upload, prints the same fields tools\pcsx2_camera_probe.ps1 reads over PINE.
//
// Chain (the p+0xF08 read is the pointer slot, not the camera): p = u32[0x2AA0D0|0x2AA0D4],
// cam = u32[p+0xF08] (eye a1, look-at a0), dir = u32[cam+0x198] (eye a0, 0x90 bytes: FUN_0018e1e0
// 0x18fca8 steps s2 by 0x90), target = p+0x660 (eye a3 / look-at a1, one lqc2 = 16 bytes).
// VU1 view matrix: FUN_00244fc8 (called from the main loop FUN_001969f8) copies 0x40 bytes from
// slot = 0x01CE2270 + u32[cam+0x174] * 0xC0 into the VIF packet (0x2454c4).
// Look-at inputs are the three vec4s at 0x2D27D0 (only +4 of each is stored by FUN_00193800).
//
// [camwatch]: from eye call 1 through eye call 15, every sq/sqc2-to-+0x30/+0x70 function (plus the
// camera callers) is bracketed around camera 0's xform translation (*(dir+0x80)+0x70). The innermost
// function whose call changes that quad logs before/after. Originals are restored at eye call 16.
#include "game_overrides.h"
#include "ps2_log.h"
#include "ps2_runtime.h"
#include <ps2_recompiled_functions.h>

#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <sstream>

namespace tekken4_camera
{
    constexpr uint32_t kRamMask = 0x01FFFFFFu;
    constexpr uint32_t kSlotBase = 0x01CE2270u;
    constexpr uint32_t kBasis = 0x002D27D0u;
    constexpr uint32_t kWatchUntilEye = 16u;
    std::atomic<int> g_linesLeft{0};
    std::atomic<uint32_t> g_eyeCalls{0}, g_lookCalls{0}, g_upCalls{0}, g_rootCalls{0};
    std::atomic<int> g_upLeft{40};

    using GuestFn = void (*)(uint8_t *, R5900Context *, PS2Runtime *);

    struct WatchEntry
    {
        uint32_t addr;
        GuestFn fn;
    };

    // Filled by logs/grok/gen_cam_watch.py from logs/grok/cam_writers.txt. 0x18e1e0 / 0x193800 / 0x244fc8
    // stay on the loggers below; those three call bracket() themselves.
    static const WatchEntry kWatch[] = {
        {0x00180498u, FUN_00180498_0x180498},
        {0x001808E8u, FUN_001808e8_0x1808e8},
        {0x00180EF0u, FUN_00180ef0_0x180ef0},
        {0x00181108u, FUN_00181108_0x181108},
        {0x001896E0u, FUN_001896e0_0x1896e0},
        {0x0018D528u, FUN_0018d528_0x18d528},
        {0x0018DD88u, FUN_0018dd88_0x18dd88},
        {0x0018DE68u, FUN_0018de68_0x18de68},
        {0x0018FD30u, FUN_0018fd30_0x18fd30},
        {0x00193AB8u, FUN_00193ab8_0x193ab8},
        {0x001B9330u, FUN_001b9330_0x1b9330},
        {0x001D5B48u, FUN_001d5b48_0x1d5b48},
        {0x001D5BC8u, FUN_001d5bc8_0x1d5bc8},
        {0x001D5C30u, FUN_001d5c30_0x1d5c30},
        {0x001D5C78u, FUN_001d5c78_0x1d5c78},
        {0x001D5CE0u, FUN_001d5ce0_0x1d5ce0},
        {0x001D5D18u, FUN_001d5d18_0x1d5d18},
        {0x001D5D60u, FUN_001d5d60_0x1d5d60},
        {0x001D5DA8u, FUN_001d5da8_0x1d5da8},
        {0x001D5E90u, FUN_001d5e90_0x1d5e90},
        {0x001D5F78u, FUN_001d5f78_0x1d5f78},
        {0x001D5FE8u, FUN_001d5fe8_0x1d5fe8},
        {0x001D6058u, FUN_001d6058_0x1d6058},
        {0x001D6178u, FUN_001d6178_0x1d6178},
        {0x001D6268u, FUN_001d6268_0x1d6268},
        {0x001D62C8u, FUN_001d62c8_0x1d62c8},
        {0x001D63A8u, FUN_001d63a8_0x1d63a8},
        {0x001D6530u, FUN_001d6530_0x1d6530},
        {0x001D6718u, FUN_001d6718_0x1d6718},
        {0x001D6818u, FUN_001d6818_0x1d6818},
        {0x001D6918u, FUN_001d6918_0x1d6918},
        {0x001D69F0u, FUN_001d69f0_0x1d69f0},
        {0x001D6AC8u, FUN_001d6ac8_0x1d6ac8},
        {0x001D6B88u, FUN_001d6b88_0x1d6b88},
        {0x001D6C48u, FUN_001d6c48_0x1d6c48},
        {0x001D6CA0u, FUN_001d6ca0_0x1d6ca0},
        {0x001D6CF8u, FUN_001d6cf8_0x1d6cf8},
        {0x001D6D50u, FUN_001d6d50_0x1d6d50},
        {0x001D6D90u, FUN_001d6d90_0x1d6d90},
        {0x001D6DD0u, FUN_001d6dd0_0x1d6dd0},
        {0x001D6E50u, FUN_001d6e50_0x1d6e50},
        {0x001D6F98u, FUN_001d6f98_0x1d6f98},
        {0x001D75B8u, FUN_001d75b8_0x1d75b8},
        {0x001D7848u, FUN_001d7848_0x1d7848},
        {0x001D7AF8u, FUN_001d7af8_0x1d7af8},
        {0x001D7DF8u, FUN_001d7df8_0x1d7df8},
        {0x001D8128u, FUN_001d8128_0x1d8128},
        {0x001D8448u, FUN_001d8448_0x1d8448},
        {0x001D8B00u, FUN_001d8b00_0x1d8b00},
        {0x001D8EB0u, FUN_001d8eb0_0x1d8eb0},
        {0x001D9260u, FUN_001d9260_0x1d9260},
        {0x001D9638u, FUN_001d9638_0x1d9638},
        {0x001D98F0u, FUN_001d98f0_0x1d98f0},
        {0x001FFD28u, FUN_001ffd28_0x1ffd28},
        {0x00200B88u, FUN_00200b88_0x200b88},
        {0x00208CA8u, FUN_00208ca8_0x208ca8},
        {0x00209588u, FUN_00209588_0x209588},
        {0x002099C8u, FUN_002099c8_0x2099c8},
        {0x0020AA78u, FUN_0020aa78_0x20aa78},
        {0x0020E950u, FUN_0020e950_0x20e950},
        {0x0020ECD0u, FUN_0020ecd0_0x20ecd0},
        {0x00219028u, FUN_00219028_0x219028},
        {0x00219398u, FUN_00219398_0x219398},
        {0x0021A198u, FUN_0021a198_0x21a198},
        {0x0021AAD0u, FUN_0021aad0_0x21aad0},
        {0x0021B760u, FUN_0021b760_0x21b760},
        {0x0021BDF8u, FUN_0021bdf8_0x21bdf8},
        {0x0021C938u, FUN_0021c938_0x21c938},
        {0x0021DE48u, FUN_0021de48_0x21de48},
        {0x002201A0u, FUN_002201a0_0x2201a0},
        {0x0022D438u, FUN_0022d438_0x22d438},
        {0x00235E68u, FUN_00235e68_0x235e68},
        {0x00235F00u, FUN_00235f00_0x235f00},
        {0x00235F90u, FUN_00235f90_0x235f90},
        {0x00236100u, FUN_00236100_0x236100},
        {0x00236130u, FUN_00236130_0x236130},
        {0x00236160u, FUN_00236160_0x236160},
        {0x00236190u, FUN_00236190_0x236190},
        {0x00236998u, FUN_00236998_0x236998},
        {0x002386C8u, FUN_002386c8_0x2386c8},
        {0x00238D28u, FUN_00238d28_0x238d28},
        {0x00239690u, FUN_00239690_0x239690},
        {0x00239EA0u, FUN_00239ea0_0x239ea0},
        {0x0023B0F8u, FUN_0023b0f8_0x23b0f8},
        {0x0023C3F0u, FUN_0023c3f0_0x23c3f0},
        {0x0023CCA8u, FUN_0023cca8_0x23cca8},
        {0x0023E1D8u, FUN_0023e1d8_0x23e1d8},
        {0x0023ED80u, FUN_0023ed80_0x23ed80},
        {0x0023FB78u, FUN_0023fb78_0x23fb78},
        {0x00242628u, FUN_00242628_0x242628},
        {0x002440A8u, FUN_002440a8_0x2440a8},
        {0x00244220u, FUN_00244220_0x244220},
        {0x00244E88u, FUN_00244e88_0x244e88},
        {0x00246468u, FUN_00246468_0x246468},
        {0x00247DE0u, FUN_00247de0_0x247de0},
        {0x00247F60u, FUN_00247f60_0x247f60},
        {0x00252490u, FUN_00252490_0x252490},
        {0x00252528u, FUN_00252528_0x252528},
        {0x002525D8u, FUN_002525d8_0x2525d8},
        {0x00254AE0u, FUN_00254ae0_0x254ae0},
        {0x00259C20u, FUN_00259c20_0x259c20},
        {0x00259D38u, FUN_00259d38_0x259d38},
        {0x00259E50u, FUN_00259e50_0x259e50},
        {0x0025F7B0u, FUN_0025f7b0_0x25f7b0},
        {0x00262678u, FUN_00262678_0x262678},
        {0x0027D120u, FUN_0027d120_0x27d120},
        {0x0027EC98u, FUN_0027ec98_0x27ec98},
        {0x00182B08u, FUN_00182b08_0x182b08},
        {0x00197FF0u, FUN_00197ff0_0x197ff0},
        {0x00198240u, FUN_00198240_0x198240},
        {0x001969F8u, FUN_001969f8_0x1969f8},
    };
    constexpr int kWatchN = sizeof(kWatch) / sizeof(kWatch[0]);

    std::atomic<int> g_arm{0};
    std::atomic<int> g_watchLogs{0};
    std::atomic<int> g_restored{0};
    int g_stamp = 0;
    int g_haveInner = 0;
    uint32_t g_innerX = 0, g_innerY = 0, g_innerZ = 0, g_innerW = 0;
    uint32_t g_innerSX = 0, g_innerSY = 0, g_innerSZ = 0, g_innerSW = 0;
    uint32_t g_watchAddr = 0;
    // Translation of the matrix FUN_00182b08 passes as a1 to FUN_001d5b48 (a1 = *(obj+0x80)+0x40).
    // On the live jump that was 0x943d00, so the row is 0x90 bytes before xform+0x70.
    uint32_t g_srcAddr = 0;
    int g_bigLeft = 8;
    int g_minorLeft = 4;
    int g_haveLast = 0;
    int g_lastLogs = 0;
    uint32_t g_lastX = 0, g_lastY = 0, g_lastZ = 0, g_lastW = 0;

    uint32_t readWord(const uint8_t *rdram, uint32_t addr)
    {
        uint32_t v = 0u;
        std::memcpy(&v, rdram + (addr & kRamMask & ~3u), 4);
        return v;
    }

    float readFloat(const uint8_t *rdram, uint32_t addr)
    {
        float f = 0.0f;
        std::memcpy(&f, rdram + (addr & kRamMask & ~3u), 4);
        return f;
    }

    bool ptrOk(uint32_t p)
    {
        return p >= 0x00100000u && p < 0x02000000u && (p & 3u) == 0u;
    }

    void appendFloats(std::ostringstream &o, const uint8_t *rdram, uint32_t addr, uint32_t n)
    {
        o << "[";
        for (uint32_t i = 0; i < n; ++i)
        {
            if (i)
                o << (i % 4u == 0u ? "; " : " ");
            o << readFloat(rdram, addr + i * 4u);
        }
        o << "]";
    }

    // Shared snapshot: dir 0x90, target 0x10, cam header words, slot 4x4, basis 0x30, *(dir+0x80) 0x80.
    void appendChain(std::ostringstream &o, const uint8_t *rdram, uint32_t cam, uint32_t dir, uint32_t target)
    {
        o << std::hex << " cam=0x" << cam << " dir=0x" << dir << " tgt=0x" << target << std::dec;
        if (ptrOk(dir))
        {
            o << " dir90=";
            appendFloats(o, rdram, dir, 36);
            const uint32_t xform = readWord(rdram, dir + 0x80u);
            o << std::hex << " xform=0x" << xform << std::dec;
            if (ptrOk(xform))
            {
                o << " xform80=";
                appendFloats(o, rdram, xform, 32);
                // FUN_00182b08: a1 of FUN_001d5b48 is *(node+0x80)+0x40 (parent world).
                const uint32_t parent = readWord(rdram, xform + 0x80u);
                o << std::hex << " parent=0x" << parent << std::dec;
                if (ptrOk(parent))
                {
                    o << " par0=";
                    appendFloats(o, rdram, parent, 16);
                    o << " par40=";
                    appendFloats(o, rdram, parent + 0x40u, 16);
                }
            }
        }
        if (ptrOk(target))
        {
            o << " target=";
            appendFloats(o, rdram, target, 4);
        }
        if (ptrOk(cam))
        {
            const uint32_t index = readWord(rdram, cam + 0x174u);
            o << std::hex << " w174=0x" << index << " w180=0x" << readWord(rdram, cam + 0x180u) << " w198=0x"
              << readWord(rdram, cam + 0x198u) << " w1BC=0x" << readWord(rdram, cam + 0x1BCu) << " w1C8=0x"
              << readWord(rdram, cam + 0x1C8u) << " w1EC=0x" << readWord(rdram, cam + 0x1ECu) << std::dec;
            o << " cam16=";
            appendFloats(o, rdram, cam, 16);
            // FUN_00244fc8 reads these into the VIF packet (0x24504c cam+0x120, 0x245050 cam+0xE0) and scales xyz by 0.0078125.
            o << " camE0=";
            appendFloats(o, rdram, cam + 0xE0u, 32);
            if (index < 8u)
            {
                const uint32_t slot = kSlotBase + index * 0xC0u;
                o << " slot" << index << "=";
                appendFloats(o, rdram, slot, 16);
                o << " f74 " << readFloat(rdram, slot + 0x74u);
                // FUN_00244fc8 returns at 0x245044 when this word is 0 (no VU packet).
                o << std::hex << " s84=0x" << readWord(rdram, slot + 0x84u) << std::dec;
            }
            else
                o << " slot=idx" << index;
        }
        o << " basis=";
        appendFloats(o, rdram, kBasis, 12);
        o << " p0=0x" << std::hex << readWord(rdram, 0x002AA0D0u) << " p1=0x" << readWord(rdram, 0x002AA0D4u)
          << " flag=0x" << readWord(rdram, 0x0035A48Cu) << " ta0=0x" << readWord(rdram, 0x0035A1D0u) << " ta1=0x"
          << readWord(rdram, 0x0035A1D4u) << " tb0=0x" << readWord(rdram, 0x0035A1C8u) << " tb1=0x"
          << readWord(rdram, 0x0035A1CCu) << std::dec;
    }

    // Halfword at *(*(cam+0x1C8)+0x50). FUN_0018e1e0 0x18e310 compares it to 1000.
    uint32_t gateHalf(const uint8_t *rdram, uint32_t cam)
    {
        if (!ptrOk(cam))
            return 0xffffffffu;
        const uint32_t p1 = readWord(rdram, cam + 0x1C8u);
        if (!ptrOk(p1))
            return 0xffffffffu;
        const uint32_t p2 = readWord(rdram, p1 + 0x50u);
        if (p2 < 0x00100000u || p2 >= 0x02000000u)
            return 0xffffffffu;
        uint16_t h = 0;
        std::memcpy(&h, rdram + (p2 & kRamMask), 2);
        return h;
    }

    bool takeLine()
    {
        return g_linesLeft.fetch_sub(1) > 0;
    }

    bool due(uint32_t call)
    {
        return call <= 3u || call % 60u == 0u;
    }

    struct Quad
    {
        uint32_t x, y, z, w;
    };

    Quad readWatch(const uint8_t *rdram)
    {
        Quad q{0, 0, 0, 0};
        if (!g_watchAddr)
            return q;
        q.x = readWord(rdram, g_watchAddr);
        q.y = readWord(rdram, g_watchAddr + 4u);
        q.z = readWord(rdram, g_watchAddr + 8u);
        q.w = readWord(rdram, g_watchAddr + 12u);
        return q;
    }

    bool sameQuad(Quad a, Quad b)
    {
        return a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
    }

    bool bigWord(uint32_t u)
    {
        float f = 0.0f;
        std::memcpy(&f, &u, 4);
        return std::fabs(f) > 2000.0f;
    }

    void appendQuad(std::ostringstream &o, Quad q)
    {
        float f[4];
        const uint32_t u[4] = {q.x, q.y, q.z, q.w};
        std::memcpy(f, u, sizeof(f));
        o << std::hex << std::setfill('0');
        for (int i = 0; i < 4; ++i)
        {
            if (i)
                o << ",";
            o << "0x" << std::setw(8) << u[i];
        }
        o << std::dec << std::setfill(' ') << " (";
        for (int i = 0; i < 4; ++i)
        {
            if (i)
                o << " ";
            o << f[i];
        }
        o << ")";
    }

    Quad readAt(const uint8_t *rdram, uint32_t addr)
    {
        Quad q{0, 0, 0, 0};
        if (!addr)
            return q;
        q.x = readWord(rdram, addr);
        q.y = readWord(rdram, addr + 4u);
        q.z = readWord(rdram, addr + 8u);
        q.w = readWord(rdram, addr + 12u);
        return q;
    }

    void logWatch(const char *tag, uint32_t fn, uint32_t ra, uint32_t a0, uint32_t a1, uint32_t a2, int span,
                  Quad dstBefore, Quad dstAfter, Quad srcBefore, Quad srcAfter, const uint8_t *rdram, int withMats)
    {
        std::ostringstream o;
        o << std::fixed << std::setprecision(4);
        o << "[camwatch] " << tag << " eye=" << g_eyeCalls.load() << std::hex << " fn=0x" << fn << " ra=0x" << ra
          << " a0=0x" << a0 << " a1=0x" << a1 << " a2=0x" << a2 << std::dec << " span=" << span << " dst=";
        appendQuad(o, dstBefore);
        o << " -> ";
        appendQuad(o, dstAfter);
        o << " src=";
        appendQuad(o, srcBefore);
        o << " -> ";
        appendQuad(o, srcAfter);
        if (withMats && rdram)
        {
            if (ptrOk(a1))
            {
                o << " L=";
                appendFloats(o, rdram, a1, 16);
            }
            if (ptrOk(a2))
            {
                o << " R=";
                appendFloats(o, rdram, a2, 16);
            }
        }
        RUNTIME_LOG(o.str() << "\n");
        g_watchLogs.fetch_add(1);
    }

    // Innermost changer of camera0 xform+0x70, or of the source translation 0x90 bytes earlier, wins.
    void bracket(uint32_t fn, GuestFn orig, uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        if (g_arm.load(std::memory_order_relaxed) == 0 || g_watchAddr == 0u)
        {
            orig(rdram, ctx, runtime);
            return;
        }
        const Quad dst0 = readWatch(rdram);
        const Quad src0 = readAt(rdram, g_srcAddr);
        const uint32_t ra = getRegU32(ctx, 31);
        const uint32_t a0 = getRegU32(ctx, 4);
        const uint32_t a1 = getRegU32(ctx, 5);
        const uint32_t a2 = getRegU32(ctx, 6);
        // Matrices as they are BEFORE the call. 1D5B48 overwrites a0, not a1/a2.
        float leftKeep[16], rightKeep[16];
        int haveL = 0, haveR = 0;
        if (fn == 0x001d5b48u)
        {
            if (ptrOk(a1))
            {
                for (int i = 0; i < 16; ++i)
                    leftKeep[i] = readFloat(rdram, a1 + (uint32_t)i * 4u);
                haveL = 1;
            }
            if (ptrOk(a2))
            {
                for (int i = 0; i < 16; ++i)
                    rightKeep[i] = readFloat(rdram, a2 + (uint32_t)i * 4u);
                haveR = 1;
            }
        }
        const int stamp0 = g_stamp;
        orig(rdram, ctx, runtime);
        const Quad dst1 = readWatch(rdram);
        const Quad src1 = readAt(rdram, g_srcAddr);
        if (sameQuad(dst0, dst1) && sameQuad(src0, src1))
            return;
        const bool childSaw = g_stamp != stamp0;
        const bool extra = !g_haveInner || dst1.x != g_innerX || dst1.y != g_innerY || dst1.z != g_innerZ || dst1.w != g_innerW ||
                           src1.x != g_innerSX || src1.y != g_innerSY || src1.z != g_innerSZ || src1.w != g_innerSW;
        g_innerX = dst1.x;
        g_innerY = dst1.y;
        g_innerZ = dst1.z;
        g_innerW = dst1.w;
        g_innerSX = src1.x;
        g_innerSY = src1.y;
        g_innerSZ = src1.z;
        g_innerSW = src1.w;
        g_haveInner = 1;
        if (childSaw && !extra)
            return;
        if (!childSaw)
            ++g_stamp;
        const bool big = bigWord(dst0.x) || bigWord(dst0.z) || bigWord(dst1.x) || bigWord(dst1.z) || bigWord(src0.x) ||
                         bigWord(src0.z) || bigWord(src1.x) || bigWord(src1.z);
        const bool take = big ? (g_bigLeft > 0) : (g_minorLeft > 0);
        if (!take)
            return;
        if (big)
            --g_bigLeft;
        else
            --g_minorLeft;
        std::ostringstream o;
        o << std::fixed << std::setprecision(4);
        o << "[camwatch] " << (big ? "big" : "minor") << " eye=" << g_eyeCalls.load() << std::hex << " fn=0x" << fn
          << " ra=0x" << ra << " a0=0x" << a0 << " a1=0x" << a1 << " a2=0x" << a2 << std::dec << " span=" << (childSaw ? 1 : 0)
          << " dst=";
        appendQuad(o, dst0);
        o << " -> ";
        appendQuad(o, dst1);
        o << " src=";
        appendQuad(o, src0);
        o << " -> ";
        appendQuad(o, src1);
        if (haveL)
        {
            o << " L=[";
            for (int i = 0; i < 16; ++i)
                o << (i ? (i % 4 == 0 ? "; " : " ") : "") << leftKeep[i];
            o << "]";
        }
        if (haveR)
        {
            o << " R=[";
            for (int i = 0; i < 16; ++i)
                o << (i ? (i % 4 == 0 ? "; " : " ") : "") << rightKeep[i];
            o << "]";
        }
        RUNTIME_LOG(o.str() << "\n");
        g_watchLogs.fetch_add(1);
    }

    template <int I>
    void watchWrap(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        bracket(kWatch[I].addr, kWatch[I].fn, rdram, ctx, runtime);
    }

    static const GuestFn kWrap[] = {
        watchWrap<0>,
        watchWrap<1>,
        watchWrap<2>,
        watchWrap<3>,
        watchWrap<4>,
        watchWrap<5>,
        watchWrap<6>,
        watchWrap<7>,
        watchWrap<8>,
        watchWrap<9>,
        watchWrap<10>,
        watchWrap<11>,
        watchWrap<12>,
        watchWrap<13>,
        watchWrap<14>,
        watchWrap<15>,
        watchWrap<16>,
        watchWrap<17>,
        watchWrap<18>,
        watchWrap<19>,
        watchWrap<20>,
        watchWrap<21>,
        watchWrap<22>,
        watchWrap<23>,
        watchWrap<24>,
        watchWrap<25>,
        watchWrap<26>,
        watchWrap<27>,
        watchWrap<28>,
        watchWrap<29>,
        watchWrap<30>,
        watchWrap<31>,
        watchWrap<32>,
        watchWrap<33>,
        watchWrap<34>,
        watchWrap<35>,
        watchWrap<36>,
        watchWrap<37>,
        watchWrap<38>,
        watchWrap<39>,
        watchWrap<40>,
        watchWrap<41>,
        watchWrap<42>,
        watchWrap<43>,
        watchWrap<44>,
        watchWrap<45>,
        watchWrap<46>,
        watchWrap<47>,
        watchWrap<48>,
        watchWrap<49>,
        watchWrap<50>,
        watchWrap<51>,
        watchWrap<52>,
        watchWrap<53>,
        watchWrap<54>,
        watchWrap<55>,
        watchWrap<56>,
        watchWrap<57>,
        watchWrap<58>,
        watchWrap<59>,
        watchWrap<60>,
        watchWrap<61>,
        watchWrap<62>,
        watchWrap<63>,
        watchWrap<64>,
        watchWrap<65>,
        watchWrap<66>,
        watchWrap<67>,
        watchWrap<68>,
        watchWrap<69>,
        watchWrap<70>,
        watchWrap<71>,
        watchWrap<72>,
        watchWrap<73>,
        watchWrap<74>,
        watchWrap<75>,
        watchWrap<76>,
        watchWrap<77>,
        watchWrap<78>,
        watchWrap<79>,
        watchWrap<80>,
        watchWrap<81>,
        watchWrap<82>,
        watchWrap<83>,
        watchWrap<84>,
        watchWrap<85>,
        watchWrap<86>,
        watchWrap<87>,
        watchWrap<88>,
        watchWrap<89>,
        watchWrap<90>,
        watchWrap<91>,
        watchWrap<92>,
        watchWrap<93>,
        watchWrap<94>,
        watchWrap<95>,
        watchWrap<96>,
        watchWrap<97>,
        watchWrap<98>,
        watchWrap<99>,
        watchWrap<100>,
        watchWrap<101>,
        watchWrap<102>,
        watchWrap<103>,
        watchWrap<104>,
        watchWrap<105>,
        watchWrap<106>,
        watchWrap<107>,
        watchWrap<108>,
        watchWrap<109>,
        watchWrap<110>,
    };

    void disarm(PS2Runtime *runtime)
    {
        g_arm.store(0, std::memory_order_relaxed);
        if (g_restored.exchange(1) != 0)
            return;
        for (int i = 0; i < kWatchN; ++i)
            runtime->registerFunction(kWatch[i].addr, kWatch[i].fn);
        RUNTIME_LOG("[camwatch] restored " << kWatchN << " at eye " << g_eyeCalls.load() << "\n");
    }

    void maybeArm(uint8_t *rdram, uint32_t call, uint32_t dir)
    {
        if (call == 1u && g_watchAddr == 0u && ptrOk(dir))
        {
            const uint32_t xf = readWord(rdram, dir + 0x80u);
            if (ptrOk(xf))
            {
                g_watchAddr = xf + 0x70u;
                g_srcAddr = g_watchAddr - 0x90u;
                g_arm.store(1, std::memory_order_relaxed);
                RUNTIME_LOG("[camwatch] arm dst=0x" << std::hex << g_watchAddr << " src=0x" << g_srcAddr << " xform=0x" << xf
                            << std::dec << " n=" << kWatchN << "\n");
            }
        }
    }

    void noteGap(const char *where, uint8_t *rdram, Quad before, int logsAtEntry, uint32_t addrAtEntry)
    {
        if (!addrAtEntry || !g_arm.load(std::memory_order_relaxed))
            return;
        const Quad after = readWatch(rdram);
        if (sameQuad(before, after))
            return;
        if (g_watchLogs.load() != logsAtEntry)
            return;
        logWatch(where, 0u, 0u, 0u, 0u, 0u, 0, before, readWatch(rdram), readAt(rdram, g_srcAddr), readAt(rdram, g_srcAddr), rdram, 0);
    }

    // FUN_00186810 (called from FUN_00182430 at 0x182730, before FUN_00182b08) copies
    // float[player+0] / float[player+8] into the root translation at player+0xE00 and player+0xE40
    // (swc1 at 0x186928 / 0x18692c / 0x186930 / 0x186938). Y is player+4 + f0 + float[gp-0x7018]
    // (0x18697c / 0x186980 / 0x186984). gp-0x7018 = 0x358258.
    void logRoot(const char *tag, uint32_t call, const uint8_t *rdram, uint32_t player, uint32_t ra)
    {
        std::ostringstream o;
        o << std::fixed << std::setprecision(4);
        o << "[camlive] " << tag << " call " << call << std::hex << " p=0x" << player << " ra=0x" << ra << std::dec;
        if (ptrOk(player))
        {
            o << " pxyz=";
            appendFloats(o, rdram, player, 4);
            o << " e00=";
            appendFloats(o, rdram, player + 0xE00u, 4);
            o << " e40=";
            appendFloats(o, rdram, player + 0xE40u, 4);
        }
        o << " c7018=" << readFloat(rdram, 0x00358258u);
        // FUN_00189d18's default (lui 0x36; lwc1 -0x6CE0) and the plane list head it walks (*(0x1B3FE90+0x1C)).
        o << " h9320=" << readFloat(rdram, 0x00359320u);
        const uint32_t col = readWord(rdram, 0x01B3FEACu);
        o << std::hex << " col=0x" << col << std::dec;
        if (ptrOk(col))
        {
            o << " col0=";
            appendFloats(o, rdram, col, 8);
            o << std::hex << " coln=0x" << readWord(rdram, col + 0x1Cu) << std::dec;
        }
        RUNTIME_LOG(o.str() << "\n");
    }

    int g_rootBig = 0;
    int g_hCalls = 0;

    // FUN_00189d18 returns f0 = f20. f20 is loaded from 0x359320 and raised when a plane wins (0x189f98).
    // Only the call from FUN_00186810 (ra 0x18693c) feeds the root Y.
    void heightLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t ra = getRegU32(ctx, 31);
        const uint32_t a0 = getRegU32(ctx, 4);
        const bool log = ra == 0x0018693Cu && g_hCalls < 8;
        const float def = readFloat(rdram, 0x00359320u);
        if (log)
            ++g_hCalls;
        FUN_00189d18_0x189d18(rdram, ctx, runtime);
        if (!log)
            return;
        std::ostringstream o;
        o << std::fixed << std::setprecision(4);
        o << "[camlive] h89d18 n=" << g_hCalls << std::hex << " a0=0x" << a0 << std::dec << " def=" << def
          << " f0=" << ctx->f[0];
        if (ptrOk(a0))
        {
            o << " q=";
            appendFloats(o, rdram, a0, 4);
        }
        RUNTIME_LOG(o.str() << "\n");
    }

    void rootLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t call = g_rootCalls.fetch_add(1u) + 1u;
        const uint32_t player = getRegU32(ctx, 4);
        const uint32_t ra = getRegU32(ctx, 31);
        // 0x182738 is the return into FUN_00182430 (the init that plants the 16k root).
        // Other callers (FUN_001a82d0 at 0x1a84bc) run every frame; keep only the first
        // samples and the first few whose position or root translation exceeds 2000.
        const float px = ptrOk(player) ? readFloat(rdram, player) : 0.0f;
        const float pz = ptrOk(player) ? readFloat(rdram, player + 8u) : 0.0f;
        const float ex = ptrOk(player) ? readFloat(rdram, player + 0xE40u) : 0.0f;
        const bool big = std::fabs(px) > 2000.0f || std::fabs(pz) > 2000.0f || std::fabs(ex) > 2000.0f;
        bool log = call <= 2u || ra == 0x00182738u;
        if (!log && big && g_rootBig < 6)
            log = true;
        if (log && big)
            ++g_rootBig;
        if (log)
            logRoot("pre86810", call, rdram, player, ra);
        FUN_00186810_0x186810(rdram, ctx, runtime);
        if (log)
            logRoot("post86810", call, rdram, player, ra);
    }

    void eyeLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t call = g_eyeCalls.fetch_add(1u) + 1u;
        const bool log = due(call) && g_linesLeft.load() > 0;
        const uint32_t a0 = getRegU32(ctx, 4), a1 = getRegU32(ctx, 5), a2 = getRegU32(ctx, 6), a3 = getRegU32(ctx, 7);
        // Token at gp-0x50A0 is consumed (stored 0) before FUN_0018e1e0 returns, so read it on entry.
        const uint32_t preFlag = readWord(rdram, 0x0035A48Cu);
        const uint32_t preIdx = ptrOk(a1) ? readWord(rdram, a1 + 0x174u) : 0xffffffffu;
        const uint32_t preTa = preIdx < 16u ? readWord(rdram, 0x0035A1D0u + preIdx * 4u) : 0xffffffffu;
        const uint32_t preTb = preIdx < 16u ? readWord(rdram, 0x0035A1C8u + preIdx * 4u) : 0xffffffffu;
        const uint32_t preHw = gateHalf(rdram, a1);
        if (call >= kWatchUntilEye)
            disarm(runtime);
        maybeArm(rdram, call, a0);
        const uint32_t addrAtEntry = g_watchAddr;
        const Quad before = readWatch(rdram);
        const int logsAtEntry = g_watchLogs.load();
        if (g_arm.load(std::memory_order_relaxed) && g_haveLast && addrAtEntry &&
            !sameQuad(before, Quad{g_lastX, g_lastY, g_lastZ, g_lastW}) && logsAtEntry == g_lastLogs)
            logWatch("uncaught-between", 0u, 0u, a0, a1, 0u, 0, Quad{g_lastX, g_lastY, g_lastZ, g_lastW}, before, readAt(rdram, g_srcAddr),
                     readAt(rdram, g_srcAddr), rdram, 0);
        if (g_arm.load(std::memory_order_relaxed) && g_watchAddr)
            bracket(0x0018e1e0u, FUN_0018e1e0_0x18e1e0, rdram, ctx, runtime);
        else
            FUN_0018e1e0_0x18e1e0(rdram, ctx, runtime);
        maybeArm(rdram, call, a0);
        noteGap("uncaught-eye", rdram, before, logsAtEntry, addrAtEntry);
        const Quad after = readWatch(rdram);
        g_lastX = after.x;
        g_lastY = after.y;
        g_lastZ = after.z;
        g_lastW = after.w;
        g_lastLogs = g_watchLogs.load();
        g_haveLast = 1;
        if (call <= 6u)
        {
            logRoot("rooteye", call, rdram, readWord(rdram, 0x002AA0D0u), 0u);
            logRoot("rooteye", call, rdram, readWord(rdram, 0x002AA0D4u), 0u);
        }
        if (!log || !takeLine())
            return;
        std::ostringstream o;
        o << std::fixed << std::setprecision(4);
        float a2f = 0, a3f = 0;
        std::memcpy(&a2f, &a2, 4);
        std::memcpy(&a3f, &a3, 4);
        o << "[camlive] eye call " << call << std::hex << " a0=0x" << a0 << " a1=0x" << a1 << " a2=0x" << a2
          << " a3=0x" << a3 << " preflag=0x" << preFlag << " preIdx=0x" << preIdx << " preTa=0x" << preTa
          << " preTb=0x" << preTb << std::dec << " preHw=" << preHw << " a2f=" << a2f << " a3f=" << a3f;
        appendChain(o, rdram, a1, a0, a3);
        RUNTIME_LOG(o.str() << "\n");
    }

    void lookAtLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t call = g_lookCalls.fetch_add(1u) + 1u;
        const bool log = due(call) && g_linesLeft.load() > 0;
        const uint32_t a0 = getRegU32(ctx, 4), a1 = getRegU32(ctx, 5), a2 = getRegU32(ctx, 6), a3 = getRegU32(ctx, 7);
        if (g_arm.load(std::memory_order_relaxed) && g_watchAddr)
            bracket(0x00193800u, FUN_00193800_0x193800, rdram, ctx, runtime);
        else
            FUN_00193800_0x193800(rdram, ctx, runtime);
        if (!log || !takeLine())
            return;
        std::ostringstream o;
        o << std::fixed << std::setprecision(4);
        float a2f = 0, a3f = 0;
        std::memcpy(&a2f, &a2, 4);
        std::memcpy(&a3f, &a3, 4);
        const uint32_t dir = ptrOk(a0) ? readWord(rdram, a0 + 0x198u) : 0u;
        o << "[camlive] look call " << call << std::hex << " a0=0x" << a0 << " a1=0x" << a1 << " a2=0x" << a2
          << " a3=0x" << a3 << std::dec << " a2f=" << a2f << " a3f=" << a3f;
        appendChain(o, rdram, a0, dir, a1);
        RUNTIME_LOG(o.str() << "\n");
    }

    // FUN_00244fc8(a0=cam) builds the VIF packet from the slot. Logged after the call: the slot 4x4 it copied
    // at 0x2454c4 (no later store to that 4x4 in the function).
    void uploadLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t call = g_upCalls.fetch_add(1u) + 1u;
        const bool log = due(call) && g_upLeft.load() > 0;
        const uint32_t cam = getRegU32(ctx, 4);
        if (g_arm.load(std::memory_order_relaxed) && g_watchAddr)
            bracket(0x00244fc8u, FUN_00244fc8_0x244fc8, rdram, ctx, runtime);
        else
            FUN_00244fc8_0x244fc8(rdram, ctx, runtime);
        if (!log || g_upLeft.fetch_sub(1) <= 0)
            return;
        std::ostringstream o;
        o << std::fixed << std::setprecision(4) << "[camlive] upload call " << call << std::hex << " cam=0x" << cam
          << std::dec;
        if (ptrOk(cam))
        {
            const uint32_t index = readWord(rdram, cam + 0x174u);
            const uint32_t dir = readWord(rdram, cam + 0x198u);
            o << " idx=" << index << " camE0=";
            appendFloats(o, rdram, cam + 0xE0u, 32);
            o << std::hex << " w1BC=0x" << readWord(rdram, cam + 0x1BCu) << std::dec;
            if (index < 8u)
            {
                const uint32_t slot = kSlotBase + index * 0xC0u;
                o << " vu=";
                appendFloats(o, rdram, slot, 16);
                o << " f74 " << readFloat(rdram, slot + 0x74u);
                o << std::hex << " s84=0x" << readWord(rdram, slot + 0x84u) << std::dec;
            }
            if (ptrOk(dir))
            {
                o << " dir+30=";
                appendFloats(o, rdram, dir + 0x30u, 4);
                o << " dir+40=";
                appendFloats(o, rdram, dir + 0x40u, 16);
            }
        }
        RUNTIME_LOG(o.str() << "\n");
    }

    void apply(PS2Runtime &runtime)
    {
        if (const char *lines = std::getenv("TEKKEN4_CAMERA_LOG"))
        {
            g_linesLeft = std::atoi(lines);
            runtime.registerFunction(0x0018e1e0u, eyeLogged);
            runtime.registerFunction(0x00193800u, lookAtLogged);
            runtime.registerFunction(0x00244fc8u, uploadLogged);
            runtime.registerFunction(0x00186810u, rootLogged);
            runtime.registerFunction(0x00189d18u, heightLogged);
            int missed = 0;
            for (int i = 0; i < kWatchN; ++i)
            {
                if (!runtime.registerFunction(kWatch[i].addr, kWrap[i]))
                    ++missed;
            }
            RUNTIME_LOG("[camlive] eye/look every 60th (" << g_linesLeft.load()
                        << " lines), upload every 60th (40 lines). dir 0x90, slot 0x01CE2270+idx*0xC0 watch "
                        << kWatchN << " miss " << missed << "\n");
        }
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 camera log (SLUS-20328 v1.00)", "SLUS_203.28", 0x00180088u, 0xB975F704u,
                           tekken4_camera::apply)
