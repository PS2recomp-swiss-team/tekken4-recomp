// Tekken 4 port (t4vurecomp): offline check of the statically recompiled VU microprograms.
//
// Runs every lifted entry of a micro memory image many times from random entry states (registers, flags, Q/P/I, VU
// data memory, cycle budgets small enough to hit the hand-over paths) through PS2X_VULIFT_VERIFY's comparison: the
// exact engine alone vs the lifted code, bit for bit (registers, flags, cycle counter, pipeline readiness, VU memory,
// XGKICK packets). The image is the player's own (game code): it stays local, nothing of it is printed.
// build: tools\vu\build_fuzz.cmd   run: vulift_fuzz.exe <image.bin> [iterations per entry] [seed] [vu0]
#include "runtime/ps2_vu1.h"
#include "runtime/ps2_vu_lift.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <vector>

class GS;

namespace
{
    std::mt19937_64 rng;

    uint32_t randFloatBits()
    {
        const uint32_t k = rng() % 100;
        const uint32_t sign = (rng() & 1) ? 0x80000000u : 0u;
        float f;
        uint32_t b;
        if (k < 40)
        {
            f = static_cast<float>(static_cast<int64_t>(rng() % 2000001) - 1000000) / 1000.0f;
            std::memcpy(&b, &f, 4);
            return b;
        }
        if (k < 50)
            return static_cast<uint32_t>(rng() % 0x400);
        if (k < 58)
            return sign;
        if (k < 63)
            return sign | static_cast<uint32_t>(rng() & 0x7FFFFF); // denormal
        if (k < 68)
            return sign | 0x7F800000u | static_cast<uint32_t>(rng() & 0x7FFFFF); // inf / nan
        if (k < 76)
            return sign | (static_cast<uint32_t>(0xF8 + rng() % 7) << 23) | static_cast<uint32_t>(rng() & 0x7FFFFF);
        if (k < 84)
            return sign | (static_cast<uint32_t>(1 + rng() % 4) << 23) | static_cast<uint32_t>(rng() & 0x7FFFFF);
        if (k < 90)
        {
            f = static_cast<float>(rng() % 64) * 0.5f; // small exact values (cancellation)
            std::memcpy(&b, &f, 4);
            return b | sign;
        }
        return static_cast<uint32_t>(rng());
    }
}

int main(int argc, char **argv)
{
    if (argc < 2)
    {
        std::fprintf(stderr, "usage: vulift_fuzz <image.bin> [iterations] [seed] [vu0]\n");
        return 2;
    }
    const bool vu0 = argc > 4 && std::strcmp(argv[4], "vu0") == 0;
    const uint32_t codeSize = vu0 ? 0x1000u : 0x4000u, dataSize = codeSize;
    std::vector<uint8_t> code(codeSize), data(dataSize);
    std::FILE *f = std::fopen(argv[1], "rb");
    if (!f || std::fread(code.data(), 1, codeSize, f) != codeSize)
    {
        std::fprintf(stderr, "cannot read %s\n", argv[1]);
        return 2;
    }
    std::fclose(f);
    const long iterations = argc > 2 ? std::atol(argv[2]) : 200;
    rng.seed(argc > 3 ? std::strtoull(argv[3], nullptr, 10) : 1);
    _putenv("PS2X_VULIFT_VERIFY=all");
    _putenv("PS2X_VULIFT_QUIET=1");

    const uint32_t unit = vu0 ? 0u : 1u;
    vuLiftTestSetCode(unit, code.data(), 1);
    uint16_t entries[512];
    const uint32_t n = vuLiftTestEntries(unit, entries, 512);
    std::printf("%u lifted entries\n", n);
    VU1Interpreter vu(vu0 ? VU1Interpreter::Unit::VU0 : VU1Interpreter::Unit::VU1);
    vu.reset();
    vu.setDirectRegisterWrites(!vu0);
    vuLiftTestSetSilent(vu, true);
    GS *gs = nullptr;
    for (long it = 0; it < iterations; ++it)
        for (uint32_t e = 0; e < n; ++e)
        {
            VU1State &s = vu.state();
            for (int r = 1; r < 32; ++r)
                for (int c = 0; c < 4; ++c)
                {
                    const uint32_t b = randFloatBits();
                    std::memcpy(&s.vf[r][c], &b, 4);
                }
            for (int r = 1; r < 16; ++r)
            {
                const uint32_t k = rng() % 10;
                s.vi[r] = k < 6 ? static_cast<int16_t>(rng() % 0x400) : k < 8 ? static_cast<int16_t>(rng() % 16)
                                                                        : static_cast<int16_t>(rng());
            }
            for (int c = 0; c < 4; ++c)
            {
                const uint32_t b = randFloatBits();
                std::memcpy(&s.acc[c], &b, 4);
            }
            uint32_t b = randFloatBits();
            std::memcpy(&s.q, &b, 4);
            b = randFloatBits();
            std::memcpy(&s.p, &b, 4);
            b = randFloatBits();
            std::memcpy(&s.i, &b, 4);
            s.r = 0x3F800000u | static_cast<uint32_t>(rng() & 0x7FFFFF);
            s.mac = static_cast<uint32_t>(rng() & 0xFFFF);
            s.clip = static_cast<uint32_t>(rng() & 0xFFFFFF);
            s.status = static_cast<uint32_t>(rng() & 0xFFF);
            for (uint32_t o = 0; o < dataSize; o += 4)
            {
                // mostly floats; some words that look like GIF tags with a small loop count
                uint32_t w = randFloatBits();
                std::memcpy(data.data() + o, &w, 4);
            }
            for (uint32_t o = 0; o < dataSize; o += 16)
            {
                // GIF-tag-like qwords (small loop counts, valid formats) so XGKICKs transfer real packets
                if (rng() % 10 == 0)
                    continue;
                const uint32_t lo = static_cast<uint32_t>(rng() % 6) | ((rng() % 3 == 0) ? 0x8000u : 0u);
                const uint32_t hi = static_cast<uint32_t>((rng() % 3) << 26 | (1u + rng() % 4) << 28);
                std::memcpy(data.data() + o, &lo, 4);
                std::memcpy(data.data() + o + 4, &hi, 4);
            }
            const uint32_t budgetPick = static_cast<uint32_t>(rng() % 10);
            const uint32_t budget = budgetPick < 6 ? 65536u : budgetPick < 8 ? 2000u : 200u + static_cast<uint32_t>(rng() % 400);
            vu.execute(code.data(), codeSize, data.data(), dataSize, *gs, nullptr, entries[e], 0x100u + static_cast<uint32_t>(rng() % 0x80),
                       static_cast<uint32_t>(rng() % 0x400), budget);
        }
    const uint64_t checked = vuLiftTestCounter(0), bad = vuLiftTestCounter(1), rejected = vuLiftTestCounter(2);
    std::printf("vulift_fuzz: %llu runs checked, %llu mismatches (%llu runs with a rejected XGKICK packet not compared)\n",
                (unsigned long long)checked, (unsigned long long)bad, (unsigned long long)rejected);
    return bad ? 1 : 0;
}
