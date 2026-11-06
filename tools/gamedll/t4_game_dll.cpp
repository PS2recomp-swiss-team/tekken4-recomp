// The few things a C runtime would give the Tekken 4 game DLL (it is linked without one) and the export the runtime
// (ps2EntryRunner.exe, PS2X_GAME_DLL_HOST, src/lib/ps2_game_dll.cpp) looks up when it loads it. Compiled with the same
// header-free flags as the generated code (tools/build_game_dll.py).
#include <stdint.h>
#include "ps2_runtime.h"
#include "ps2_game_dll_abi.h"

extern "C" int _fltused = 0x9875;

// No destructors run at exit: the process ends with the game.
extern "C" int atexit(void (*)(void)) { return 0; }

// Stack probe for frames over a page (same contract as the CRT's __chkstk: probe from the caller's RSP down, keep every
// register but R10/R11 and the flags, leave RSP alone).
extern "C" __attribute__((naked)) void __chkstk(void)
{
    __asm__ volatile(
        "subq   $16, %rsp\n\t"
        "movq   %r10, (%rsp)\n\t"
        "movq   %r11, 8(%rsp)\n\t"
        "xorq   %r11, %r11\n\t"
        "leaq   24(%rsp), %r10\n\t"
        "subq   %rax, %r10\n\t"
        "cmovbq %r11, %r10\n\t"
        "movq   %gs:0x10, %r11\n\t"
        "cmpq   %r11, %r10\n\t"
        "jae    2f\n\t"
        "andw   $0xF000, %r10w\n\t"
        "1:\n\t"
        "leaq   -0x1000(%r11), %r11\n\t"
        "movb   $0, (%r11)\n\t"
        "cmpq   %r11, %r10\n\t"
        "jne    1b\n\t"
        "2:\n\t"
        "movq   (%rsp), %r10\n\t"
        "movq   8(%rsp), %r11\n\t"
        "addq   $16, %rsp\n\t"
        "ret");
}

// Static constructors (.CRT$XCU): the generated function table and the lifted VU programs register themselves.
typedef void (*t4_ctor)(void);
#pragma section(".CRT$XCA", read)
#pragma section(".CRT$XCZ", read)
__declspec(allocate(".CRT$XCA")) t4_ctor t4_xc_a = 0;
__declspec(allocate(".CRT$XCZ")) t4_ctor t4_xc_z = 0;

#ifndef T4_GAME_DLL_SIMD
#define T4_GAME_DLL_SIMD 0
#endif

static Ps2GameDllInfo g_info;

extern "C" __declspec(dllexport) const Ps2GameDllInfo *ps2_game_dll_init(uint32_t hostAbi)
{
    if (hostAbi != PS2_GAME_DLL_ABI)
        return nullptr;
    for (t4_ctor *p = &t4_xc_a + 1; p < &t4_xc_z; ++p)
        if (*p)
            (*p)();
    g_info.abi = PS2_GAME_DLL_ABI;
    g_info.simd = T4_GAME_DLL_SIMD;
    g_info.tableBase = g_ps2RecompiledFunctionTableBase;
    g_info.tableEnd = g_ps2RecompiledFunctionTableEnd;
    g_info.tableSlotCount = g_ps2RecompiledFunctionTableSlotCount;
    g_info.table = g_ps2RecompiledFunctionTable;
    return &g_info;
}
