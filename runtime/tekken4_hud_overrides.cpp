// Tekken 4 (SLUS-20328 v1.00): game-rendered online names and host-only rank badges.
// TEKKEN4_HUD_NAMES=P1|P2, TEKKEN4_HUD_RANKS=tier,tier, TEKKEN4_HUD_PLATES=0 restores fighter names.
// Names enter the guest font queue at the original name draw calls, including resimulation. The net HELLO
// fingerprint requires identical effective names/settings. Badge drawing never writes guest memory.
// See docs/T4_RANKED.md for the static trace, queue contract and required coordinator pair runs.
#include "game_overrides.h"
#include "ps2_host_overlay.h"
#include "ps2_log.h"
#include "ps2_runtime.h"
#include "raylib.h"
#include "rlgl.h"
#include "tekken4_rank_badges.h"
#include "tekken4_native_names.h"

#include <algorithm>
#include <mutex>
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
    constexpr int kSceneSelect = 7, kSceneFight = 4, kTypeVs = 3;

    struct Anchor
    {
        int x = 0, y = 0, scene = 0;
        uint8_t alpha = 0;
        bool valid = false;
    };
    std::mutex g_anchorMutex;
    Anchor g_anchor[2]; // presenter reads under the same lock; never used to decide guest writes
    PS2Runtime::RecompiledFunction g_selectOriginal = nullptr, g_fightOriginal = nullptr;
    PS2Runtime::RecompiledFunction g_selectWidgetOriginal = nullptr;

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

    // The renderer and the queue use 640x448 game coordinates. The select quad has already been
    // projected to GS 12.4 integers by FUN_001d5d90, with origin (1728, 1824).
    bool nativeName(uint8_t *ram, int side, int scene, int cx, int cy, uint8_t alpha)
    {
        if (side < 0 || rd32(ram, kGameType) != kTypeVs || rd32(ram, kScene) != static_cast<uint32_t>(scene))
            return false;
        const auto &name = tekken4_names::settings().names[side];
        const auto text = tekken4_names::fit(ram, name);
        const int x = cx - text.width / 2, y = cy - 10; // font 6: 20-pixel glyph quad
        if (!tekken4_names::enqueue(ram, text, x, y, alpha))
            return false;
        std::lock_guard<std::mutex> lock(g_anchorMutex);
        g_anchor[side] = Anchor{x, y, scene, alpha, true};
        return true;
    }

    void fightName(uint8_t *ram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t ra = getRegU32(ctx, 31);
        const int side = tekken4_names::fightSide(ra);
        // Original HUD caller supplies the centre in 12.4 pixels: (86,57) / (557,57).
        if (nativeName(ram, side, kSceneFight, static_cast<int32_t>(getRegU32(ctx, 6)) / 16,
                       static_cast<int32_t>(getRegU32(ctx, 7)) / 16, 128))
            ctx->pc = ra;
        else
            g_fightOriginal(ram, ctx, runtime);
    }

    void selectName(uint8_t *ram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t ra = getRegU32(ctx, 31);
        // $s1 survives in FUN_001f4da8 and identifies the side's object, even in a mirror match.
        const int side = tekken4_names::selectSide(ra, getRegU32(ctx, 17));
        const uint32_t quad = getRegU32(ctx, 6);
        if (side >= 0 && quad >= 0x00100000u && quad <= 0x01ffffc0u && std::isfinite(ctx->f[14]))
        {
            int32_t minX = INT32_MAX, minY = INT32_MAX, maxX = INT32_MIN, maxY = INT32_MIN;
            for (uint32_t i = 0; i < 4; ++i)
            {
                const int32_t x = static_cast<int32_t>(rd32(ram, quad + i * 16));
                const int32_t y = static_cast<int32_t>(rd32(ram, quad + i * 16 + 4));
                minX = std::min(minX, x); maxX = std::max(maxX, x);
                minY = std::min(minY, y); maxY = std::max(maxY, y);
            }
            const int cx = static_cast<int>((static_cast<int64_t>(minX) + maxX) / 32 - 1728);
            const int cy = static_cast<int>((static_cast<int64_t>(minY) + maxY) / 32 - 1824);
            const auto alpha = static_cast<uint8_t>(std::lround(std::clamp(ctx->f[14], 0.0f, 1.0f) * 128.0f));
            if (nativeName(ram, side, kSceneSelect, cx, cy, alpha))
            {
                ctx->pc = ra;
                return;
            }
        }
        g_selectOriginal(ram, ctx, runtime);
    }

    void selectWidgetName(uint8_t *ram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t ra = getRegU32(ctx, 31), widget = getRegU32(ctx, 4);
        if (widget >= 0x00100000u && widget <= 0x01ffffa0u)
        {
            // The active VS UI keeps the side in s3, independent of fighter and local role.
            const int side = tekken4_names::selectWidgetSide(ra, getRegU32(ctx, 19),
                                                             rd32(ram, widget + 0x54) & 0xffffu);
            if (side >= 0 && rd32(ram, kScene) == kSceneSelect && rd32(ram, kGameType) == kTypeVs)
            {
                const bool visible = (rd32(ram, widget + 0x52) & 0xffffu) != 0;
                float opacity = 0.0f;
                std::memcpy(&opacity, ram + widget + 0x5c, sizeof(opacity));
                std::array<float, 16> matrix;
                std::memcpy(matrix.data(), ram + widget + 0x10, sizeof(matrix));
                int cx = 0, cy = 0;
                if (visible && std::isfinite(opacity) && tekken4_names::selectWidgetCentre(matrix, cx, cy))
                {
                    const auto alpha = static_cast<uint8_t>(std::lround(std::clamp(opacity, 0.0f, 1.0f) * 128.0f));
                    if (nativeName(ram, side, kSceneSelect, cx, cy, alpha))
                    {
                        ctx->pc = ra;
                        return;
                    }
                }
                // A hidden widget or fallback draw must not retain a badge from an earlier name.
                std::lock_guard<std::mutex> lock(g_anchorMutex);
                g_anchor[side].valid = false;
            }
        }
        g_selectWidgetOriginal(ram, ctx, runtime);
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
            const char *windir = std::getenv("WINDIR"); // the Windows folder (its Fonts); none -> raylib's own font
            const std::string fonts = std::string(windir ? windir : "") + "/Fonts/";
            for (const std::string path : {fonts + "arialbd.ttf", fonts + "segoeuib.ttf"})
            {
                if (!windir || !*windir || !FileExists(path.c_str()))
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
    void badge(int tier, Rectangle r, uint8_t alpha)
    {
        if (tier < 0 || tier >= tekken4_rank_badges::kCount)
            return;
        const auto &b = tekken4_rank_badges::kBadges[tier];
        const Map m{r};
        const float opacity = std::min(1.0f, alpha / 128.0f);
        const Color plate = rgb(b.plate, opacity), light = rgb(b.light, opacity), dark = rgb(b.dark, opacity);
        const std::vector<Vector2> hex = {m(14, 6), m(186, 6), m(198, 50), m(186, 94), m(14, 94), m(2, 50)};
        fan(m(100, 50), hex, plate);
        fan(m(100, 27), {m(14, 10), m(186, 10), m(195, 44), m(5, 44)}, rgb(b.light, 0.22f * opacity));
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
            text(lines[i], p.x, p.y, m.s(size) * 1.05f, rgb(0xffffffu, opacity), dark, true);
        }
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
            if (type == kTypeVs && (scene == kSceneSelect || scene == kSceneFight))
            {
                Anchor anchors[2];
                {
                    std::lock_guard<std::mutex> lock(g_anchorMutex);
                    std::copy(std::begin(g_anchor), std::end(g_anchor), anchors);
                }
                for (int side = 0; side < 2; ++side)
                {
                    const Anchor &a = anchors[side];
                    // Live guest RAM can advance or roll back while a frame is presented.
                    // Scene/visibility are stable guards; a current-RAM frame-age test flickers.
                    if (!a.valid || a.scene != scene || !a.alpha)
                        continue;
                    // Badge only: its right edge is four game pixels left of the actual queued text.
                    const float sx = f.w / 640.0f, sy = f.h / 448.0f;
                    badge(g.side[side].tier, Rectangle{f.x + (a.x - 32) * sx, f.y + (a.y + 1) * sy,
                                                      28 * sx, 16 * sy}, a.alpha);
                }
            }
        }
        maybeShot();
    }

    void apply(PS2Runtime &runtime)
    {
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
        const auto &names = tekken4_names::settings();
        if (names.enabled())
        {
            // Install the entry hooks together. Other callers/resume addresses keep their original functions.
            if (!runtime.hasFunction(0x001f0a80u) || !runtime.hasFunction(0x001f2e70u) ||
                !runtime.hasFunction(0x00236eb8u))
            {
                RUNTIME_LOG("[hud] native name entry points unavailable; fighter names retained\n");
                return;
            }
            const auto fight = runtime.lookupFunction(0x001f0a80u);
            const auto select = runtime.lookupFunction(0x001f2e70u);
            const auto selectWidget = runtime.lookupFunction(0x00236eb8u);
            if (fight != fightName) g_fightOriginal = fight;
            if (select != selectName) g_selectOriginal = select;
            if (selectWidget != selectWidgetName) g_selectWidgetOriginal = selectWidget;
            runtime.registerFunction(0x001f0a80u, fightName);
            runtime.registerFunction(0x001f2e70u, selectName);
            runtime.registerFunction(0x00236eb8u, selectWidgetName);
            for (int side = 0; side < 2; ++side)
                g.side[side].name = names.names[side];
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
            RUNTIME_LOG("[hud] native font names: P1 \"" << g.side[0].name << "\" tier " << g.side[0].tier << ", P2 \""
                                                   << g.side[1].name << "\" tier " << g.side[1].tier << "\n");
        }
        else
        {
            g.side[0] = g.side[1] = Side{};
            RUNTIME_LOG("[hud] native names off or absent; fighter names retained\n");
        }
        if ((g.side[0].name.size() || g.side[1].name.size()) || !g.shots.empty())
            ps2_host_overlay::set(draw, nullptr);
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 online name plates (SLUS-20328 v1.00)", "SLUS_203.28", 0x00180088u, 0xB975F704u,
                           tekken4_hud::apply)
