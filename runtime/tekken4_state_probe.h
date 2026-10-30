// Read-only SLUS-20328 discovery aid. No game-state field address is proven here.
// This is host state, deliberately outside rollback snapshots. Call only at a live boundary.
#pragma once

#include <cinttypes>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace tekken4_state_probe
{
    constexpr uint32_t kRamBytes = 32u * 1024u * 1024u;
    constexpr uint32_t kBlockBytes = 16u;

    struct Region
    {
        uint32_t address = 0, size = 0;
        std::vector<uint8_t> previous;
    };

    struct Candidate
    {
        const char *category = nullptr;
        uint32_t address = 0, width = 4;
    };

    struct State
    {
        bool initialized = false, active = false, haveFrame = false;
        uint64_t lastFrame = 0;
        std::chrono::steady_clock::time_point started{};
        FILE *file = nullptr;
        std::vector<Region> regions;
        std::vector<Candidate> candidates;

        ~State()
        {
            if (file)
                std::fclose(file);
        }
    };

    inline State &state()
    {
        static State value;
        return value;
    }

    inline bool number(const std::string &text, uint32_t &value)
    {
        if (text.empty() || text[0] == '-' || text[0] == '+' || text[0] == ' ')
            return false;
        char *end = nullptr;
        const unsigned long long parsed = std::strtoull(text.c_str(), &end, 0);
        if (!end || *end || parsed > kRamBytes)
            return false;
        value = static_cast<uint32_t>(parsed);
        return true;
    }

    inline bool regions(State &s, const std::string &text)
    {
        if (text == "none")
            return true;
        size_t start = 0;
        uint64_t total = 0;
        while (start < text.size())
        {
            const size_t end = text.find(',', start);
            const std::string item = text.substr(start, end == std::string::npos ? end : end - start);
            const size_t colon = item.find(':');
            Region region;
            if (colon == std::string::npos || !number(item.substr(0, colon), region.address) ||
                !number(item.substr(colon + 1), region.size) || !region.size ||
                uint64_t(region.address) + region.size > kRamBytes || s.regions.size() >= 64)
                return false;
            total += region.size;
            if (total > kRamBytes)
                return false;
            for (const auto &old : s.regions)
                if (uint64_t(region.address) < uint64_t(old.address) + old.size &&
                    uint64_t(old.address) < uint64_t(region.address) + region.size)
                    return false;
            s.regions.push_back(region);
            if (end == std::string::npos)
                return true;
            start = end + 1;
        }
        return false;
    }

    inline bool candidates(State &s, const char *environment, const char *category)
    {
        const char *configured = std::getenv(environment);
        if (!configured || !*configured)
            return true;
        const std::string text(configured);
        size_t start = 0;
        while (start < text.size())
        {
            const size_t end = text.find(',', start);
            const std::string item = text.substr(start, end == std::string::npos ? end : end - start);
            const size_t colon = item.find(':');
            Candidate candidate;
            candidate.category = category;
            if (!number(item.substr(0, colon), candidate.address) ||
                (colon != std::string::npos && !number(item.substr(colon + 1), candidate.width)) ||
                (candidate.width != 1 && candidate.width != 2 && candidate.width != 4) ||
                uint64_t(candidate.address) + candidate.width > kRamBytes || s.candidates.size() >= 192)
                return false;
            s.candidates.push_back(candidate);
            if (end == std::string::npos)
                return true;
            start = end + 1;
        }
        return false;
    }

    inline bool enabled()
    {
        State &s = state();
        if (s.initialized)
            return s.active;
        s.initialized = true;
        const char *switchValue = std::getenv("TEKKEN4_STATE_PROBE");
        if (!switchValue || std::strcmp(switchValue, "1") != 0)
            return false;
        const char *search = std::getenv("TEKKEN4_STATE_PROBE_RANGES");
        if (!regions(s, search && *search ? search : "0x300000:0x200000") ||
            !candidates(s, "TEKKEN4_STATE_PROBE_MODE", "mode") ||
            !candidates(s, "TEKKEN4_STATE_PROBE_ROUND", "round") ||
            !candidates(s, "TEKKEN4_STATE_PROBE_HEALTH", "health"))
        {
            std::fprintf(stderr, "[tekken4 probe] invalid configuration; probe disabled\n");
            return false;
        }
        const char *path = std::getenv("TEKKEN4_STATE_PROBE_FILE");
        s.file = std::fopen(path && *path ? path : "t4_state_probe.log", "a");
        if (!s.file)
        {
            std::fprintf(stderr, "[tekken4 probe] cannot open log; probe disabled\n");
            return false;
        }
        std::fprintf(s.file, "PROBE version=1 build=SLUS-20328-v1.00 live_only=1\n"
                            "NOTE all fields are unproven candidates; raw search ranges have no gameplay coverage guarantee\n"
                            "NOTE scan and log overhead changes timing; do not use this run as a performance measurement\n"
                            "FORMAT F frame elapsed_ms; C category address width raw_le_value; B/D address byte_count raw_bytes\n"
                            "NOTE B is baseline, D replaces changed bytes since previous sampled F; reconstruct little-endian values offline\n"
                            "TODO mode manager/select/round/winner/score/health addresses and semantics require annotation and validation\n");
        for (auto &region : s.regions)
        {
            std::fprintf(s.file, "RANGE %08x %08x discovery_only\n", region.address, region.size);
            region.previous.resize(region.size);
        }
        std::fflush(s.file);
        s.started = std::chrono::steady_clock::now();
        s.active = !std::ferror(s.file);
        std::fprintf(stderr, "[tekken4 probe] %s; candidates unproven, scan/log overhead affects timing\n",
                     s.active ? "enabled" : "log error; disabled");
        return s.active;
    }

    inline void sample(uint64_t frame, const uint8_t *rdram, bool resimulating)
    {
        // Logical resimulation, including no-cut tails and wrong-input test passes, must never emit.
        if (resimulating || !rdram || !enabled())
            return;
        State &s = state();
        if (s.haveFrame && frame <= s.lastFrame)
            return;
        const auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                                   std::chrono::steady_clock::now() - s.started).count();
        std::fprintf(s.file, "F %" PRIu64 " %" PRId64 "\n", frame, static_cast<int64_t>(elapsedMs));
        for (const auto &candidate : s.candidates)
        {
            uint32_t value = 0;
            for (uint32_t byte = 0; byte < candidate.width; ++byte)
                value |= uint32_t(rdram[candidate.address + byte]) << (byte * 8);
            std::fprintf(s.file, "C %s %08x %u %08x\n", candidate.category, candidate.address,
                         candidate.width, value);
        }
        static const char hex[] = "0123456789abcdef";
        for (auto &region : s.regions)
        {
            for (uint32_t offset = 0; offset < region.size; offset += kBlockBytes)
            {
                const uint32_t count = region.size - offset < kBlockBytes ? region.size - offset : kBlockBytes;
                const uint8_t *bytes = rdram + region.address + offset;
                uint8_t *previous = region.previous.data() + offset;
                if (s.haveFrame && std::memcmp(previous, bytes, count) == 0)
                    continue;
                char encoded[kBlockBytes * 2 + 1];
                for (uint32_t byte = 0; byte < count; ++byte)
                {
                    encoded[byte * 2] = hex[bytes[byte] >> 4];
                    encoded[byte * 2 + 1] = hex[bytes[byte] & 15u];
                }
                encoded[count * 2] = '\0';
                std::fprintf(s.file, "%c %08x %u %s\n", s.haveFrame ? 'D' : 'B',
                             region.address + offset, count, encoded);
                std::memcpy(previous, bytes, count);
            }
        }
        std::fflush(s.file);
        s.lastFrame = frame;
        s.haveFrame = true;
        if (std::ferror(s.file))
        {
            s.active = false;
            std::fprintf(stderr, "[tekken4 probe] log error; probe disabled (capture incomplete)\n");
        }
    }
}
