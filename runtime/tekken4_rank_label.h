#pragma once
// Read the installed game's font 6 into a host texture. No font pixels are shipped or
// written to disk, and rank-dependent bytes never enter the guest font queue/RAM.
#include "ps2_runtime.h"
#include "raylib.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <map>
#include <string>
#include <vector>

namespace tekken4_rank_label
{
    template <typename T> inline T read(const uint8_t *ram, uint32_t address)
    {
        T result;
        std::memcpy(&result, ram + address, sizeof(result));
        return result;
    }

    inline bool range(uint32_t address, uint32_t bytes)
    {
        return address >= 0x00100000u && address < 0x02000000u && bytes <= 0x02000000u - address;
    }

    struct Label
    {
        Texture2D texture{};
        int width = 0;
    };

    inline Label load(const uint8_t *ram, const std::string &name)
    {
        Label result;
        if (!ram || name.empty() || name.size() > 32)
            return result;
        // Font 6's game-owned runtime object: row width, rows, glyph stride,
        // source pixels, palette and glyph-index indirection. Reject other layouts.
        constexpr uint32_t descriptor = 0x002bd100u;
        const uint32_t rowWords = read<uint32_t>(ram, descriptor + 0x18);
        const uint32_t height = read<uint32_t>(ram, descriptor + 0x1c);
        const uint32_t stride = read<uint32_t>(ram, descriptor + 0x20);
        const uint32_t source = read<uint32_t>(ram, descriptor + 0x24);
        const uint32_t palette = read<uint32_t>(ram, descriptor + 0x28);
        const uint32_t indices = read<uint32_t>(ram, descriptor + 0x2c);
        const uint32_t metrics = read<uint32_t>(ram, 0x0031f208u);
        if (rowWords != 5 || height != 20 || stride != 200 ||
            !range(source, stride) || !range(palette, 64) || !range(indices, 192) || !range(metrics, 512))
            return result;

        int width = 0;
        for (unsigned char c : name)
        {
            if (c < 0x20 || c > 0x7e)
                return result;
            const int advance = static_cast<int8_t>(ram[metrics + c]);
            if (advance <= 0 || advance > 20)
                return result;
            width += advance;
        }
        // Preserve overhang at either end; the nominal width remains the advances.
        const int imageWidth = width + 20;
        std::vector<Color> pixels(static_cast<size_t>(imageWidth) * height, Color{0, 0, 0, 0});
        int pen = 10;
        bool any = false;
        for (unsigned char c : name)
        {
            const uint32_t glyph = read<uint16_t>(ram, indices + 2u * (c - 0x20u));
            if (glyph >= 192 || !range(source, (glyph + 1) * stride))
                return Label{};
            const int bearing = static_cast<int8_t>(ram[metrics + 0x100u + c]);
            if (bearing < -20 || bearing > 20)
                return Label{};
            if (c != ' ')
            {
                for (uint32_t y = 0; y < height; ++y)
                    for (uint32_t x = 0; x < 20; ++x)
                    {
                        const int dstX = pen + static_cast<int>(x);
                        const int dstY = static_cast<int>(y) + bearing;
                        if (dstX < 0 || dstX >= imageWidth || dstY < 0 || dstY >= static_cast<int>(height))
                            continue;
                        const uint8_t packed = ram[source + glyph * stride + y * rowWords * 2 + x / 2];
                        const uint8_t index = (packed >> ((x & 1u) * 4u)) & 15u;
                        const uint32_t colour = read<uint32_t>(ram, palette + 4u * index);
                        Color pixel{static_cast<uint8_t>(colour), static_cast<uint8_t>(colour >> 8),
                                    static_cast<uint8_t>(colour >> 16),
                                    static_cast<uint8_t>(std::min(255u, (colour >> 24) * 255u / 128u))};
                        auto &dst = pixels[static_cast<size_t>(dstY) * imageWidth + dstX];
                        if (pixel.a > dst.a)
                            dst = pixel;
                        any = any || pixel.a != 0;
                    }
            }
            pen += static_cast<int8_t>(ram[metrics + c]);
        }
        if (!any)
            return result;
        Image image{pixels.data(), imageWidth, static_cast<int>(height), 1, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8};
        result.texture = LoadTextureFromImage(image);
        result.width = width;
        if (result.texture.id)
            SetTextureFilter(result.texture, TEXTURE_FILTER_BILINEAR);
        return result;
    }

    // x/y use the same top-left glyph-quad convention as the native name. The
    // caller supplies its select-only scale and the available window-pixel width.
    inline bool draw(PS2Runtime &runtime, const char *name, float x, float y,
                     float sx, float sy, uint8_t alpha, float availableWidth)
    {
        if (!name || !*name || sx <= 0 || sy <= 0 || !alpha)
            return false;
        static std::map<std::string, Label> labels;
        auto &label = labels[name];
        if (!label.texture.id)
            label = load(runtime.memory().getRDRAM(), name);
        if (!label.texture.id || label.width * sx > availableWidth)
            return false;
        const Rectangle source{0, 0, static_cast<float>(label.texture.width), static_cast<float>(label.texture.height)};
        const Rectangle target{x - 10 * sx, y, source.width * sx, source.height * sy};
        DrawTexturePro(label.texture, source, target, Vector2{0, 0}, 0,
                       Color{255, 255, 255, static_cast<uint8_t>(std::min(255u, alpha * 255u / 128u))});
        return true;
    }
}
