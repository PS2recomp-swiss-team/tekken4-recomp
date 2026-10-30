// Tekken 4 (SLUS-20328, NTSC-U v1.00): game-thread performance in normal play (docs/PERF.md, "Building to 60").
// TEKKEN4_PERF_IDLE=0   the main loop's vsync wait (FUN_0022a140, polls 0x1ccafb7 at 0x22a150 until the vblank handler
//                       clears it) iterates as the game does: one 32-cycle checkpoint per iteration, each advancing the
//                       EE timers and the IOP (~100k per frame on a heavy stage). Default: the scheduler accounts the
//                       iterations up to just before the next event (deadline, EE timer interrupt, slice end) in one step
//                       (EeScheduler::setIdleLoopPcs, the same skip the rollback modes use: same EE cycles and events).
// Rollback/netplay modes (TEKKEN4_RB_MODE / TEKKEN4_NET) set this themselves (TEKKEN4_RB_IDLE), so nothing is done here.
#include "game_overrides.h"
#include "ps2_log.h"
#include "ps2_runtime.h"
#include "runtime/ee_scheduler.h"

#include <cstdlib>

namespace tekken4_perf2
{
    void apply(PS2Runtime &runtime)
    {
        const char *rb = std::getenv("TEKKEN4_RB_MODE");
        const char *net = std::getenv("TEKKEN4_NET");
        if ((rb && *rb) || (net && *net))
            return;
        const char *idle = std::getenv("TEKKEN4_PERF_IDLE");
        if (idle && *idle && std::atoi(idle) == 0)
        {
            RUNTIME_LOG("[tekken4] TEKKEN4_PERF_IDLE=0: the vsync wait loop iterates as the game does\n");
            return;
        }
        runtime.eeScheduler().setIdleLoopPcs({0x0022a150u});
        RUNTIME_LOG("[tekken4] vsync wait loop 0x22a150: iterations up to the next event accounted in one step\n");
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 perf (SLUS-20328 v1.00)", "SLUS_203.28", 0x00180088u, 0xB975F704u,
                           tekken4_perf2::apply)
