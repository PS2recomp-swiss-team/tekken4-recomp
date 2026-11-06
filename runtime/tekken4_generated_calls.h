// The generated game functions our modules call by name (wrappers that log, hook or adjust a call and then run the
// game's own function). In a release runtime (PS2X_GAME_DLL_HOST, 0.1.4) the generated code is not part of the program:
// it is in ps2_game.dll, built on the player's PC from their disc, and these calls go through the function table that
// DLL handed over at start -- as it was before any of our modules replaced an entry, so a wrapper never calls itself.
// A developer build (generated code compiled into the program) calls them directly as before.
#pragma once
#if defined(PS2X_GAME_DLL_HOST)
#include "ps2_runtime.h"
#define T4_GENERATED_FUNCTION(name, address)                                         \
    inline void name(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)       \
    {                                                                              \
        ps2GameDllOriginal(address)(rdram, ctx, runtime);                          \
    }
T4_GENERATED_FUNCTION(FUN_0018e1e0_0x18e1e0, 0x0018e1e0u)
T4_GENERATED_FUNCTION(FUN_00193800_0x193800, 0x00193800u)
T4_GENERATED_FUNCTION(FUN_00227bd8_0x227bd8, 0x00227bd8u)
T4_GENERATED_FUNCTION(FUN_0022a598_0x22a598, 0x0022a598u)
T4_GENERATED_FUNCTION(FUN_002323a0_0x2323a0, 0x002323a0u)
T4_GENERATED_FUNCTION(FUN_00232ab0_0x232ab0, 0x00232ab0u)
T4_GENERATED_FUNCTION(FUN_00232bc8_0x232bc8, 0x00232bc8u)
T4_GENERATED_FUNCTION(FUN_002330b8_0x2330b8, 0x002330b8u)
T4_GENERATED_FUNCTION(FUN_00291d30_0x291d30, 0x00291d30u)
T4_GENERATED_FUNCTION(sceGifPkCloseGifTag_0x291ee8, 0x00291ee8u)
#undef T4_GENERATED_FUNCTION
#else
#include <ps2_recompiled_functions.h>
#endif
