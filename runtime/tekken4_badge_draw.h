#pragma once
// Original geometric artwork. Draw directly in the presenter's window pixels, never a low-res target.
#include "tekken4_rank_badges.h"
#include "raylib.h"
#include <algorithm>
#include <cmath>
#include <vector>

namespace tekken4_badge_draw
{
    inline Color color(uint32_t rgb, float alpha)
    {
        return Color{static_cast<unsigned char>(rgb >> 16), static_cast<unsigned char>(rgb >> 8),
                     static_cast<unsigned char>(rgb), static_cast<unsigned char>(255 * std::clamp(alpha, 0.0f, 1.0f))};
    }
    inline void triangle(Vector2 a, Vector2 b, Vector2 c, Color col)
    {
        if ((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) > 0) std::swap(b,c);
        DrawTriangle(a,b,c,col);
    }
    inline void polygon(const std::vector<Vector2> &p, Color col)
    {
        for (size_t i=1; i+1<p.size(); ++i) triangle(p[0],p[i],p[i+1],col);
    }
    inline void draw(int tier, Rectangle r, float alpha)
    {
        if (tier < 0 || tier >= tekken4_rank_badges::kCount || r.height <= 0) return;
        const auto &b = tekken4_rank_badges::kBadges[tier];
        // 160x100 design: one strong emblem and a tier-progress rail, no lettering or micro-pips.
        const auto p = [&](float x,float y) { return Vector2{r.x+x*r.width/160, r.y+y*r.height/100}; };
        const auto shape = [&](float inset) {
            return std::vector<Vector2>{p(16+inset,inset),p(144-inset,inset),p(160-inset,50),
                                       p(144-inset,100-inset),p(16+inset,100-inset),p(inset,50)};
        };
        polygon(shape(0), color(0x07151f,alpha));
        polygon(shape(3), color(0xc5f2ff,alpha));
        polygon(shape(9), color(0x263746,alpha));
        // Broad polished facets, with an uninterrupted silver/cyan edge like the life-bar frame.
        polygon({p(16,9),p(144,9),p(151,30),p(9,30)},color(0xf2fbff,alpha));
        polygon({p(9,70),p(151,70),p(144,91),p(16,91)},color(0x56869e,alpha));
        polygon(shape(16),color(b.dark,alpha));
        polygon({p(28,18),p(132,18),p(144,49),p(16,49)},color(b.plate,alpha));
        polygon({p(28,18),p(132,18),p(136,28),p(24,28)},color(b.light,alpha));
        // Tier geometry is intentionally simple enough to survive a 14-pixel cap height.
        const float cx=70, cy=51, radius=30;
        const int n = b.n == 0 ? 16 : std::min(b.n,8);
        const int count = b.star ? n*2 : n;
        std::vector<Vector2> emblem;
        for(int i=0;i<count;++i) {
            const float angle=-1.570796327f+6.283185307f*i/count;
            const float rr=radius * ((b.star && (i&1)) ? 0.48f : 1.0f);
            emblem.push_back(p(cx+rr*std::cos(angle),cy+rr*std::sin(angle)));
        }
        // Stars need a centre fan (a triangle fan from their first vertex would cross concavities).
        for(size_t i=0;i<emblem.size();++i)
            triangle(p(cx,cy),emblem[i],emblem[(i+1)%emblem.size()],color(b.light,alpha));
        polygon({p(65,35),p(77,51),p(65,65),p(56,51)},color(0xf3fbff,alpha));
        // A single rising rail differentiates steps within a colour family without tiny dots/text.
        const float progress = b.of > 0 ? static_cast<float>(b.pips)/b.of : 0;
        polygon({p(115,76),p(125,76),p(125,30),p(115,30)},color(0x12212b,alpha));
        if(progress>0) polygon({p(115,76),p(125,76),p(125,76-46*progress),p(115,76-46*progress)},color(b.light,alpha));
    }

    // Baseline follows the actual game-font queue anchor. Uniform scale keeps the plate metallic
    // rather than stretched when the game is presented at 16:9. 4 game pixels separate badge/name.
    inline Rectangle bounds(float x,float y,float w,float h,int nameX,int nameY)
    {
        const float sx=w/640, sy=h/448;
        const float height=14*sy, width=height*1.6f;
        // Native font capitals occupy rows 4..17 inclusive; the baseline is the following edge.
        return Rectangle{x+nameX*sx-4*sx-width,y+(nameY+18)*sy-height,width,height};
    }
}
