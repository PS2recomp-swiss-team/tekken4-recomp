// Tekken 4 (SLUS-20328, NTSC-U v1.00): repeatable test runs.
// TEKKEN4_RAND_SEED=<n>: the game's srand (0x2a2528) stores <n> instead of the seed the game passes, so every random
// pick (Arcade opponents, the stage card the Practice stage select opens on, CPU AI) follows the same sequence each run.
// For test runs only (tools\run_fixed_fight.ps1); normal play keeps the game's own seed. The game's rand runs on this
// state (tekken4_overrides.cpp guestRand), so nothing else is needed.
#include "game_overrides.h"
#include "ps2_log.h"
#include "ps2_runtime.h"
#include "runtime/ps2_memory.h"

#include <cstdint>
#include <cstdlib>
#include <cstring>

namespace tekken4_testseed
{
    constexpr uint32_t kSrand = 0x002a2528u;    // newlib srand: stores the seed at _impure_ptr + 88
    constexpr uint32_t kReentPtr = 0x00304b94u; // _impure_ptr
    uint32_t g_seed = 0u;

    void pinnedSrand(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        (void)runtime;
        ctx->pc = getRegU32(ctx, 31);
        uint32_t reent = 0u;
        std::memcpy(&reent, rdram + kReentPtr, 4);
        if (uint8_t *state = getMemPtr(rdram, reent + 88u))
            std::memcpy(state, &g_seed, 4);
    }

    void apply(PS2Runtime &runtime)
    {
        const char *seed = std::getenv("TEKKEN4_RAND_SEED");
        if (!seed || !*seed)
            return;
        g_seed = static_cast<uint32_t>(std::strtoul(seed, nullptr, 0));
        runtime.registerFunction(kSrand, pinnedSrand);
        RUNTIME_LOG("[tekken4] TEKKEN4_RAND_SEED=" << g_seed << ": the game's srand is pinned to it\n");
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 test seed (SLUS-20328 v1.00)", "SLUS_203.28", 0x00180088u, 0xB975F704u,
                           tekken4_testseed::apply)
