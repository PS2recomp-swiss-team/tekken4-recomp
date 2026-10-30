// Tekken 4 (SLUS-20328, NTSC-U v1.00): all fighters (and costumes) selectable from the start.
//
// ON by default; TEKKEN4_UNLOCK_ALL=0 turns it off (the game's own unlock rules apply again). Netplay: the setting
// is read once at startup, so both peers must run with the same value (unset on both = unlocked; the launcher and
// netplay never need to set it, only 0 differs and must then be set on both sides).
//
// How the game decides (found with headless Ghidra, tools\ghidra_decomp.cmd):
//   0x30e100 is a table of 112 entries x 28 bytes, one per (fighter, costume): +0 u16 fighter, +2 u16 costume,
//   +4 name id, ..., +24 a callback "is this fighter/costume available?" (FUN_001e2da0(i) calls it).
//   Callback 0x1e2c88 = always 1, 0x1e2c80 = always 0, 0x1ec350 = checks the save profile: bit <costume> of
//   byte (0x36c2b8 + 0x60 + fighter) (FUN_001ec0a0). 0x1ec350 is the only entry that depends on save data.
//   FUN_001e2cc0 builds the selectable-fighter mask (gp-0x52d4) and per-fighter costume counts from the callbacks;
//   the character-select grid, Arcade/Story/VS lists all go through FUN_001e2da0 / that mask.
// This override replaces 0x1ec350 with "return 1": the save profile in RAM (and so the memory card) is never touched.
#include "game_overrides.h"
#include "ps2_log.h"
#include "ps2_runtime.h"

#include <cstdlib>
#include <cstring>

namespace tekken4_unlock
{
    constexpr uint32_t kAvailableCheck = 0x001ec350u; // FUN_001ec350(entry): save-profile costume/fighter bit test

    void alwaysAvailable(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        (void)rdram;
        (void)runtime;
        SET_GPR_U32(ctx, 2, 1u); // v0 = 1
        ctx->pc = getRegU32(ctx, 31);
    }

    void apply(PS2Runtime &runtime)
    {
        const char *env = std::getenv("TEKKEN4_UNLOCK_ALL");
        if (env && *env && std::strcmp(env, "0") == 0)
        {
            RUNTIME_LOG("[tekken4] TEKKEN4_UNLOCK_ALL=0: the game's own unlocks apply\n");
            return;
        }
        runtime.registerFunction(kAvailableCheck, alwaysAvailable);
        RUNTIME_LOG("[tekken4] all fighters unlocked (override of 0x1ec350; TEKKEN4_UNLOCK_ALL=0 turns it off)\n");
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 unlock all (SLUS-20328 v1.00)", "SLUS_203.28", 0x00180088u, 0xB975F704u,
                           tekken4_unlock::apply)
