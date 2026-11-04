// Unit test of runtime/tekken4_match_state.h on synthetic RAM (no game data): rounds, KO / time-out, draw rounds,
// a predicted KO that a rollback removes before its frame is confirmed, an abandoned match, the fighter and stage
// reads, a second match. Built and run by tools/test_match_state.py.
#include "../runtime/tekken4_match_state.h"
#include "../runtime/tekken4_rounds.h"

#include <cstdio>
#include <cstring>
#include <vector>

namespace
{
    using namespace tekken4_match;
    int g_failures = 0;
#define CHECK(c)                                                                                                     \
    do                                                                                                               \
    {                                                                                                                \
        if (!(c))                                                                                                    \
        {                                                                                                            \
            std::printf("FAIL line %d: %s\n", __LINE__, #c);                                                         \
            ++g_failures;                                                                                            \
        }                                                                                                            \
    } while (0)

    struct Ram
    {
        std::vector<uint8_t> m = std::vector<uint8_t>(32u * 1024u * 1024u);
        void w32(uint32_t a, uint32_t v) { std::memcpy(&m[a], &v, 4); }
        void w16(uint32_t a, int16_t v) { std::memcpy(&m[a], &v, 2); }
        Ram()
        {
            w32(kPlayerTable, kPlayerStatic[0]);
            w32(kPlayerTable + 4, kPlayerStatic[1]);
            w16(kPlayerStatic[0] + kOffSide, 0);
            w16(kPlayerStatic[1] + kOffSide, 1);
            w32(kRoundsToWin, 2);
            w32(kStageCard, 10);
        }
        void scene(int s) { w32(kScene, static_cast<uint32_t>(s)); }
        void health(int p1, int p2)
        {
            w32(kPlayerStatic[0] + kOffHealth, static_cast<uint32_t>(p1 << 16));
            w32(kPlayerStatic[1] + kOffHealth, static_cast<uint32_t>(p2 << 16));
        }
        void wins(int a, int b)
        {
            w16(kPlayerStatic[0] + kOffWins, static_cast<int16_t>(a));
            w16(kPlayerStatic[1] + kOffWins, static_cast<int16_t>(b));
        }
        void fighters(int a, int b, int costumeA = 1, int costumeB = 1)
        {
            const int f[2] = {a, b}, c[2] = {costumeA, costumeB};
            for (int i = 0; i < 2; ++i)
            {
                w16(kSelFighter + 2 * i, static_cast<int16_t>(f[i]));
                w16(kSelModel + 2 * i, static_cast<int16_t>(f[i] * 4 + c[i]));
                w16(kPlayerStatic[i] + kOffFighter, static_cast<int16_t>(f[i]));
                w16(kPlayerStatic[i] + kOffModel, static_cast<int16_t>(f[i] * 4 + c[i]));
            }
        }
        void timer(int t) { w32(kRoundTimer, static_cast<uint32_t>(t)); }
        void code(int c) { m[kMatchCode] = static_cast<uint8_t>(c); }
    };

    // One live frame: sample and confirm at once (offline).
    void live(Tracker &t, Ram &r, uint64_t &f)
    {
        ++f;
        t.observe(f, r.m.data());
        t.confirm(f, nullptr);
    }

    void select_then_fight(Tracker &t, Ram &r, uint64_t &f, int a, int b, int card)
    {
        r.scene(7);
        r.health(0, 0);
        for (int i = 0; i < 5; ++i)
            live(t, r, f);
        r.scene(4);
        r.fighters(a, b);
        r.w32(kStageCard, static_cast<uint32_t>(card));
        r.wins(0, 0);
        r.health(165, 165);
        r.timer(3600);
        live(t, r, f);
    }

    void test_two_rounds_ko_and_time()
    {
        Ram r;
        Tracker t;
        uint64_t f = 0;
        select_then_fight(t, r, f, 14, 0, 8);
        CHECK(t.inMatch());
        r.health(165, 0); // KO
        r.timer(1200);
        r.wins(1, 0);
        live(t, r, f);
        r.health(165, 165); // round 2
        r.timer(3600);
        live(t, r, f);
        r.health(120, 100); // time-out, P1 more health
        r.timer(0);
        r.wins(2, 0);
        r.code(1);
        live(t, r, f);
        CHECK(t.hasEnd());
        const MatchEnd &e = t.endEvent();
        CHECK(e.winner == 0 && e.score[0] == 2 && e.score[1] == 0 && e.consistent);
        CHECK(e.chars[0] == 14 && e.chars[1] == 0 && e.costumes[0] == 1 && e.stage == 8);
        CHECK(e.rounds.size() == 2 && !e.rounds[0].timeOut && e.rounds[1].timeOut && e.rounds[1].winner == 0);
    }

    void test_draw_match_and_combot()
    {
        Ram r;
        Tracker t;
        uint64_t f = 0;
        select_then_fight(t, r, f, 3, 18, 10);
        r.w16(kSelFighter - 4 + 2, 13); // Combot's move-set word (0x357f78 side 2) is not what is read
        r.timer(0);
        r.wins(1, 1); // equal health at time-out: both
        live(t, r, f);
        r.timer(3600);
        live(t, r, f);
        r.timer(0);
        r.wins(2, 2);
        r.code(3);
        live(t, r, f);
        CHECK(t.hasEnd());
        const MatchEnd &e = t.endEvent();
        CHECK(e.winner == -1 && e.score[0] == 2 && e.score[1] == 2 && e.consistent);
        CHECK(e.rounds.size() == 2 && e.rounds[0].winner == -1);
        CHECK(e.chars[1] == 18 && e.stage == -1); // the random card: no stage
    }

    void test_inconsistent_code_is_not_consistent()
    {
        Ram r;
        Tracker t;
        uint64_t f = 0;
        select_then_fight(t, r, f, 1, 2, 0);
        r.wins(2, 0);
        r.code(2); // the game's decision byte says P2: never call that proven
        live(t, r, f);
        CHECK(t.hasEnd() && !t.endEvent().consistent);
    }

    void test_predicted_ko_rolled_back()
    {
        // Netplay: frames are observed when visited and confirmed later. A KO seen on a predicted frame and then
        // re-simulated without it must not end the round.
        Ram r;
        Tracker t;
        uint64_t f = 0;
        select_then_fight(t, r, f, 9, 8, 5); // frames 1..6, confirmed
        const uint64_t base = f;
        r.health(165, 0);
        r.wins(1, 0);
        t.observe(base + 1, r.m.data()); // predicted: P2 KO
        r.wins(2, 0);
        r.code(1);
        t.observe(base + 2, r.m.data());
        t.confirm(base, nullptr);        // only up to the last confirmed frame
        CHECK(!t.hasEnd() && t.inMatch());
        r.health(165, 140); // rollback: corrected frames have no KO
        r.wins(0, 0);
        r.code(0);
        t.observe(base + 1, r.m.data());
        t.observe(base + 2, r.m.data());
        t.confirm(base + 2, nullptr);
        CHECK(!t.hasEnd() && t.inMatch());
    }

    void test_negotiated_rounds_and_first_to_three()
    {
        using tekken4_rounds::parse;
        CHECK(parse(nullptr).valid && parse(nullptr).value == 0);
        CHECK(parse("").valid && parse("").value == 0);
        for (const char *s : {"1", "2", "3", "4", "5"})
            CHECK(parse(s).valid && parse(s).value == static_cast<uint32_t>(s[0] - '0'));
        for (const char *s : {"0", "6", "-1", "3x", "3 ", " 3", "+3", "03", "999999999999999999"})
            CHECK(!parse(s).valid);
        const auto hash = tekken4_rounds::fingerprint(42, parse("3"));
        CHECK(hash == tekken4_rounds::fingerprint(42, parse("3")));
        CHECK(hash != tekken4_rounds::fingerprint(42, parse("2")));
        CHECK(tekken4_rounds::fingerprint(0, parse("2")) != tekken4_rounds::fingerprint(0, parse(nullptr)));

        Ram r;
        Tracker t;
        uint64_t f = 0;
        r.w32(kRoundsToWin, 3);
        select_then_fight(t, r, f, 14, 0, 9);
        r.wins(1, 0);
        live(t, r, f);
        r.wins(2, 0);
        live(t, r, f);
        CHECK(t.inMatch() && !t.hasEnd());
        // A predicted third win must disappear when the frame is replayed with corrected input.
        r.wins(3, 0);
        r.code(1);
        t.observe(f + 1, r.m.data());
        r.wins(2, 0);
        r.code(0);
        t.observe(f + 1, r.m.data());
        t.confirm(++f, nullptr);
        CHECK(!t.hasEnd());
        r.wins(2, 1);
        live(t, r, f);
        r.wins(3, 1);
        r.code(1);
        live(t, r, f);
        CHECK(t.hasEnd());
        const auto &end = t.endEvent();
        CHECK(end.consistent && end.winner == 0 && end.score[0] == 3 && end.score[1] == 1);
        CHECK(end.roundsToWin == 3 && end.rounds.size() == 4);
    }

    void test_abandoned_and_second_match()
    {
        Ram r;
        Tracker t;
        uint64_t f = 0;
        select_then_fight(t, r, f, 4, 5, 1);
        r.wins(1, 0);
        live(t, r, f);
        r.scene(7); // back to the select before the end (pause menu): no result
        live(t, r, f);
        CHECK(!t.inMatch() && !t.hasEnd());
        select_then_fight(t, r, f, 6, 7, 2);
        CHECK(t.inMatch());
        r.wins(0, 2);
        r.code(2);
        live(t, r, f);
        CHECK(t.hasEnd() && t.endEvent().winner == 1 && t.endEvent().chars[0] == 6 && t.endEvent().stage == 2);
        CHECK(t.matches() == 1);
        // the stale wins after the match never start a match; the next fight's fresh counters do
        r.scene(7);
        live(t, r, f);
        CHECK(!t.inMatch());
        select_then_fight(t, r, f, 0, 0, 9);
        CHECK(t.inMatch());
    }
}

int main()
{
    test_two_rounds_ko_and_time();
    test_draw_match_and_combot();
    test_inconsistent_code_is_not_consistent();
    test_predicted_ko_rolled_back();
    test_abandoned_and_second_match();
    test_negotiated_rounds_and_first_to_three();
    if (g_failures)
    {
        std::printf("%d failure(s)\n", g_failures);
        return 1;
    }
    std::printf("match_state_test: all passed\n");
    return 0;
}
