// Tekken 4 online session report. No game-state address is read here.
// TEKKEN4_NET_RESULT=<path> opts in; unset/empty/0 disables it. One path per process.
// Winner, score and match end remain unknown until the state probe proves them.
#pragma once

#include <cmath>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <locale>
#include <sstream>
#include <string>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#define TEKKEN4_RESULT_UNDEF_LEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#define TEKKEN4_RESULT_UNDEF_NOMINMAX
#endif
#include <windows.h>
#ifdef TEKKEN4_RESULT_UNDEF_LEAN
#undef WIN32_LEAN_AND_MEAN
#undef TEKKEN4_RESULT_UNDEF_LEAN
#endif
#ifdef TEKKEN4_RESULT_UNDEF_NOMINMAX
#undef NOMINMAX
#undef TEKKEN4_RESULT_UNDEF_NOMINMAX
#endif
#endif

namespace tekken4_online_result
{
    struct State
    {
        std::string path;
        std::string runId, detail;
        int slot = -1;
        bool configured = false, connected = false, ended = false;
        bool haveFrame = false, haveFps = false, haveHash = false;
        bool hashIncludesIop = false;
        uint64_t frame = 0, hashFrame = 0, hash = 0;
        double fps = 0;
        std::string reason = "session_configured";
    };

    // The rollback thread owns this cache. The exit callback uses only cached host
    // data; it never dereferences the runtime or waits for the hash worker.
    inline State &state()
    {
        static State s;
        return s;
    }

    inline bool enabled() { return !state().path.empty(); }

    inline std::string jsonString(const std::string &value)
    {
        std::string result = "\"";
        const char hex[] = "0123456789abcdef";
        for (unsigned char c : value)
        {
            if (c == '"' || c == '\\')
            {
                result += '\\';
                result += static_cast<char>(c);
            }
            else if (c < 0x20u)
            {
                result += "\\u00";
                result += hex[c >> 4u];
                result += hex[c & 15u];
            }
            else
                result += static_cast<char>(c);
        }
        result += '"';
        return result;
    }

    inline bool write()
    {
        const State &s = state();
        if (s.path.empty())
            return false;
        std::ostringstream out;
        out.imbue(std::locale::classic());
        out << "{\n  \"schema\": \"tekken4-online-session-v1\",\n"
               "  \"run_id\": " << jsonString(s.runId) << ",\n"
               "  \"reporting_finished\": " << (s.ended ? "true" : "false") << ",\n"
               "  \"connected\": " << (s.connected ? "true" : "false") << ",\n"
               "  \"local_slot\": " << (s.slot >= 0 ? std::to_string(s.slot + 1) : "null") << ",\n"
               "  \"winner\": null,\n  \"score\": null,\n  \"match_result_proven\": false,\n"
               "  \"frame\": " << (s.haveFrame ? std::to_string(s.frame) : "null") << ",\n"
               "  \"final_hash\": ";
        if (s.haveHash)
        {
            char hash[17];
            std::snprintf(hash, sizeof(hash), "%016llx", static_cast<unsigned long long>(s.hash));
            out << "{\"value\": \"" << hash << "\", \"frame\": " << s.hashFrame
                << ", \"kind\": \"latest_confirmed_sampled_boundary\", \"peer_agreement_proven\": false}";
        }
        else
            out << "null";
        out << ",\n  \"hash_scope\": \"RDRAM, scratchpad, VU0 data, EE cycle; excludes VU1 and GS\",\n"
               "  \"hash_includes_iop_state\": " << (s.haveHash ? (s.hashIncludesIop ? "true" : "false") : "null") << ",\n"
               "  \"fps\": ";
        if (s.haveFps)
            out << std::fixed << std::setprecision(3) << s.fps;
        else
            out << "null";
        out << ",\n  \"fps_basis\": \"live frame intervals per wall second since handshake; includes waits; excludes resimulation; not fight-only\",\n"
               "  \"reason\": " << jsonString(s.reason) << ",\n"
               "  \"reason_detail\": " << jsonString(s.detail) << ",\n"
               "  \"TODO_winner\": \"Probe must confirm winner field, width, P1/P2/draw encoding and terminal-state lifetime.\",\n"
               "  \"TODO_score\": \"Probe must confirm both round-win counters, widths, increment timing and reset lifetime.\",\n"
               "  \"TODO_match_end\": \"Probe must distinguish round end, match end, rematch/select and abort; no game match-end detector exists.\"\n}\n";

        // Write beside the destination, then replace it. A failed replacement
        // leaves the previous report intact and retains the temporary file.
        const std::string temporary = s.path + ".tmp";
        std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
        file << out.str();
        file.close();
        if (!file)
        {
            std::fprintf(stderr, "[T4 result] cannot write %s\n", temporary.c_str());
            return false;
        }
#ifdef _WIN32
        const bool replaced = MoveFileExA(temporary.c_str(), s.path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
        const bool replaced = std::rename(temporary.c_str(), s.path.c_str()) == 0;
#endif
        if (!replaced)
            std::fprintf(stderr, "[T4 result] cannot replace %s (temporary retained)\n", s.path.c_str());
        return replaced;
    }

    inline void finish(const char *reason, uint64_t frame, const char *detail = nullptr)
    {
        State &s = state();
        if (!enabled() || s.ended)
            return;
        s.frame = frame;
        s.haveFrame = true;
        s.reason = reason ? reason : "unknown_session_end";
        s.detail = detail ? detail : "";
        s.ended = true;
        write();
    }

    inline void atExit()
    {
        State &s = state();
        if (!enabled() || s.ended)
            return;
        s.reason = "process_exit";
        s.ended = true;
        write();
    }

    inline void configure(int slot)
    {
        State &s = state();
        if (s.configured)
            return;
        s.configured = true;
        const char *path = std::getenv("TEKKEN4_NET_RESULT");
        if (!path || !*path || std::string(path) == "0")
            return;
        s.path = path;
        s.slot = slot;
        // Local invocation identity only, not a shared match/session identifier.
        std::ostringstream id;
        id.imbue(std::locale::classic());
        id << std::hex << std::chrono::system_clock::now().time_since_epoch().count() << '-'
           << std::chrono::steady_clock::now().time_since_epoch().count();
        s.runId = id.str();
        if (std::atexit(atExit) != 0)
            std::fprintf(stderr, "[T4 result] cannot register process-exit report\n");
        write(); // Supersede a stale report even if this process is later killed.
    }

    inline void started(int slot)
    {
        State &s = state();
        if (!enabled() || s.ended)
            return;
        s.slot = slot;
        s.connected = true;
        s.reason = "session_started";
        write();
    }

    inline void liveFrame(uint64_t frame, double fps)
    {
        State &s = state();
        if (!enabled() || s.ended)
            return;
        s.frame = frame;
        s.haveFrame = true;
        s.haveFps = std::isfinite(fps) && fps >= 0;
        s.fps = fps;
    }

    inline void confirmedHash(uint64_t frame, uint64_t hash, bool includesIop)
    {
        State &s = state();
        if (!enabled() || s.ended || (s.haveHash && frame < s.hashFrame))
            return;
        s.hashFrame = frame;
        s.hash = hash;
        s.hashIncludesIop = includesIop;
        s.haveHash = true;
    }
}
