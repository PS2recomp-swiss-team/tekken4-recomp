#pragma once
// SLUS-20328 v1.00. Host configuration and the game's font queue adapter; no game assets in this file.
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>

namespace tekken4_names
{
    constexpr size_t kMaxLength = 16;
    constexpr int kMaxWidth = 104; // leaves room for a badge left of the P1 HUD's centre at x=86
    constexpr uint32_t kSelectNameObject = 0x00399ab0u, kSelectStride = 0x190u;
    constexpr uint32_t kFontDescriptor = 0x0031f208u; // font 6: 0x31f1d8 + 6 * 8
    constexpr uint32_t kQueue = 0x01cd07a0u, kQueueEnd = 0x01cd47a0u;
    constexpr uint32_t kTextCursor = 0x00357a54u; // gp - 0x511c, formatter's scratch cursor

    // Font 6 has separate ASCII upper/lowercase metrics. Keep printable ASCII, including literal '%';
    // enqueue bypasses printf. One '?' per valid non-ASCII UTF-8 scalar; malformed bytes also become '?'.
    inline std::string sanitize(std::string_view input)
    {
        std::string out;
        for (size_t i = 0; i < input.size() && out.size() < kMaxLength;)
        {
            const auto c = static_cast<unsigned char>(input[i]);
            if (c >= 0x20 && c <= 0x7e)
            {
                out.push_back(static_cast<char>(c));
                ++i;
                continue;
            }
            size_t n = c >= 0xc2 && c <= 0xdf ? 2 : c >= 0xe0 && c <= 0xef ? 3 :
                       c >= 0xf0 && c <= 0xf4 ? 4 : 1;
            bool valid = n > 1 && i + n <= input.size();
            for (size_t j = 1; valid && j < n; ++j)
                valid = (static_cast<unsigned char>(input[i + j]) & 0xc0) == 0x80;
            if (valid)
            {
                const auto second = static_cast<unsigned char>(input[i + 1]);
                valid = !(c == 0xe0 && second < 0xa0) && !(c == 0xed && second >= 0xa0) &&
                        !(c == 0xf0 && second < 0x90) && !(c == 0xf4 && second >= 0x90);
            }
            out.push_back('?');
            i += valid ? n : 1;
        }
        return out;
    }

    struct Settings
    {
        std::array<std::string, 2> names;
        bool enabled() const { return !names[0].empty() || !names[1].empty(); }
    };

    inline Settings parse(const char *names, const char *plates)
    {
        Settings result;
        if (!names || (plates && std::strcmp(plates, "0") == 0))
            return result;
        const std::string_view all(names);
        const size_t bar = all.find('|');
        // Require the launcher's P1|P2 contract. Never guess a local role or swap on the joiner.
        if (bar == std::string_view::npos || all.find('|', bar + 1) != std::string_view::npos)
            return result;
        result.names = {sanitize(all.substr(0, bar)), sanitize(all.substr(bar + 1))};
        return result;
    }

    inline std::string asciiFromWide(std::wstring_view raw)
    {
        std::string names;
        for (size_t i = 0; i < raw.size(); ++i)
        {
            const uint32_t c = static_cast<uint32_t>(raw[i]);
            if (c >= 0xd800 && c <= 0xdbff && i + 1 < raw.size() && raw[i + 1] >= 0xdc00 && raw[i + 1] <= 0xdfff)
                ++i;
            names.push_back(c >= 0x20 && c <= 0x7e ? static_cast<char>(c) : '?');
        }
        return names;
    }

    inline const Settings &settings()
    {
        // One immutable session configuration shared by override registration and net HELLO, in either order.
        static const Settings value = []
        {
#ifdef _WIN32
            // CRT getenv uses the PC's ANSI codepage. Read Unicode on Windows so the same launcher name
            // cannot turn into different ASCII bytes on two PCs with different system locales.
            const wchar_t *raw = _wgetenv(L"TEKKEN4_HUD_NAMES");
            const std::string names = raw ? asciiFromWide(raw) : std::string();
            return parse(raw ? names.c_str() : nullptr, std::getenv("TEKKEN4_HUD_PLATES"));
#else
            return parse(std::getenv("TEKKEN4_HUD_NAMES"), std::getenv("TEKKEN4_HUD_PLATES"));
#endif
        }();
        return value;
    }

    inline uint64_t fingerprint(uint64_t boot, const Settings &s)
    {
        uint64_t h = boot ? boot : 14695981039346656037ull;
        const auto byte = [&h](unsigned char c) { h = (h ^ c) * 1099511628211ull; };
        for (unsigned char c : std::string_view("T4 native names v1"))
            byte(c);
        for (const auto &name : s.names)
        {
            byte(static_cast<unsigned char>(name.size()));
            for (unsigned char c : name)
                byte(c);
        }
        return h ? h : 1;
    }

    inline int fightSide(uint32_t returnAddress)
    {
        return returnAddress == 0x001f1b94u ? 0 : returnAddress == 0x001f1bd8u ? 1 : -1;
    }

    inline int selectSide(uint32_t returnAddress, uint32_t nameObject)
    {
        if (returnAddress != 0x001f507cu)
            return -1;
        return nameObject == kSelectNameObject ? 0 : nameObject == kSelectNameObject + kSelectStride ? 1 : -1;
    }

    inline uint32_t read32(const uint8_t *ram, uint32_t address)
    {
        uint32_t value;
        std::memcpy(&value, ram + address, sizeof(value));
        return value;
    }

    template <typename T> inline void write(uint8_t *ram, uint32_t address, T value)
    {
        std::memcpy(ram + address, &value, sizeof(value));
    }

    struct Text
    {
        std::string name;
        int width = 0;
    };

    inline Text fit(const uint8_t *ram, const std::string &name)
    {
        Text result;
        const uint32_t widths = read32(ram, kFontDescriptor);
        if (widths < 0x00180080u || widths > 0x01fffe00u)
            return result;
        for (unsigned char c : name)
        {
            if (c < 0x20 || c > 0x7e || result.name.size() >= kMaxLength)
                break;
            const int advance = static_cast<int8_t>(ram[widths + c]); // FUN_0022c228: signed metric
            if (advance <= 0 || result.width + advance > kMaxWidth)
                break;
            result.name.push_back(static_cast<char>(c));
            result.width += advance;
        }
        return result;
    }

    // Queue a literal in the format consumed by FUN_0022c670 (the same records as FUN_0022c3d0).
    // The game owns the buffer. No guest allocation, shared fighter-table patch or host address enters RAM.
    inline bool enqueue(uint8_t *ram, const Text &text, int x, int y, uint8_t alpha)
    {
        if (text.name.empty() || text.name.size() > kMaxLength || x < -32768 || x > 32767 || y < -32768 || y > 32767)
            return false;
        const uint32_t cursor = read32(ram, kQueue);
        const uint32_t bytes = (11u + static_cast<uint32_t>(text.name.size()) + 2u) & ~1u;
        if (cursor < kQueue + 8 || (cursor & 1u) || cursor > kQueueEnd - bytes - 2)
            return false;
        std::memset(ram + cursor, 0, bytes + 2); // NUL, padding and end marker are deterministic too
        write<uint16_t>(ram, cursor, static_cast<uint16_t>(bytes / 2));
        write<int16_t>(ram, cursor + 2, static_cast<int16_t>(x));
        write<int16_t>(ram, cursor + 4, static_cast<int16_t>(y));
        write<uint16_t>(ram, cursor + 6, 0xfff0u);
        ram[cursor + 8] = 6; // game proportional font, including lowercase
        ram[cursor + 9] = 7; // game's white palette
        ram[cursor + 10] = alpha;
        std::memcpy(ram + cursor + 11, text.name.data(), text.name.size());
        write<uint32_t>(ram, kTextCursor, cursor + 12 + static_cast<uint32_t>(text.name.size()));
        write<uint32_t>(ram, kQueue, cursor + bytes);
        return true;
    }
}
