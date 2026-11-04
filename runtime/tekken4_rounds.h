#pragma once
// Negotiated online Round option, SLUS-20328 v1.00. Zero means retain the game's option.
#include <cstdint>
#include <cstdlib>
#include <initializer_list>

namespace tekken4_rounds
{
    constexpr uint32_t kSetter = 0x00197b68u;
    constexpr uint32_t kActive = 0x00357d74u;
    constexpr uint32_t kVsOption = 0x002a8c23u;

    struct Settings
    {
        bool valid = true;
        uint32_t value = 0;
    };

    inline Settings parse(const char *text)
    {
        if (!text || !*text)
            return {};
        // The game's own VS setup supports 1..5. Do not silently normalize malformed tickets.
        if (text[0] < '1' || text[0] > '5' || text[1])
            return {false, 0};
        return {true, static_cast<uint32_t>(text[0] - '0')};
    }

    inline const Settings &settings()
    {
        static const Settings s = []
        {
#ifdef _MSC_VER
            char *text = nullptr;
            size_t size = 0;
            if (_dupenv_s(&text, &size, "TEKKEN4_NET_ROUNDS"))
                return Settings{false, 0};
            const auto result = parse(text);
            std::free(text);
            return result;
#else
            return parse(std::getenv("TEKKEN4_NET_ROUNDS"));
#endif
        }();
        return s;
    }

    inline uint64_t fingerprint(uint64_t hash, const Settings &s)
    {
        if (!hash)
            hash = 14695981039346656037ull;
        // Versioned setter contract; distinguish preserving the option from an explicit target.
        for (uint32_t value : {1u, kSetter, kActive, s.value})
            for (unsigned i = 0; i < 4; ++i)
            {
                hash ^= static_cast<uint8_t>(value >> (8u * i));
                hash *= 1099511628211ull;
            }
        return hash ? hash : 1u;
    }
}
