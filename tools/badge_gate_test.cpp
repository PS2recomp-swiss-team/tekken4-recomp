// Synthetic checks of the badge visibility gate. No game, renderer or network.
#include "../runtime/tekken4_badge_gate.h"
#include <cassert>
#include <iostream>

using tekken4_badge_gate::visible;

int main()
{
    constexpr int kSelect = 7, kFight = 4;
    // Live play as measured: the presenter sees the counter at the queue's frame or one ahead.
    assert(visible(true, kFight, 128, 1000, kFight, 1000));
    assert(visible(true, kFight, 128, 1000, kFight, 1001));
    // Replay / KO slow motion / pose without HUD: no name is queued any more, the counter goes on.
    assert(!visible(true, kFight, 128, 1000, kFight, 1002));
    for (uint32_t frame = 1002; frame < 1002 + 5000; ++frame)
        assert(!visible(true, kFight, 128, 1000, kFight, frame));
    // Same alpha rule as the text: a fully faded name has no badge; a partial fade keeps it.
    assert(!visible(true, kFight, 0, 1000, kFight, 1000));
    assert(visible(true, kSelect, 17, 1000, kSelect, 1001));
    // Wrong scene, never queued, invalidated anchor.
    assert(!visible(true, kSelect, 128, 1000, kFight, 1000));
    assert(!visible(false, kFight, 128, 1000, kFight, 1000));
    // A rollback restores the counter below the last queue: still the same on-screen frame, up to the bound.
    assert(visible(true, kFight, 128, 1000, kFight, 999));
    assert(visible(true, kFight, 128, 1000, kFight, 1000 - tekken4_badge_gate::kMaxBehind));
    assert(!visible(true, kFight, 128, 1000, kFight, 1000 - tekken4_badge_gate::kMaxBehind - 1));
    assert(!visible(true, kFight, 128, 1000, kFight, 900));
    // The counter wraps modulo 2^32 without the gate misjudging the distance.
    assert(visible(true, kFight, 128, 0xffffffffu, kFight, 0xffffffffu));
    assert(visible(true, kFight, 128, 0xffffffffu, kFight, 0));
    assert(!visible(true, kFight, 128, 0xffffffffu, kFight, 1));
    assert(visible(true, kFight, 128, 0, kFight, 0xfffffff8u));
    // Explicit limits are honoured exactly.
    assert(visible(true, kFight, 128, 1000, kFight, 1000, 0, 0));
    assert(!visible(true, kFight, 128, 1000, kFight, 1001, 0, 0));
    assert(tekken4_badge_gate::kMaxAhead == 1);
    std::cout << "all passed\n";
    return 0;
}
