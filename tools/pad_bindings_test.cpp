// Tests runtime/ps2_pad_bindings.h (patch 100, ps2xRuntime/include/runtime/ps2_pad_bindings.h) on its own: the file
// parser, the default layout against a copy of the old fixed code (patch 60 fromXInput, patch 31 asyncPadMask),
// the mapping of XInput samples and keys, and the live reload. No game, no window, no pad.
// tools/test_pad_bindings.py extracts the header from the patch and builds this.
#include "runtime/ps2_pad_bindings.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <chrono>
#include <random>
#include <set>
#include <thread>

namespace pb = ps2_pad_bindings;

static int g_failed = 0;
static int g_checks = 0;
#define CHECK(cond) ((void)(++g_checks), (cond) ? (void)0 : (void)(++g_failed, std::printf("FAIL line %d: %s\n", __LINE__, #cond)))

namespace
{
    // PS2 bits as patch 60 names them.
    constexpr uint16_t kSelect = 0x0001u, kL3 = 0x0002u, kR3 = 0x0004u, kStart = 0x0008u, kUp = 0x0010u,
                       kRight = 0x0020u, kDown = 0x0040u, kLeft = 0x0080u, kL2 = 0x0100u, kR2 = 0x0200u,
                       kL1 = 0x0400u, kR1 = 0x0800u, kTriangle = 0x1000u, kCircle = 0x2000u, kCross = 0x4000u,
                       kSquare = 0x8000u;

    // ---- the OLD fixed layout, copied from patch 60 (ps2_host_pad.cpp) ----
    float oldNorm(int16_t v) { return std::min(1.0f, std::max(-1.0f, static_cast<float>(v) / 32767.0f)); }

    uint16_t oldStickDirs(float x, float y, uint16_t prev)
    {
        uint16_t d = 0;
        const auto on = [prev](float v, uint16_t bit) { return v > 0.5f || ((prev & bit) != 0 && v > 0.4f); };
        if (on(-x, kLeft))
            d |= kLeft;
        if (on(x, kRight))
            d |= kRight;
        if (on(-y, kUp))
            d |= kUp;
        if (on(y, kDown))
            d |= kDown;
        return d;
    }

    uint16_t oldButtons(const pb::RawPad &g, bool stickDpad, uint16_t &dirs)
    {
        const uint16_t w = g.buttons;
        uint16_t b = 0;
        if (w & 0x0001) b |= kUp;
        if (w & 0x0002) b |= kDown;
        if (w & 0x0004) b |= kLeft;
        if (w & 0x0008) b |= kRight;
        if (w & 0x0010) b |= kStart;
        if (w & 0x0020) b |= kSelect;
        if (w & 0x0040) b |= kL3;
        if (w & 0x0080) b |= kR3;
        if (w & 0x0100) b |= kL1;
        if (w & 0x0200) b |= kR1;
        if (w & 0x1000) b |= kCross;
        if (w & 0x2000) b |= kCircle;
        if (w & 0x4000) b |= kSquare;
        if (w & 0x8000) b |= kTriangle;
        if (g.lt > 30) b |= kL2;
        if (g.rt > 30) b |= kR2;
        const float lx = oldNorm(g.lx), ly = -oldNorm(g.ly);
        if (stickDpad)
        {
            dirs = oldStickDirs(lx, ly, dirs);
            b |= dirs;
        }
        return b;
    }

    // ---- the OLD keyboard, copied from patch 31 (ps2_input_latency.cpp asyncPadMask) ----
    uint16_t oldKeys(const std::set<int> &down)
    {
        const auto d = [&down](int vk) { return down.count(vk) != 0; };
        uint16_t m = 0;
        if (d('W')) m |= kUp;
        if (d('S')) m |= kDown;
        if (d('A')) m |= kLeft;
        if (d('D')) m |= kRight;
        if (d(0x28) || d('X') || d(0x20)) m |= kCross;
        if (d(0x27) || d('C') || d(0x1B)) m |= kCircle;
        if (d(0x25) || d('Z') || d(0x60)) m |= kSquare;
        if (d(0x26) || d('V') || d(0x61)) m |= kTriangle;
        if (d('Q')) m |= kL1;
        if (d('E')) m |= kR1;
        if (d(0xA0)) m |= kL2;
        if (d(0xA1)) m |= kR2;
        if (d(0x0D)) m |= kStart;
        if (d(0x09)) m |= kSelect;
        return m;
    }

    uint16_t mapKeys(const pb::KeyMap &m, int player, const std::set<int> &down)
    {
        uint16_t out = 0;
        for (const auto &kb : pb::flatKeys(m, player))
            if (down.count(kb.first))
                out = static_cast<uint16_t>(out | kb.second);
        return out;
    }

    pb::RawPad pad(uint16_t buttons, uint8_t lt = 0, uint8_t rt = 0, int16_t lx = 0, int16_t ly = 0, int16_t rx = 0,
                   int16_t ry = 0)
    {
        pb::RawPad r;
        r.buttons = buttons;
        r.lt = lt;
        r.rt = rt;
        r.lx = lx;
        r.ly = ly;
        r.rx = rx;
        r.ry = ry;
        return r;
    }

    uint16_t eval(const pb::PadMap &m, const pb::RawPad &r, bool stickDpad = true)
    {
        uint32_t axis = 0;
        return pb::evalPad(m, r, stickDpad, axis);
    }

    void testDefaultPadEqualsOldCode()
    {
        std::mt19937 rng(7);
        for (int stickDpad = 0; stickDpad < 2; ++stickDpad)
        {
            pb::PadMap fixedMap; // nothing set: every button default
            uint16_t dirs = 0;
            uint32_t axis = 0;
            int diffs = 0;
            for (int i = 0; i < 200000; ++i)
            {
                pb::RawPad r;
                // Buttons: any of the 14 XInput bits; sticks drift slowly so the hysteresis is exercised.
                r.buttons = static_cast<uint16_t>(rng() & 0xF3FF);
                r.lt = static_cast<uint8_t>(rng() % 3 == 0 ? rng() % 256 : 0);
                r.rt = static_cast<uint8_t>(rng() % 3 == 0 ? rng() % 256 : 0);
                const auto drift = [&rng](int16_t v) {
                    const int step = static_cast<int>(rng() % 20001) - 10000;
                    return static_cast<int16_t>(std::max(-32768, std::min(32767, v + step)));
                };
                static int16_t lx = 0, ly = 0, rx = 0, ry = 0;
                lx = drift(lx);
                ly = drift(ly);
                rx = drift(rx);
                ry = drift(ry);
                r.lx = lx;
                r.ly = ly;
                r.rx = rx;
                r.ry = ry;
                const uint16_t want = oldButtons(r, stickDpad != 0, dirs);
                const uint16_t got = pb::evalPad(fixedMap, r, stickDpad != 0, axis);
                diffs += want != got;
            }
            CHECK(diffs == 0);
        }
    }

    void testDefaultKeysEqualOldCode()
    {
        pb::KeyMap none;
        std::mt19937 rng(11);
        const int pool[] = {'W', 'S', 'A', 'D', 'X', 'C', 'Z', 'V', 'Q', 'E', 0x28, 0x27, 0x25, 0x26, 0x20, 0x1B, 0x60,
                            0x61, 0xA0, 0xA1, 0x0D, 0x09, 'P', 'K', 0x70, 0xA2};
        int diffs = 0;
        for (int i = 0; i < 100000; ++i)
        {
            std::set<int> down;
            for (int v : pool)
                if (rng() % 4 == 0)
                    down.insert(v);
            diffs += oldKeys(down) != mapKeys(none, 0, down);
            diffs += mapKeys(none, 1, down) != 0; // player 2 has no default keys
        }
        CHECK(diffs == 0);
    }

    void testDefaultFiles()
    {
        CHECK(pb::parse("").isDefault());
        CHECK(pb::parse("; only a comment\r\n# another\r\n").isDefault());
        CHECK(pb::parse("[player1]\ndevice = auto\n[player2]\ndevice = AUTO\n").isDefault());
        CHECK(pb::parse("\xEF\xBB\xBF[player1]\r\ndevice = auto ; the usual\r\n").isDefault());
        CHECK(pb::parse("[general]\nwhatever = 1\n").isDefault());
        CHECK(!pb::parse("[player1.pad]\nSQUARE = A\n").isDefault());
        CHECK(!pb::parse("[player2.keys]\n1 = U\n").isDefault());
        CHECK(!pb::parse("[player1]\ndevice = keyboard\n").isDefault());
        // A section with no binding line changes nothing.
        CHECK(pb::parse("[player1.pad]\n[player1.keys]\n[player2.pad]\n").isDefault());
        // Garbage keeps the default and says so.
        std::vector<std::string> warn;
        const pb::Config junk = pb::parse("[player1]\ndevice = banana\nfoo\n[nonsense]\n[player1.pad]\nBOGUS = A\nSQUARE = ZZ\n", &warn);
        CHECK(junk.isDefault() == false); // SQUARE was listed (to nothing): that is a binding, see below
        CHECK(warn.size() >= 4);
        CHECK(junk.p[0].autoDevice);
    }

    void testDevices()
    {
        pb::Config c = pb::parse("[player1]\ndevice = keyboard+xinput:2\n[player2]\ndevice = xinput:0\n");
        CHECK(!c.p[0].autoDevice && c.p[0].keyboard && c.p[0].pad && c.p[0].xslot == 2);
        CHECK(!c.p[1].autoDevice && !c.p[1].keyboard && c.p[1].pad && c.p[1].xslot == 0);
        CHECK(c.pinnedMask() == 0x5u);
        c = pb::parse("[player1]\ndevice = none\n[player2]\ndevice = keyboard\n");
        CHECK(!c.p[0].keyboard && !c.p[0].pad);
        CHECK(c.p[1].keyboard && !c.p[1].pad);
        c = pb::parse("[player1]\ndevice = xinput\n[player2]\ndevice = auto + keyboard\n");
        CHECK(!c.p[0].keyboard && c.p[0].pad && c.p[0].xslot == -1);
        CHECK(c.p[1].autoDevice && !c.p[1].keyboard && c.p[1].pad); // auto swallows the rest
        c = pb::parse("[player1]\ndevice = xinput:9\n"); // not a slot: ignored, stays auto
        CHECK(c.p[0].autoDevice);
        c = pb::parse("[PLAYER2]\nDevice=Keyboard , XInput:3\n");
        CHECK(c.p[1].keyboard && c.p[1].xslot == 3);
    }

    void testBindingLines()
    {
        std::vector<std::string> warn;
        pb::Config c = pb::parse(
            "[player1.pad]\n"
            "1 = x lb\n"          // Tekken name, two sources, lower case
            "cross = NONE\n"      // listed, unbound
            "L2 = RT\n"
            "UP = DUP, LUP RUP\n" // commas, three sources
            "R1 = A A\n"          // duplicate dropped
            "circle = \n"         // listed, empty = unbound
            "[player1.keys]\n"
            "SQUARE = left z numpad\n" // NUMPAD is not a key name: warned, the rest kept
            "RP = F5\n",
            &warn);
        const pb::PadMap &pm = c.p[0].padMap;
        CHECK(pm.set[pb::B_SQUARE] && pm.src[pb::B_SQUARE].size() == 2);
        CHECK(pm.set[pb::B_CROSS] && pm.src[pb::B_CROSS].empty());
        CHECK(pm.set[pb::B_CIRCLE] && pm.src[pb::B_CIRCLE].empty());
        CHECK(pm.set[pb::B_L2] && pm.src[pb::B_L2].size() == 1 && pm.src[pb::B_L2][0].kind == pb::SK_RT);
        CHECK(pm.set[pb::B_UP] && pm.src[pb::B_UP].size() == 3);
        CHECK(pm.src[pb::B_R1].size() == 1);
        CHECK(!pm.set[pb::B_TRIANGLE] && !pm.set[pb::B_START]);
        const pb::KeyMap &km = c.p[0].keyMap;
        CHECK(km.set[pb::B_SQUARE] && km.vk[pb::B_SQUARE].size() == 2);
        CHECK(km.set[pb::B_TRIANGLE] && km.vk[pb::B_TRIANGLE].size() == 1 && km.vk[pb::B_TRIANGLE][0] == 0x74);
        CHECK(warn.size() == 1);
    }

    void testPadMapping()
    {
        pb::Config c = pb::parse(
            "[player1.pad]\n"
            "1 = X LB\n"
            "CROSS = NONE\n"
            "L2 = RT\n"
            "UP = DUP\n");
        const pb::PadMap &m = c.p[0].padMap;
        // X presses Square; the default Square source (X) is replaced, so Y is still Triangle
        CHECK(eval(m, pad(0x4000)) == kSquare);
        CHECK(eval(m, pad(0x8000)) == kTriangle);
        // LB: Square (listed) AND L1 (default of L1 is LB, not listed here)
        CHECK(eval(m, pad(0x0100)) == (kSquare | kL1));
        // A no longer presses Cross
        CHECK(eval(m, pad(0x1000)) == 0);
        // RT -> L2 only; the default R2 (RT) still there
        CHECK(eval(m, pad(0, 0, 255)) == (kL2 | kR2));
        CHECK(eval(m, pad(0, 30, 0)) == 0);     // LT at the threshold is not pressed; L2 no longer listens to LT
        CHECK(eval(m, pad(0, 255, 0)) == 0);
        // UP = DUP: the stick up no longer presses Up, the d-pad does; Down still has the stick (default)
        CHECK(eval(m, pad(0x0001)) == kUp);
        CHECK(eval(m, pad(0, 0, 0, 0, 32767)) == 0);   // stick up
        CHECK(eval(m, pad(0, 0, 0, 0, -32767)) == kDown); // stick down
        // an axis source: R stick right presses Circle
        const pb::Config d = pb::parse("[player1.pad]\nCIRCLE = RRIGHT B\n");
        CHECK(eval(d.p[0].padMap, pad(0, 0, 0, 0, 0, 32000)) == kCircle);
        CHECK(eval(d.p[0].padMap, pad(0x2000)) == kCircle);
        CHECK(eval(d.p[0].padMap, pad(0, 0, 0, 0, 0, 12000)) == 0); // 0.37 < 0.5
        // hysteresis: on at 0.6, stays on at 0.45, off at 0.35
        uint32_t axis = 0;
        CHECK(pb::evalPad(d.p[0].padMap, pad(0, 0, 0, 0, 0, 19661), true, axis) == kCircle);
        CHECK(pb::evalPad(d.p[0].padMap, pad(0, 0, 0, 0, 0, 14746), true, axis) == kCircle);
        CHECK(pb::evalPad(d.p[0].padMap, pad(0, 0, 0, 0, 0, 11469), true, axis) == 0);
        // TEKKEN4_PAD_STICK_DPAD=0 only takes the stick out of the default d-pad, not out of a listed source
        const pb::Config e = pb::parse("[player1.pad]\nSQUARE = LLEFT\n");
        CHECK(eval(e.p[0].padMap, pad(0, 0, 0, -32767), false) == kSquare);
        CHECK(eval(e.p[0].padMap, pad(0, 0, 0, -32767), false) == kSquare);
        CHECK(eval(e.p[0].padMap, pad(0, 0, 0, 0, 32767), false) == 0);
        // the same Tekken layout in a row: X Y RB RT for 1 2 3 4
        const pb::Config row = pb::parse("[player1.pad]\n1 = X\n2 = Y\n3 = RB\n4 = RT\nL1 = LB\nR1 = A\nR2 = B\nL2 = LT\n");
        CHECK(eval(row.p[0].padMap, pad(0x0200)) == kCross);
        CHECK(eval(row.p[0].padMap, pad(0, 0, 255)) == kCircle);
        CHECK(eval(row.p[0].padMap, pad(0x1000)) == kR1);
        CHECK(eval(row.p[0].padMap, pad(0x2000)) == kR2);
    }

    void testKeyMapping()
    {
        const pb::Config c = pb::parse(
            "[player1.keys]\n"
            "SQUARE = U\n"
            "UP = I\n"
            "CROSS = NONE\n"
            "[player2]\ndevice = keyboard\n"
            "[player2.keys]\n"
            "1 = NUM4\nSTART = NUMADD\n");
        const pb::KeyMap &k1 = c.p[0].keyMap;
        CHECK(mapKeys(k1, 0, {'U'}) == kSquare);
        CHECK(mapKeys(k1, 0, {0x25}) == 0);          // LEFT arrow was a default Square key; now only U
        CHECK(mapKeys(k1, 0, {'I'}) == kUp);
        CHECK(mapKeys(k1, 0, {'W'}) == 0);           // W was Up
        CHECK(mapKeys(k1, 0, {'X'}) == 0 && mapKeys(k1, 0, {0x28}) == 0); // Cross unbound
        CHECK(mapKeys(k1, 0, {'Q', 'E'}) == (kL1 | kR1)); // unlisted buttons keep their keys
        CHECK(mapKeys(k1, 0, {0x0D}) == kStart);
        const pb::KeyMap &k2 = c.p[1].keyMap;
        CHECK(mapKeys(k2, 1, {0x64}) == kSquare);
        CHECK(mapKeys(k2, 1, {0x6B}) == kStart);
        CHECK(mapKeys(k2, 1, {'W', 'Q', 0x0D}) == 0); // player 2 has no other key
        CHECK(c.p[1].keyboard && !c.p[1].pad);
    }

    void testNames()
    {
        for (int b = 0; b < pb::kButtons; ++b)
            CHECK(pb::buttonIndex(pb::kButtonNames[b]) == b);
        CHECK(pb::buttonIndex("1") == pb::B_SQUARE && pb::buttonIndex("LP") == pb::B_SQUARE);
        CHECK(pb::buttonIndex("2") == pb::B_TRIANGLE && pb::buttonIndex("rp") == pb::B_TRIANGLE);
        CHECK(pb::buttonIndex("3") == pb::B_CROSS && pb::buttonIndex("LK") == pb::B_CROSS);
        CHECK(pb::buttonIndex("4") == pb::B_CIRCLE && pb::buttonIndex("RK") == pb::B_CIRCLE);
        CHECK(pb::buttonIndex("5") == -1 && pb::buttonIndex("") == -1);
        // bit i of the pad word is button i
        CHECK((1u << pb::B_SELECT) == kSelect && (1u << pb::B_START) == kStart && (1u << pb::B_UP) == kUp &&
              (1u << pb::B_LEFT) == kLeft && (1u << pb::B_L2) == kL2 && (1u << pb::B_R1) == kR1 &&
              (1u << pb::B_TRIANGLE) == kTriangle && (1u << pb::B_SQUARE) == kSquare);
        for (const pb::NamedButton &b : pb::kXButtons)
        {
            pb::Src s;
            CHECK(pb::parsePadSource(b.name, s) && s.kind == pb::SK_BUTTON && s.arg == b.mask);
            CHECK(pb::padSourceName(s) == b.name);
        }
        for (int i = 0; i < 8; ++i)
        {
            pb::Src s;
            CHECK(pb::parsePadSource(pb::kAxisNames[i], s) && s.kind == pb::SK_AXIS && s.arg == i);
        }
        for (const pb::NamedKey &k : pb::kKeyNames)
            CHECK(pb::parseKey(k.name) == k.vk);
        for (char ch = 'A'; ch <= 'Z'; ++ch)
            CHECK(pb::parseKey(std::string(1, ch)) == static_cast<uint16_t>(ch) && pb::keyName(static_cast<uint16_t>(ch)) == std::string(1, ch));
        for (char ch = '0'; ch <= '9'; ++ch)
            CHECK(pb::parseKey(std::string(1, ch)) == static_cast<uint16_t>(ch));
        CHECK(pb::parseKey("a") == 'A' && pb::parseKey("Enter") == 0x0D && pb::parseKey("nope") == 0);
        CHECK(pb::keyName(0x0D) == "ENTER" && pb::keyName(0xDE) == "APOSTROPHE" && pb::keyName(0x1B) == "ESC");
    }

    // The same text and expectations as the launcher's tests/test_t4_controls_ini.py (GOLDEN): both parsers agree.
    void testGolden()
    {
        std::vector<std::string> warn;
        const pb::Config c = pb::parse(R"INI(; a comment
[player1]
device = keyboard+xinput:2
[player1.pad]
1 = x lb
CROSS = NONE
L2 = RT
UP = DUP, LUP RUP
[player1.keys]
SQUARE = left z
RP = F5
[player2]
device = xinput:0
[player2.keys]
1 = NUM4
)INI",
                                       &warn);
        CHECK(warn.empty());
        CHECK(c.p[0].keyboard && c.p[0].pad && c.p[0].xslot == 2);
        CHECK(!c.p[1].keyboard && c.p[1].pad && c.p[1].xslot == 0);
        const pb::PadMap &pm = c.p[0].padMap;
        CHECK(pm.src[pb::B_SQUARE].size() == 2 && pm.src[pb::B_SQUARE][0].arg == pb::X_X && pm.src[pb::B_SQUARE][1].arg == pb::X_LB);
        CHECK(pm.set[pb::B_CROSS] && pm.src[pb::B_CROSS].empty());
        CHECK(pm.src[pb::B_L2].size() == 1 && pm.src[pb::B_L2][0].kind == pb::SK_RT);
        CHECK(pm.src[pb::B_UP].size() == 3);
        CHECK(!pm.set[pb::B_TRIANGLE]);
        CHECK(mapKeys(c.p[0].keyMap, 0, {0x25}) == kSquare && mapKeys(c.p[0].keyMap, 0, {0x60}) == 0);
        CHECK(mapKeys(c.p[0].keyMap, 0, {0x74}) == kTriangle);
        CHECK(mapKeys(c.p[0].keyMap, 0, {'Q'}) == kL1);
        CHECK(mapKeys(c.p[1].keyMap, 1, {0x64}) == kSquare);
        CHECK(mapKeys(c.p[1].keyMap, 1, {'Q'}) == 0);
    }

    void writeFile(const std::string &path, const std::string &text)
    {
        std::ofstream f(path, std::ios::binary | std::ios::trunc);
        f << text;
    }

    void testLiveReload(const std::string &dir)
    {
        const std::string path = dir + "/controls_live.ini";
        std::remove(path.c_str());
        pb::useFileForTest(path, 10);
        CHECK(pb::current()->isDefault()); // no file
        writeFile(path, "[player1.keys]\nSQUARE = U\n");
        bool changed = false;
        for (int i = 0; i < 200 && !changed; ++i)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            changed = !pb::current()->isDefault();
        }
        CHECK(changed);
        CHECK(pb::current()->p[0].keyMap.set[pb::B_SQUARE]);
        // a different file of the same size within the same timestamp tick is still noticed through size or time
        writeFile(path, "[player1.keys]\nSQUARE = U\nTRIANGLE = I\n");
        bool second = false;
        for (int i = 0; i < 200 && !second; ++i)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            second = pb::current()->p[0].keyMap.set[pb::B_TRIANGLE];
        }
        CHECK(second);
        std::remove(path.c_str());
        bool back = false;
        for (int i = 0; i < 200 && !back; ++i)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            back = pb::current()->isDefault();
        }
        CHECK(back);
        // another thread sees the same current config
        std::shared_ptr<const pb::Config> other;
        writeFile(path, "[player2]\ndevice = none\n");
        for (int i = 0; i < 200; ++i)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            if (!pb::current()->isDefault())
                break;
        }
        std::thread t([&other] { other = pb::current(); });
        t.join();
        CHECK(other && !other->p[1].pad && !other->p[1].keyboard);
        std::remove(path.c_str());
    }
}

int main(int argc, char **argv)
{
    const std::string dir = argc > 1 ? argv[1] : ".";
    testNames();
    testGolden();
    testDefaultFiles();
    testDevices();
    testBindingLines();
    testPadMapping();
    testKeyMapping();
    testDefaultPadEqualsOldCode();
    testDefaultKeysEqualOldCode();
    testLiveReload(dir);
    std::printf("%d checks, %d failed\n", g_checks, g_failed);
    if (g_failed == 0)
        std::printf("all passed\n");
    return g_failed == 0 ? 0 : 1;
}
