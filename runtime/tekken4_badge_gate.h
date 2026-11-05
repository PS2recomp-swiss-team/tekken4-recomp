#pragma once
// Rank badge visibility gate (host only; reads, never writes, guest state).
// A badge belongs to the player-name text and may be drawn only while the game itself queues that text. The name
// hooks (tekken4_hud_overrides.cpp) remember the game-loop counter of the frame in which they queued each side's
// text; the presenter draws a badge only when that frame is the one on screen. Frames that queue no name (KO
// replay, KO slow motion, intros and win poses without the HUD, pause menus that hide it, menus) therefore show
// no badge, whatever the scene/type registers still say.
//
// What "the frame on screen" means in counter terms was measured (TEKKEN4_HUD_GATE_LOG, 16,000-frame rollback
// pair, VS select and fight): the game increments the counter right after the frame's draw calls, so the
// presenter reads queued+1 on about 85 % of its passes and queued+0 on the rest (it ran between the queue and the
// increment); queued+2 never happened in live play. An exact "counter == queued" test hid the badge on 98 % of
// the passes in select and 85 % in the fight. So the frame is current while the counter is at most one ahead.
// A rollback restores the counter below the queue's for the few frames it re-simulates (the picture shown stays
// the last live one, which had its names): up to kMaxBehind frames back is the same frame as well.
#include <cstdint>

namespace tekken4_badge_gate
{
    constexpr uint32_t kGameFrame = 0x00356018u; // game-loop counter (u32), +1 per game frame
    constexpr int32_t kMaxAhead = 1;             // counter minus the frame of the last name queue
    constexpr int32_t kMaxBehind = 16;           // rollback depth bound (netplay windows are <= 12 frames)

    // Counter distance from the last name queue to now (signed, modulo 2^32).
    inline int32_t distance(uint32_t queuedFrame, uint32_t currentFrame)
    {
        return static_cast<int32_t>(currentFrame - queuedFrame);
    }

    inline bool visible(bool valid, int anchorScene, uint8_t alpha, uint32_t queuedFrame, int scene, uint32_t currentFrame,
                        int32_t maxAhead = kMaxAhead, int32_t maxBehind = kMaxBehind)
    {
        if (!valid || anchorScene != scene || alpha == 0)
            return false;
        const int32_t d = distance(queuedFrame, currentFrame);
        return d <= maxAhead && d >= -maxBehind;
    }
}
