// Tekken 4 online session report + the match result. No game-state address is read here: the match comes from
// tekken4_match_state.h (decided on confirmed frames only) through matchEnded().
// TEKKEN4_NET_RESULT=<path> opts in; unset/empty/0 disables it. One path per process.
// The first match of the session is the lobby match: its result is written once its deciding frame is confirmed
// and the state hash of the first hashed frame at or after it has been compared with the peer's (or after a bound).
#pragma once

#include "tekken4_match_state.h"
#include <vector>

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
        // the match (first one of the session)
        std::string matchId;              // TEKKEN4_NET_MATCH (the lobby's match id), "" offline
        bool haveMatch = false, matchFinal = false;
        tekken4_match::MatchEnd match;
        uint64_t matchHashTarget = 0;     // first hashed frame >= the deciding frame
        bool haveMatchHash = false;
        uint64_t matchHash = 0;
        int matchHashAgreement = 0;       // t4net::hashAgreement of that frame (1 equal, -1 different, 0/2 unknown)
        uint32_t desync = 0, hashesCompared = 0;
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
        // winner 0 = P1, 1 = P2, null = draw or no result: read it only when match_result_proven is true.
        const bool proven = s.matchFinal && s.match.consistent;
        out << "{\n  \"schema\": \"tekken4-online-session-v2\",\n"
               "  \"run_id\": " << jsonString(s.runId) << ",\n"
               "  \"match\": " << (s.matchId.empty() ? std::string("null") : jsonString(s.matchId)) << ",\n"
               "  \"reporting_finished\": " << (s.ended ? "true" : "false") << ",\n"
               "  \"connected\": " << (s.connected ? "true" : "false") << ",\n"
               "  \"local_slot\": " << (s.slot >= 0 ? std::to_string(s.slot + 1) : "null") << ",\n"
               "  \"match_result_proven\": " << (proven ? "true" : "false") << ",\n"
               "  \"winner\": " << (proven && s.match.winner >= 0 ? std::to_string(s.match.winner) : "null") << ",\n"
               "  \"draw\": " << (proven && s.match.winner < 0 ? "true" : "false") << ",\n"
               "  \"score\": ";
        if (proven)
            out << "[" << s.match.score[0] << ", " << s.match.score[1] << "]";
        else
            out << "null";
        if (s.matchFinal)
        {
            const tekken4_match::MatchEnd &m = s.match;
            out << ",\n  \"chars\": [" << m.chars[0] << ", " << m.chars[1] << "],\n"
                   "  \"costumes\": [" << m.costumes[0] << ", " << m.costumes[1] << "],\n"
                   "  \"stage\": " << m.stage << ",\n"
                   "  \"rounds_to_win\": " << m.roundsToWin << ",\n"
                   "  \"match_code\": " << m.code << ",\n"
                   "  \"match_start_frame\": " << m.startFrame << ",\n"
                   "  \"match_end_frame\": " << m.frame << ",\n"
                   "  \"frames\": " << m.frame << ",\n"
                   "  \"rounds\": [";
            for (size_t i = 0; i < m.rounds.size(); ++i)
            {
                const tekken4_match::Round &r = m.rounds[i];
                out << (i ? ", " : "") << "{\"frame\": " << r.frame << ", \"winner\": "
                    << (r.winner >= 0 ? std::to_string(r.winner) : std::string("null")) << ", \"by\": \""
                    << (r.timeOut ? "time" : "ko") << "\", \"health\": [" << (r.health[0] >> 16) << ", "
                    << (r.health[1] >> 16) << "]}";
            }
            out << "],\n  \"hash\": ";
            if (s.haveMatchHash)
            {
                char hash[17];
                std::snprintf(hash, sizeof(hash), "%016llx", static_cast<unsigned long long>(s.matchHash));
                out << "\"" << hash << "\",\n  \"hash_frame\": " << s.matchHashTarget << ",\n  \"hash_agreed\": "
                    << (s.matchHashAgreement == 1 ? "true" : (s.matchHashAgreement == -1 ? "false" : "null"));
            }
            else
                out << "null,\n  \"hash_frame\": null,\n  \"hash_agreed\": null";
            out << ",\n  \"desync\": " << s.desync << ",\n  \"hashes_compared\": " << s.hashesCompared;
        }
        out << ",\n  \"frame\": " << (s.haveFrame ? std::to_string(s.frame) : "null") << ",\n"
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
               "  \"reason_detail\": " << jsonString(s.detail) << "\n}\n";

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
        if (s.haveMatch)
            s.matchFinal = true; // decided on confirmed frames; the hash comparison just did not finish
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
        if (const char *match = std::getenv("TEKKEN4_NET_MATCH"))
            s.matchId = std::string(match).substr(0, 64);
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
        if (!enabled())
            return;
        if (s.haveMatch && !s.haveMatchHash && frame == s.matchHashTarget)
        {
            s.haveMatchHash = true;
            s.matchHash = hash;
        }
        if (s.ended || (s.haveHash && frame < s.hashFrame))
            return;
        s.hashFrame = frame;
        s.hash = hash;
        s.hashIncludesIop = includesIop;
        s.haveHash = true;
    }

    // The session's first match ended on a confirmed frame. hashEvery: the netplay hash interval (0 = none).
    inline void matchEnded(const tekken4_match::MatchEnd &end, uint64_t hashEvery)
    {
        State &s = state();
        if (!enabled() || s.haveMatch)
            return;
        s.haveMatch = true;
        s.match = end;
        s.matchHashTarget = hashEvery ? (end.frame + hashEvery - 1u) / hashEvery * hashEvery : 0u;
    }

    inline bool matchPending() { return enabled() && state().haveMatch && !state().matchFinal; }
    inline uint64_t matchHashTarget() { return state().matchHashTarget; }
    inline bool matchHashKnown() { return state().haveMatchHash; }
    inline uint64_t matchFrame() { return state().match.frame; }

    // Writes the match result (once). agreement: t4net::hashAgreement(target), desync/compared: totals so far.
    inline void finalizeMatch(int agreement, uint32_t desync, uint32_t compared)
    {
        State &s = state();
        if (!enabled() || !s.haveMatch || s.matchFinal)
            return;
        s.matchFinal = true;
        s.matchHashAgreement = agreement;
        s.desync = desync;
        s.hashesCompared = compared;
        write();
    }
}
