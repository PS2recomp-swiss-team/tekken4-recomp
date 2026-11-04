// Tekken 4 (SLUS-20328, NTSC-U v1.00): the online players' NAME PLATES -- who plays which side, with their lobby name
// and T4 rank badge (Tekken 7's rank names, our own badge drawing: tekken4_rank_badges.h). docs/T4_RANKED.md.
//
// Drawn by the presenter over the game's picture (patch 88, ps2_host_overlay.h): host-only, it only READS guest RAM
// (the scene manager and the fight's player objects) and never writes it, so online state hashes, rollback and
// replays are the same with and without the plates.
//
//   TEKKEN4_HUD_NAMES   "<P1 name>|<P2 name>"   the lobby's names, P1 = the host's side (the launcher passes them;
//                                               unset = no plates, e.g. offline play)
//   TEKKEN4_HUD_RANKS   "<P1 tier>,<P2 tier>"   T4 rank tiers 0..46 (t4lobby/ranks.py); -1 or empty = no badge (guest,
//                                               casual without a rank)
//   TEKKEN4_HUD_PLATES  0                       off (the launcher's setting "Name plates in the game")
//   TEKKEN4_HUD_SHOTS   <s>[,<s>...]            test hook: the WINDOW (picture + plates) saved as hud_<s>s.png in
//                                               the working directory at those seconds after start
//   TEKKEN4_HUD_WINDOW  <w>x<h>                 test hook: the window's size (pictures at 1280x896 etc.)
//
// Where: VS character select (scene 7, game type 3 VS Battle -- t4autovs's scene record) under each side's preview
// (P1 left, P2 right), and in the fight (scene 4 with a round running) under each life bar's fighter name.
#include "game_overrides.h"
#include "ps2_host_overlay.h"
#include "ps2_log.h"
#include "ps2_runtime.h"
#include "raylib.h"
#include "rlgl.h"
#include "tekken4_rank_badges.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

namespace tekken4_hud
{
    // ---- guest addresses (physical RDRAM), SLUS-20328 v1.00 (docs/MATCH_RESULT_T4.md, docs/DIRECTFIGHT_T4.md)
    constexpr uint32_t kScene = 0x00357d38u;       // current scene: 7 VS character select, 4 the fight
    constexpr uint32_t kGameType = 0x002a8bf8u;    // 3 = VS Battle
    constexpr uint32_t kPlayerTable = 0x002a9420u; // two pointers P1, P2 (player objects, stride 0xF20)
    constexpr uint32_t kOffHealth = 0x6bcu;        // s32 16.16, 165.0 full
    constexpr uint32_t kRoundTimer = 0x00356064u;  // s32 frames left
    constexpr uint32_t kRoundNumber = 0x00356078u; // u32, 1-based
    constexpr int kSceneSelect = 7, kSceneFight = 4, kTypeVs = 3;

    struct Side
    {
        std::string name;
        int tier = -1;
    };

    struct State
    {
        Side side[2];
        bool fontTried = false;
        Font font{};
        bool fontOwn = false;
        std::vector<double> shots;
        size_t nextShot = 0;
        std::chrono::steady_clock::time_point start;
    };
    State g;

    uint32_t rd32(const uint8_t *rdram, uint32_t a)
    {
        uint32_t v;
        std::memcpy(&v, rdram + (a & 0x1ffffffu), 4);
        return v;
    }

    // Lobby names are shown as typed, but the font has ASCII only (and '|' separates the two).
    std::string clean(const std::string &s)
    {
        std::string out;
        for (unsigned char c : s)
        {
            if (out.size() >= 16)
                break;
            if (c >= 0x20 && c < 0x7f)
                out.push_back(static_cast<char>(c));
            else if (c >= 0xc0)
                out.push_back('?'); // the start of a UTF-8 character outside ASCII
        }
        return out;
    }

    Color rgb(uint32_t v, float a = 1.0f)
    {
        return Color{static_cast<unsigned char>(v >> 16), static_cast<unsigned char>(v >> 8), static_cast<unsigned char>(v),
                     static_cast<unsigned char>(std::lround(255.0f * std::clamp(a, 0.0f, 1.0f)))};
    }

    // raylib draws a triangle given counter-clockwise on screen (back faces are culled): fix the order.
    void tri(Vector2 a, Vector2 b, Vector2 c, Color col)
    {
        const float cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
        if (cross > 0.0f)
            std::swap(b, c);
        DrawTriangle(a, b, c, col);
    }

    // A polygon that is star-shaped around `center` (every convex polygon and our stars): a fan of triangles.
    void fan(Vector2 center, const std::vector<Vector2> &pts, Color col)
    {
        for (size_t i = 0; i < pts.size(); ++i)
            tri(center, pts[i], pts[(i + 1) % pts.size()], col);
    }

    void outline(const std::vector<Vector2> &pts, float width, Color col)
    {
        for (size_t i = 0; i < pts.size(); ++i)
        {
            DrawLineEx(pts[i], pts[(i + 1) % pts.size()], width, col);
            DrawCircleV(pts[i], width * 0.5f, col);
        }
    }

    // The badge in the 200x100 design space of tools/make_rank_badges.py, mapped onto `r`.
    struct Map
    {
        Rectangle r;
        Vector2 operator()(float x, float y) const
        {
            return Vector2{r.x + x * r.width / tekken4_rank_badges::kWidth, r.y + y * r.height / tekken4_rank_badges::kHeight};
        }
        float s(float v) const { return v * r.width / tekken4_rank_badges::kWidth; }
    };

    std::vector<Vector2> emblem(const Map &m, int star, int n, float cx, float cy, float r)
    {
        std::vector<Vector2> pts;
        const float pi = 3.14159265358979f;
        if (!star)
        {
            float start = (n % 2) ? -pi / 2 : -pi / 2 + pi / n;
            if (n == 4)
                start = -pi / 2;
            for (int i = 0; i < n; ++i)
                pts.push_back(m(cx + r * std::cos(start + 2 * pi * i / n), cy + r * std::sin(start + 2 * pi * i / n)));
            return pts;
        }
        const float inner = r * (n <= 6 ? 0.42f : n <= 8 ? 0.55f : 0.68f);
        for (int i = 0; i < 2 * n; ++i)
        {
            const float a = -pi / 2 + pi * i / n;
            const float rr = (i % 2 == 0) ? r : inner;
            pts.push_back(m(cx + rr * std::cos(a), cy + rr * std::sin(a)));
        }
        return pts;
    }

    Font font()
    {
        if (!g.fontTried)
        {
            g.fontTried = true;
            const char *windir = std::getenv("WINDIR");
            for (const std::string path : {std::string(windir ? windir : "C:\\Windows") + "\\Fonts\\arialbd.ttf",
                                           std::string(windir ? windir : "C:\\Windows") + "\\Fonts\\segoeuib.ttf"})
            {
                if (!FileExists(path.c_str()))
                    continue;
                Font f = LoadFontEx(path.c_str(), 64, nullptr, 0);
                if (f.texture.id != 0)
                {
                    SetTextureFilter(f.texture, TEXTURE_FILTER_BILINEAR);
                    g.font = f;
                    g.fontOwn = true;
                    break;
                }
            }
            if (!g.fontOwn)
                g.font = GetFontDefault();
        }
        return g.font;
    }

    // Text with a dark rim (the badge's stroke / readable on any stage), centred on (cx, cy) or left-aligned at x.
    void text(const std::string &s, float x, float cy, float size, Color fill, Color rim, bool centred)
    {
        const Font f = font();
        const float spacing = size * 0.04f;
        const Vector2 dim = MeasureTextEx(f, s.c_str(), size, spacing);
        const float left = centred ? x - dim.x * 0.5f : x;
        const float top = cy - dim.y * 0.5f;
        const float o = std::max(1.0f, size * 0.07f);
        for (int dx = -1; dx <= 1; ++dx)
            for (int dy = -1; dy <= 1; ++dy)
                if (dx || dy)
                    DrawTextEx(f, s.c_str(), Vector2{left + dx * o, top + dy * o}, size, spacing, rim);
        DrawTextEx(f, s.c_str(), Vector2{left, top}, size, spacing, fill);
    }

    float textWidth(const std::string &s, float size)
    {
        return MeasureTextEx(font(), s.c_str(), size, size * 0.04f).x;
    }

    std::vector<std::string> nameLines(const std::string &name)
    {
        std::string up = name;
        for (char &c : up)
            c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        if (up.size() <= 9 || up.find(' ') == std::string::npos)
            return {up};
        size_t best = std::string::npos;
        for (size_t i = 0; i < up.size(); ++i)
            if (up[i] == ' ' && (best == std::string::npos ||
                                 std::fabs(static_cast<double>(i) - up.size() / 2.0) <
                                     std::fabs(static_cast<double>(best) - up.size() / 2.0)))
                best = i;
        return {up.substr(0, best), up.substr(best + 1)};
    }

    // One rank badge (tools/make_rank_badges.py's svg(), element for element) into `r` (2:1).
    void badge(int tier, Rectangle r)
    {
        if (tier < 0 || tier >= tekken4_rank_badges::kCount)
            return;
        const auto &b = tekken4_rank_badges::kBadges[tier];
        const Map m{r};
        const Color plate = rgb(b.plate), light = rgb(b.light), dark = rgb(b.dark);
        const std::vector<Vector2> hex = {m(14, 6), m(186, 6), m(198, 50), m(186, 94), m(14, 94), m(2, 50)};
        fan(m(100, 50), hex, plate);
        fan(m(100, 27), {m(14, 10), m(186, 10), m(195, 44), m(5, 44)}, rgb(b.light, 0.22f));
        outline(hex, m.s(5), light);
        DrawCircleV(m(50, 50), m.s(36), dark);
        DrawRing(m(50, 50), m.s(34.5f), m.s(37.5f), 0.0f, 360.0f, 48, light);
        if (!b.star && b.n == 0)
            DrawCircleV(m(50, 50), m.s(22), light);
        else
            fan(m(50, 50), emblem(m, b.star, b.n, 50, 50, 30), light);
        const float step = b.of > 4 ? 11.0f : 14.0f;
        for (int i = 0; i < b.pips; ++i)
        {
            DrawCircleV(m(96 + i * step, 80), m.s(4.75f), dark);
            DrawCircleV(m(96 + i * step, 80), m.s(4.0f), light);
        }
        const std::vector<std::string> lines = nameLines(b.name);
        size_t longest = 0;
        for (const auto &l : lines)
            longest = std::max(longest, l.size());
        const float size = std::min(22.0f, std::round(92.0f / (0.7f * static_cast<float>(longest)) * 10.0f) / 10.0f);
        float ys[2] = {50, 0};
        if (lines.size() == 2)
            ys[0] = 38, ys[1] = 60;
        for (size_t i = 0; i < lines.size(); ++i)
        {
            const float y = ys[i] - (b.pips ? 6.0f : 0.0f);
            const Vector2 p = m(141, y);
            text(lines[i], p.x, p.y, m.s(size) * 1.05f, WHITE, dark, true);
        }
    }

    // A side's plate: "P1" / "P2" tag, the name, the badge. `right` = aligned to the right edge (P2).
    void fightPlate(int side, float edgeX, float y, float h, bool right)
    {
        const Side &s = g.side[side];
        if (s.name.empty() && s.tier < 0)
            return;
        const float pad = h * 0.18f;
        const float badgeW = s.tier >= 0 ? h * 2.0f : 0.0f;
        const float nameSize = h * 0.62f, tagSize = h * 0.5f;
        const std::string tag = side == 0 ? "P1" : "P2";
        const float tagW = textWidth(tag, tagSize), nameW = textWidth(s.name, nameSize);
        const float w = pad + tagW + pad + nameW + (badgeW > 0 ? pad + badgeW : 0.0f) + pad;
        const float x = right ? edgeX - w : edgeX;
        DrawRectangleRounded(Rectangle{x, y, w, h}, 0.35f, 8, Color{0, 0, 0, 150});
        const Color tagCol = side == 0 ? Color{235, 70, 60, 255} : Color{70, 130, 245, 255};
        // P1: tag, name, badge (left to right); P2 mirrors it: badge, name, tag.
        float cur = x + pad;
        auto put = [&](int what) {
            if (what == 0)
            {
                text(tag, cur, y + h * 0.5f, tagSize, tagCol, BLACK, false);
                cur += tagW + pad;
            }
            else if (what == 1)
            {
                text(s.name, cur, y + h * 0.5f, nameSize, WHITE, BLACK, false);
                cur += nameW + pad;
            }
            else if (badgeW > 0)
            {
                badge(s.tier, Rectangle{cur, y - h * 0.05f, badgeW * 1.05f, h * 1.05f});
                cur += badgeW + pad;
            }
        };
        if (!right)
            put(0), put(1), put(2);
        else
            put(2), put(1), put(0);
    }

    // At the select screen: under the side's preview, centred on cx -- tag + name, the badge below.
    void selectPlate(int side, float cx, float y, float unit)
    {
        const Side &s = g.side[side];
        if (s.name.empty() && s.tier < 0)
            return;
        const float nameSize = unit * 0.55f;
        const std::string line = std::string(side == 0 ? "P1 " : "P2 ") + s.name;
        const float w = std::max(textWidth(line, nameSize) + unit * 0.5f, s.tier >= 0 ? unit * 3.0f : 0.0f);
        const float h = unit * (s.tier >= 0 ? 2.45f : 0.95f);
        DrawRectangleRounded(Rectangle{cx - w * 0.5f, y, w, h}, 0.25f, 8, Color{0, 0, 0, 150});
        text(line, cx, y + unit * 0.48f, nameSize, WHITE, BLACK, true);
        if (s.tier >= 0)
            badge(s.tier, Rectangle{cx - unit * 1.35f, y + unit * 0.95f, unit * 2.7f, unit * 1.35f});
    }

    void maybeShot()
    {
        if (g.nextShot >= g.shots.size())
            return;
        const double t = std::chrono::duration<double>(std::chrono::steady_clock::now() - g.start).count();
        if (t < g.shots[g.nextShot])
            return;
        rlDrawRenderBatchActive();          // raylib batches shapes and text until EndDrawing: draw them first
        Image img = LoadImageFromScreen(); // the back buffer: the picture and the plates, before the swap
        std::ostringstream name;
        name << "hud_" << static_cast<int>(g.shots[g.nextShot]) << "s.png";
        const bool ok = img.data && ExportImage(img, name.str().c_str());
        UnloadImage(img);
        RUNTIME_LOG("[hud] " << (ok ? "wrote " : "could not write ") << name.str() << "\n");
        ++g.nextShot;
    }

    // Test hook for pictures: TEKKEN4_HUD_WINDOW=<w>x<h> sets the window's size once (host-only).
    void windowSize()
    {
        static bool done = false;
        if (done)
            return;
        done = true;
        const char *v = std::getenv("TEKKEN4_HUD_WINDOW");
        int w = 0, h = 0;
        if (v && std::sscanf(v, "%dx%d", &w, &h) == 2 && w >= 320 && h >= 224 && w <= 7680 && h <= 4320)
            SetWindowSize(w, h);
    }

    void draw(PS2Runtime &runtime, const ps2_host_overlay::Frame &f, void *)
    {
        windowSize();
        const uint8_t *rdram = runtime.memory().getRDRAM();
        if (rdram)
        {
            const int32_t scene = static_cast<int32_t>(rd32(rdram, kScene));
            const int32_t type = static_cast<int32_t>(rd32(rdram, kGameType));
            if (type == kTypeVs && scene == kSceneSelect)
            {
                const float unit = f.h * 0.06f;
                selectPlate(0, f.x + f.w * 0.165f, f.y + f.h * 0.545f, unit);
                selectPlate(1, f.x + f.w * 0.835f, f.y + f.h * 0.545f, unit);
            }
            else if (type == kTypeVs && scene == kSceneFight)
            {
                bool running = false;
                const uint32_t round = rd32(rdram, kRoundNumber);
                const int32_t timer = static_cast<int32_t>(rd32(rdram, kRoundTimer));
                if (round >= 1 && round <= 9 && timer > 0 && timer <= 99 * 60)
                    for (int side = 0; side < 2; ++side)
                    {
                        const uint32_t p = rd32(rdram, kPlayerTable + 4u * side);
                        if (p >= 0x100000u && p < 0x2000000u)
                        {
                            const int32_t hp = static_cast<int32_t>(rd32(rdram, p + kOffHealth));
                            running = running || (hp > 0 && hp <= (200 << 16));
                        }
                    }
                if (running)
                {
                    const float h = f.h * 0.052f;
                    fightPlate(0, f.x + f.w * 0.04f, f.y + f.h * 0.155f, h, false);
                    fightPlate(1, f.x + f.w * 0.96f, f.y + f.h * 0.155f, h, true);
                }
            }
        }
        maybeShot();
    }

    void apply(PS2Runtime &)
    {
        const char *names = std::getenv("TEKKEN4_HUD_NAMES");
        const char *plates = std::getenv("TEKKEN4_HUD_PLATES");
        const char *shots = std::getenv("TEKKEN4_HUD_SHOTS");
        if (shots && *shots)
        {
            std::stringstream list(shots);
            for (std::string item; std::getline(list, item, ',');)
                if (!item.empty())
                    g.shots.push_back(std::atof(item.c_str()));
            std::sort(g.shots.begin(), g.shots.end());
        }
        g.start = std::chrono::steady_clock::now();
        const bool off = plates && std::strcmp(plates, "0") == 0;
        if (!off && names && *names)
        {
            const std::string all(names);
            const size_t bar = all.find('|');
            g.side[0].name = clean(all.substr(0, bar));
            g.side[1].name = bar == std::string::npos ? std::string() : clean(all.substr(bar + 1));
            if (const char *ranks = std::getenv("TEKKEN4_HUD_RANKS"))
            {
                std::stringstream list(ranks);
                std::string item;
                for (int side = 0; side < 2 && std::getline(list, item, ','); ++side)
                {
                    char *end = nullptr;
                    const long v = std::strtol(item.c_str(), &end, 10);
                    g.side[side].tier = (end != item.c_str() && v >= 0 && v < tekken4_rank_badges::kCount)
                                            ? static_cast<int>(v) : -1;
                }
            }
            RUNTIME_LOG("[hud] name plates: P1 \"" << g.side[0].name << "\" tier " << g.side[0].tier << ", P2 \""
                                                   << g.side[1].name << "\" tier " << g.side[1].tier << "\n");
        }
        else
        {
            g.side[0] = g.side[1] = Side{};
            if (off)
                RUNTIME_LOG("[hud] name plates off (TEKKEN4_HUD_PLATES=0)\n");
        }
        if ((g.side[0].name.size() || g.side[1].name.size()) || !g.shots.empty())
            ps2_host_overlay::set(draw, nullptr);
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 online name plates (SLUS-20328 v1.00)", "SLUS_203.28", 0x00180088u, 0xB975F704u,
                           tekken4_hud::apply)
