// Tekken 4 (SLUS-20328 v1.00 only) match state read from guest RAM at frame boundaries: both fighters, health,
// round wins, rounds to win, round timer, the game's own match decision. Read only: nothing here writes guest
// memory, so it cannot change the simulation. Addresses and their evidence: docs/MATCH_RESULT_T4.md.
//
// Frames are sampled at every boundary visit (live AND re-simulated: a rollback overwrites the mispredicted
// sample of a frame with the corrected one) into a ring; confirm(upto) walks the frames that can no longer change
// (every input before them confirmed: netplay's min(remoteContig, frame), offline every frame) in order and turns
// them into events. Only confirmed frames decide a round or the match, so a KO seen on a predicted input that a
// rollback then removes is never reported (T5DR's match_end_final rule).
#pragma once

#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace tekken4_match
{
    // ---- guest addresses (physical RDRAM), SLUS-20328 v1.00
    // Player objects: a table of two pointers (P1, P2) built by FUN_00198a68 (stride 0xF20).
    constexpr uint32_t kPlayerTable = 0x002a9420u;
    constexpr uint32_t kPlayerStatic[2] = {0x002a95b0u, 0x002aa4d0u};
    constexpr uint32_t kOffSide = 0x3cu;        // s16: 0 = P1 side object, 1 = P2 (FUN_00198a68)
    constexpr uint32_t kOffWins = 0x8eu;        // s16: rounds won in this match (FUN_001bbe70 increments it)
    constexpr uint32_t kOffRoundResult = 0x90u; // s16: last round 1 = won, -1 = lost (FUN_001bbe70)
    constexpr uint32_t kOffHealth = 0x6bcu;     // s32: health, 16.16 fixed point (165.0 = full); 0 = KO
    constexpr uint32_t kRoundsToWin = 0x00357d74u; // u32: read by FUN_00197b78 (match end when wins reach it)
    constexpr uint32_t kRoundTimer = 0x00356064u;  // s32: round time left in frames (gp-0x6B0C, FUN_001bcb08)
    constexpr uint32_t kRoundNumber = 0x00356078u; // u32: 1-based round of the match (gp-0x6AF8)
    constexpr uint32_t kGameState = 0x002a8bf8u;   // FUN_001bbb28's struct: +0x2C result, +0x2D winner side
    constexpr uint32_t kMatchCode = kGameState + 0x2cu; // u8: 1 = P1 won the match, 2 = P2, 3 = equal wins
    constexpr uint32_t kMatchWinnerSide = kGameState + 0x2du;
    // The game's scene manager (FUN_001978d0; found by agent t4autovs): current scene, 4 = the VS fight, 7 = the
    // character select, 2 = the mode menu.
    constexpr uint32_t kScene = 0x00357d38u;
    constexpr int32_t kSceneFight = 4;

    struct Sample
    {
        uint64_t frame = ~0ull;
        bool pointersOk = false;
        int16_t wins[2] = {0, 0};
        int16_t roundResult[2] = {0, 0};
        int32_t health[2] = {0, 0};
        int32_t timer = 0;
        uint32_t roundsToWin = 0, round = 0;
        int32_t scene = -1;
        uint8_t code = 0, winnerSide = 0;
        int32_t chars[2] = {-1, -1};
        int32_t costumes[2] = {-1, -1};
        int32_t stage = -1;
    };

    struct Round
    {
        uint64_t frame = 0;
        int winner = -1;          // 0 = P1, 1 = P2, -1 = draw (both or neither got the round)
        bool timeOut = false;     // the round timer ran out (else a KO)
        int32_t health[2] = {0, 0};
    };

    struct MatchEnd
    {
        uint64_t startFrame = 0, frame = 0;
        int winner = -1;          // 0 = P1, 1 = P2, -1 = draw
        int score[2] = {0, 0};
        int roundsToWin = 0;
        int code = 0;             // the game's own decision byte (1/2/3)
        bool consistent = false;  // wins and the game's decision byte agree
        int32_t chars[2] = {-1, -1};
        int32_t costumes[2] = {-1, -1};
        int32_t stage = -1;
        std::vector<Round> rounds;
    };

    inline uint32_t rd32(const uint8_t *rdram, uint32_t a)
    {
        uint32_t v;
        std::memcpy(&v, rdram + (a & 0x1ffffffu), 4);
        return v;
    }
    inline int16_t rd16(const uint8_t *rdram, uint32_t a)
    {
        int16_t v;
        std::memcpy(&v, rdram + (a & 0x1ffffffu), 2);
        return v;
    }

    // The VS select's result, copied into both player objects by FUN_0019d3e0 when the fight is set up: per side
    // u16 move-set fighter (0x357f78 -> +0x40), u16 fighter (0x357f7c -> +0x42) and u16 model = fighter * 4 + costume
    // (0x357f80 -> +0x48). The two fighter words differ only for Combot (18), who fights with another fighter's moves
    // (cb run: 0x357f78 = 13, 0x357f7c = 18, model 73); the fighter shown and reported is +0x42.
    constexpr uint32_t kSelFighter = 0x00357f7cu; // [2] u16
    constexpr uint32_t kSelModel = 0x00357f80u;   // [2] u16
    constexpr uint32_t kOffFighter = 0x42u;       // s16 in the player object (copy of kSelFighter[side])
    constexpr uint32_t kOffModel = 0x48u;         // s16 in the player object (copy of kSelModel[side])

    // The stage select's card (the profile block's cursor, left at the confirmed card for the fight): 0 AIRPORT,
    // 1 BUILDING, 2 MALL, 3 JUNGLE, 4 SHINJUKU, 5 BEACH, 6 LABORATORY, 7 PARKING AREA, 8 UNDERGROUND, 9 ARENA (the
    // order of the game's stage-name table at 0x2c8748), 10 = the random card: which stage the random card loads is
    // not known here, so the stage is reported only for cards 0..9.
    constexpr uint32_t kStageCard = 0x0036c490u;
    constexpr int kStageCards = 10;

    struct Selection
    {
        int32_t chars[2] = {-1, -1};
        int32_t costumes[2] = {-1, -1};
        int32_t stage = -1;
    };

    // Taken from the player objects (what the fight runs with); -1 where the copy disagrees with the select
    // screen's record or is out of range.
    inline Selection readSelection(const uint8_t *rdram)
    {
        Selection sel;
        for (int i = 0; i < 2; ++i)
        {
            const int fighter = rd16(rdram, kPlayerStatic[i] + kOffFighter);
            const int model = rd16(rdram, kPlayerStatic[i] + kOffModel);
            if (fighter >= 0 && fighter <= 18 && fighter == rd16(rdram, kSelFighter + 2u * i) && model / 4 == fighter &&
                model == rd16(rdram, kSelModel + 2u * i))
            {
                sel.chars[i] = fighter;
                sel.costumes[i] = model & 3;
            }
        }
        const uint32_t card = rd32(rdram, kStageCard);
        if (card < static_cast<uint32_t>(kStageCards))
            sel.stage = static_cast<int32_t>(card);
        return sel;
    }

    inline Sample read(uint64_t frame, const uint8_t *rdram)
    {
        Sample s;
        s.frame = frame;
        uint32_t p[2] = {rd32(rdram, kPlayerTable), rd32(rdram, kPlayerTable + 4u)};
        s.pointersOk = p[0] == kPlayerStatic[0] && p[1] == kPlayerStatic[1] &&
                       rd16(rdram, kPlayerStatic[0] + kOffSide) == 0 && rd16(rdram, kPlayerStatic[1] + kOffSide) == 1;
        for (int i = 0; i < 2; ++i)
        {
            s.wins[i] = rd16(rdram, kPlayerStatic[i] + kOffWins);
            s.roundResult[i] = rd16(rdram, kPlayerStatic[i] + kOffRoundResult);
            s.health[i] = static_cast<int32_t>(rd32(rdram, kPlayerStatic[i] + kOffHealth));
        }
        s.timer = static_cast<int32_t>(rd32(rdram, kRoundTimer));
        s.roundsToWin = rd32(rdram, kRoundsToWin);
        s.round = rd32(rdram, kRoundNumber);
        s.scene = static_cast<int32_t>(rd32(rdram, kScene));
        s.code = rdram[kMatchCode];
        s.winnerSide = rdram[kMatchWinnerSide];
        const Selection sel = readSelection(rdram);
        for (int i = 0; i < 2; ++i)
        {
            s.chars[i] = sel.chars[i];
            s.costumes[i] = sel.costumes[i];
        }
        s.stage = sel.stage;
        return s;
    }

    // A frame inside a match: the fight scene, plausible rules and counters.
    inline bool plausible(const Sample &s)
    {
        return s.pointersOk && s.scene == kSceneFight && s.roundsToWin >= 1u && s.roundsToWin <= 9u &&
               s.wins[0] >= 0 && s.wins[1] >= 0 && s.wins[0] <= 9 && s.wins[1] <= 9;
    }

    class Tracker
    {
    public:
        static constexpr size_t kRing = 1024; // far more than any rollback window (max prediction 8 + delay 4)

        // Every boundary visit, live or re-simulated: the newest visit of a frame wins.
        void observe(uint64_t frame, const uint8_t *rdram)
        {
            if (!rdram)
                return;
            ring_[frame % kRing] = read(frame, rdram);
        }

        // Frames up to `upto` are final. Returns true when a match ended in this call (endEvent() has it).
        bool confirm(uint64_t upto, FILE *log)
        {
            bool ended = false;
            if (next_ == 0)
                next_ = upto > kRing ? upto - kRing + 1u : 1u;
            for (; next_ <= upto; ++next_)
            {
                const Sample &s = ring_[next_ % kRing];
                if (s.frame != next_)
                {
                    ++gaps_;
                    havePrev_ = false;
                    continue;
                }
                ended |= step(s, log);
                prev_ = s;
                havePrev_ = true;
            }
            return ended;
        }

        bool hasEnd() const { return haveEnd_; }
        const MatchEnd &endEvent() const { return end_; }
        uint64_t matches() const { return matches_; }
        uint64_t gaps() const { return gaps_; }
        bool inMatch() const { return inMatch_; }

    private:
        static bool fresh(const Sample &s)
        {
            return plausible(s) && s.wins[0] == 0 && s.wins[1] == 0 && s.health[0] > 0 && s.health[1] > 0;
        }

        bool step(const Sample &s, FILE *log)
        {
            if (!inMatch_)
            {
                // A match starts on the first frame with fresh counters and both fighters alive after a frame
                // that was not like that (boot: no health yet; after a match: the winner's count stays until
                // the next match's set-up clears it).
                if (fresh(s) && havePrev_ && !fresh(prev_))
                {
                    inMatch_ = true;
                    cur_ = MatchEnd{};
                    cur_.startFrame = s.frame;
                    cur_.roundsToWin = static_cast<int>(s.roundsToWin);
                    for (int i = 0; i < 2; ++i)
                    {
                        cur_.chars[i] = s.chars[i];
                        cur_.costumes[i] = s.costumes[i];
                    }
                    cur_.stage = s.stage;
                    if (log)
                        std::fprintf(log, "MATCH start f=%" PRIu64 " rounds_to_win=%u chars=%d,%d stage=%d\n", s.frame,
                                     s.roundsToWin, s.chars[0], s.chars[1], s.stage);
                }
                return false;
            }
            if (!plausible(s))
            {
                if (log)
                    std::fprintf(log, "MATCH abandoned f=%" PRIu64 " (left the fight scene: scene %d)\n", s.frame,
                                 s.scene);
                inMatch_ = false;
                return false;
            }
            if (havePrev_ && (s.wins[0] != prev_.wins[0] || s.wins[1] != prev_.wins[1]))
            {
                if (s.wins[0] < prev_.wins[0] || s.wins[1] < prev_.wins[1])
                {
                    // counters went back without passing the target: a new match set-up (left mid-match)
                    if (log)
                        std::fprintf(log, "MATCH abandoned f=%" PRIu64 " (round wins reset %d-%d -> %d-%d)\n", s.frame,
                                     prev_.wins[0], prev_.wins[1], s.wins[0], s.wins[1]);
                    inMatch_ = false;
                    return false;
                }
                Round r;
                r.frame = s.frame;
                const bool p1 = s.wins[0] > prev_.wins[0], p2 = s.wins[1] > prev_.wins[1];
                r.winner = p1 && !p2 ? 0 : (p2 && !p1 ? 1 : -1);
                r.timeOut = s.timer <= 0;
                r.health[0] = s.health[0];
                r.health[1] = s.health[1];
                cur_.rounds.push_back(r);
                if (log)
                    std::fprintf(log, "MATCH round f=%" PRIu64 " n=%zu winner=%s by=%s health=%.2f,%.2f wins=%d-%d\n",
                                 s.frame, cur_.rounds.size(), r.winner == 0 ? "P1" : (r.winner == 1 ? "P2" : "draw"),
                                 r.timeOut ? "time" : "ko", s.health[0] / 65536.0, s.health[1] / 65536.0, s.wins[0],
                                 s.wins[1]);
                const int target = static_cast<int>(s.roundsToWin);
                if (s.wins[0] >= target || s.wins[1] >= target)
                {
                    cur_.frame = s.frame;
                    cur_.score[0] = s.wins[0];
                    cur_.score[1] = s.wins[1];
                    cur_.winner = s.wins[0] > s.wins[1] ? 0 : (s.wins[1] > s.wins[0] ? 1 : -1);
                    cur_.code = s.code;
                    cur_.consistent = (cur_.winner == 0 && s.code == 1u) || (cur_.winner == 1 && s.code == 2u) ||
                                      (cur_.winner == -1 && s.code == 3u);
                    // the fighters as they are at the deciding frame (the start's ids are a cross-check)
                    for (int i = 0; i < 2; ++i)
                        if (s.chars[i] >= 0)
                        {
                            cur_.chars[i] = s.chars[i];
                            cur_.costumes[i] = s.costumes[i];
                        }
                    if (s.stage >= 0)
                        cur_.stage = s.stage;
                    end_ = cur_;
                    haveEnd_ = true;
                    inMatch_ = false;
                    ++matches_;
                    if (log)
                        std::fprintf(log, "MATCHEND f=%" PRIu64 " winner=%s score=%d-%d code=%u consistent=%d chars=%d,%d"
                                          " stage=%d rounds=%zu start=%" PRIu64 "\n",
                                     s.frame, end_.winner == 0 ? "P1" : (end_.winner == 1 ? "P2" : "draw"),
                                     end_.score[0], end_.score[1], s.code, end_.consistent ? 1 : 0, end_.chars[0],
                                     end_.chars[1], end_.stage, end_.rounds.size(), end_.startFrame);
                    return true;
                }
            }
            return false;
        }

        Sample ring_[kRing];
        uint64_t next_ = 0, gaps_ = 0, matches_ = 0;
        Sample prev_;
        bool havePrev_ = false, inMatch_ = false, haveEnd_ = false;
        MatchEnd cur_, end_;
    };
}
