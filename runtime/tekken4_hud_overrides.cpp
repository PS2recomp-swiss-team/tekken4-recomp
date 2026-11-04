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
#include "tekken4_badge_draw.h"
#include "tekken4_rank_cache.h"
#include "tekken4_rank_label.h"

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
        tekken4_rank_cache::Plates plates;
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
                int cx = 0, cy = 0;
                uint8_t alpha = 0;
                if (tekken4_names::selectNodeAnchor(ram, widget, cx, cy, alpha) &&
                    nativeName(ram, side, kSceneSelect, cx, cy, alpha))
                {
                    ctx->pc = ra;
                    return;
                }
                // A hidden widget or fallback draw must not retain a badge from an earlier name.
                std::lock_guard<std::mutex> lock(g_anchorMutex);
                g_anchor[side].valid = false;
            }
        }
        g_selectWidgetOriginal(ram, ctx, runtime);
    }

    // Proof sheet uses precisely the renderer used in the HUD, at three actual pixel sizes.
    void maybeSheet()
    {
        static bool done=false;
        if(done) return;
        done=true;
        const char *path=std::getenv("TEKKEN4_HUD_BADGE_SHEET");
        if(!path||!*path) return;
        const auto target=LoadRenderTexture(1140,1260);
        BeginTextureMode(target);
        ClearBackground(Color{10,21,31,255});
        DrawText("T4 / T5DR 37 ranks - original host vector artwork",24,18,24,Color{209,241,255,255});
        DrawText("Actual pixel sizes: 22 x 14   /   45 x 28   /   67 x 42",24,52,18,Color{155,190,208,255});
        for(int rank=0;rank<tekken4_rank_badges::kCount;++rank) {
            const int col=rank/13, row=rank%13, x=24+col*376, y=92+row*88;
            DrawText(TextFormat("%02d  %s",rank,tekken4_rank_badges::kBadges[rank].name),x,y,16,Color{209,225,235,255});
            for(int size=1;size<=3;++size)
                tekken4_badge_draw::draw(rank,Rectangle{static_cast<float>(x+16+(size-1)*100),
                    static_cast<float>(y+24+42-14*size),22.4f*size,14.0f*size},1.0f);
        }
        EndTextureMode();
        Image img=LoadImageFromTexture(target.texture);
        ImageFlipVertical(&img);
        const bool ok=ExportImage(img,path);
        UnloadImage(img);
        UnloadRenderTexture(target);
        RUNTIME_LOG("[hud] badge sheet " << (ok ? "written" : "failed") << "\n");
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

    void originalBadge(int side,int tier,Rectangle rect,uint8_t alpha)
    {
        if(tier<0||tier>=tekken4_rank_badges::kCount||!alpha) return;
        if(alpha>=128) { tekken4_badge_draw::draw(tier,rect,1); return; }
        // Composite the bevel as ONE fading object. Applying alpha to overlapping facets separately
        // would make the centre remain opaque. This temporary target is exactly window resolution,
        // with a 1:1 blit: no small bitmap is ever enlarged (including during HUD transitions).
        static RenderTexture2D target[2]{};
        auto &texture=target[side];
        const int w=static_cast<int>(std::ceil(rect.width)),h=static_cast<int>(std::ceil(rect.height));
        if(texture.id&&(texture.texture.width!=w||texture.texture.height!=h)) {
            UnloadRenderTexture(texture); texture={};
        }
        if(!texture.id) texture=LoadRenderTexture(w,h);
        if(!texture.id) return;
        BeginTextureMode(texture);
        ClearBackground(BLANK);
        tekken4_badge_draw::draw(tier,Rectangle{0,0,rect.width,rect.height},1);
        EndTextureMode();
        DrawTexturePro(texture.texture,Rectangle{0,0,static_cast<float>(w),-static_cast<float>(h)},
                       Rectangle{rect.x,rect.y,static_cast<float>(w),static_cast<float>(h)},Vector2{0,0},0,
                       Color{255,255,255,static_cast<uint8_t>(alpha*255/128)});
    }

    void draw(PS2Runtime &runtime, const ps2_host_overlay::Frame &f, void *)
    {
        windowSize();
        maybeSheet();
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
                    // Direct window-resolution geometry, baseline anchored to the native font.
                    const int tier = g.side[side].tier;
                    const Rectangle rect = tekken4_badge_draw::bounds(f.x,f.y,f.w,f.h,a.x,a.y);
                    if (!g.plates.draw(tier, rect, a.alpha))
                        originalBadge(side,tier,rect,a.alpha);
                    if (scene == kSceneSelect && tier >= 0 && tier < tekken4_rank_badges::kCount)
                    {
                        const float sx=f.w/640, sy=f.h/448;
                        tekken4_rank_label::draw(runtime,tekken4_rank_badges::kBadges[tier].name,
                            f.x+a.x*sx,f.y+(a.y+21)*sy,sx*0.70f,sy*0.70f,a.alpha,112*sx);
                    }
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
