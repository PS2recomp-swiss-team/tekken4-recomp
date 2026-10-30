// Tekken 4 (SLUS-20328, NTSC-U v1.00) overrides for PS2Recomp's ps2xRuntime.
// tools\stage_generated.cmd copies this file into ps2xRuntime/src/runner next to the generated code.
// Addresses are for this ELF only (matched by name, entry point and CRC32 below).
#include "game_overrides.h"
#include "ps2_runtime.h"
#include "ps2_stubs.h"
#include "ps2_syscalls.h"
#include "runtime/ps2_audio.h"
#include "runtime/ps2_memory.h"
#include "ps2x/iop/iop_host.h"
#include "runtime/gs/gs_frontend.h"
#include "Stubs/CD.h"
#include "Stubs/MPEG.h"
#include <ps2_recompiled_functions.h>

#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#define NOGDI  // raylib shares this unity build: no Rectangle,
#define NOUSER // CloseWindow, ShowCursor from windows.h
#include <windows.h>
#include <dbghelp.h> // SYMBOL_INFO only: the functions are loaded at run time
#include <tlhelp32.h>
#endif

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace tekken4
{
    // Namco's sound driver runs on the IOP and serves SIF RPC id 0x12345. Its EE library (0x222788-0x2237f8)
    // binds one client (0x1cca440) and only makes synchronous calls: 4 words in at 0x1cc9f80 (the per-frame
    // call 0x100 sends a 0x80-byte command queue at 0x1cca040 instead), 8 words back at 0x1cca000.
    // FUN_00222788 retries the bind every vsync until client.server != 0, so without a server boot stops there.
    // TEKKEN4_SOUND=1 plus an ISO forwards this SID to zsiopdrv, except mode-0 disc reads and the movie
    // calls (0x3000/0x3100/0x3200), which stay on the local HLE. Without that env every call is answered
    // at once with a zeroed reply: no sound.
    constexpr uint32_t kSoundSid = 0x12345u;
    constexpr uint32_t kSceSifBindRpc = 0x00281bc8u;
    constexpr uint32_t kSceSifCallRpc = 0x00281d98u;
    constexpr uint32_t kSceSifCheckStatRpc = 0x00281f88u;
    constexpr uint32_t kSceSifSendCmd = 0x00281300u;
    constexpr uint32_t kSifCmdSetSreg = 0x80000001u; // ps2sdk SIF_CMD_SET_SREG, packet+16 index, packet+20 value

    // t_SifRpcClientData: 16-byte header, then command, buf, cbuf, end_function, end_param, server.
    constexpr uint32_t kClientBodyOffset = 0x10u;
    constexpr uint32_t kClientBodySize = 0x18u;
    constexpr uint32_t kClientServerOffset = 0x24u;
    constexpr uint32_t kMaxReplySize = 0x1000u;
    constexpr uint32_t kSoundFrameCall = 0x100u; // FUN_00222958, once per pass of the main loop (FUN_001969f8)

    // The same driver is the game's disc loader. FUN_00214cb8 sends call 0x200 with (sector, EE destination,
    // size, mode) in the 4 send words. Sectors count from the start of TEKKEN/DATA.BIN (file table at 0x3133e0:
    // sector, size, checksum, key; with that base every checksum matches). When the read is done the driver
    // triggers callback 0x2289c8, which does done_flag += 1 at gp-0x5148 = 0x357a28; the loader polls that flag
    // (FUN_00228e50), decrypts the first 4 KB (~word + key) and checks the file's checksum.
    constexpr uint32_t kDiscReadCall = 0x200u;
    constexpr uint32_t kDiscReadDoneFlag = 0x00357a28u;
    // Where TEKKEN/DATA.BIN sits on this disc (ISO9660 directory of SLUS-20328 v1.00).
    constexpr uint64_t kDataBinLbn = 401u;
    constexpr uint64_t kDataBinSize = 2695536640u;
    std::ifstream g_disc;            // the ISO, or else a loose DATA.BIN extracted next to the ELF
    uint64_t g_discBase = 0u;        // byte offset of DATA.BIN inside g_disc
    bool g_discTried = false;
    bool g_realSound = false;        // TEKKEN4_SOUND=1 and an ISO: SID 0x12345 reaches zsiopdrv

    // TEKKEN4_ISO, else the first .iso in the project root (the ELF lives in <root>/game/disc).
    std::filesystem::path findIsoPath()
    {
        const PS2Runtime::IoPaths &paths = PS2Runtime::getIoPaths();
        std::error_code ec;
        if (const char *env = std::getenv("TEKKEN4_ISO"))
        {
            if (env[0] != '\0')
                return env;
        }
        for (const auto &entry : std::filesystem::directory_iterator(paths.elfDirectory.parent_path().parent_path(), ec))
            if (!ec && entry.path().extension() == ".iso")
                return entry.path();
        return {};
    }

    // The ISO comes first: it holds the whole disc, so a sector past DATA.BIN (DATA2.BIN follows it) reads as on
    // a console. A loose TEKKEN/DATA.BIN is only a fallback for setups without the image.
    bool openDisc()
    {
        if (g_discTried)
            return g_disc.is_open();
        g_discTried = true;
        std::filesystem::path source = findIsoPath();
        if (!source.empty())
        {
            g_disc.open(source, std::ios::binary);
            g_discBase = kDataBinLbn * 2048u;
        }
        if (!g_disc.is_open())
        {
            std::error_code ec;
            source = PS2Runtime::getIoPaths().cdRoot / "TEKKEN" / "DATA.BIN";
            if (std::filesystem::exists(source, ec))
            {
                g_disc.open(source, std::ios::binary);
                g_discBase = 0u;
            }
        }
        RUNTIME_LOG("[tekken4] driver reads from "
                    << (g_disc.is_open() ? source.string() : std::string("NOTHING (no ISO, no DATA.BIN; set TEKKEN4_ISO)"))
                    << "\n");
        return g_disc.is_open();
    }

    void discRead(uint8_t *rdram, uint32_t sendAddr)
    {
        uint32_t args[4] = {};
        if (const uint8_t *send = getMemPtr(rdram, sendAddr))
            std::memcpy(args, send, sizeof(args));
        const uint32_t sector = args[0], dest = args[1], size = args[2], mode = args[3];
        const uint32_t phys = dest & 0x01FFFFFFu;
        bool copied = false;
        if (mode == 0u && size != 0u && phys + static_cast<uint64_t>(size) <= PS2_RAM_SIZE && openDisc())
        {
            const uint64_t offset = static_cast<uint64_t>(sector) * 2048u;
            if (offset >= kDataBinSize) // not seen yet: from the ISO it reads on into DATA2.BIN, a loose DATA.BIN fails
                RUNTIME_LOG("[tekken4] sector " << sector << " is past DATA.BIN\n");
            g_disc.clear();
            g_disc.seekg(static_cast<std::streamoff>(g_discBase + offset));
            g_disc.read(reinterpret_cast<char *>(rdram + phys), size);
            copied = g_disc.gcount() == static_cast<std::streamsize>(size);
        }
        RUNTIME_LOG("[tekken4] disc read sector " << sector << " size " << size << " -> 0x" << std::hex << dest
                                                  << " mode " << mode << std::dec
                                                  << (copied ? "" : " (not copied: mode/size/file)") << "\n");
        uint32_t done = 0u;
        std::memcpy(&done, rdram + kDiscReadDoneFlag, 4);
        ++done;
        std::memcpy(rdram + kDiscReadDoneFlag, &done, 4);
    }

    // Movies (player FUN_00227bd8). Call 0x3000 (sector, size, file, mode) opens a movie file; each 0x3200
    // (EE destination, sectors) then asks for the next sectors of its video, into a ring the player decodes with
    // libmpeg. The files interleave 0x27 sectors of MPEG-2 video with 2 sectors of SPU ADPCM audio, which the
    // driver keeps (PCSX2's ring holds the video units back to back). The driver answers with SIF command 4,
    // whose handler 0x2289f0 stores the byte count at gp-0x5144 = 0x357a2c; the player sets it to -1 before
    // asking (FUN_002287a8). Call 0x3100 closes the stream. Mode 1 (0x10000-byte requests) is not verified yet.
    constexpr uint32_t kMovieOpenCall = 0x3000u;
    constexpr uint32_t kMovieReadCall = 0x3200u;
    constexpr uint32_t kMovieCloseCall = 0x3100u;
    constexpr uint32_t kMovieReadResult = 0x00357a2cu;
    constexpr uint32_t kMovieVideoBytes = 0x27u * 2048u; // per interleave unit
    constexpr uint32_t kMovieAudioBytes = 2u * 2048u;
    // The driver's per-frame reply (call 0x100, word 3) carries the movie stream's status: 0x200 = its audio is
    // ready (FUN_002286e0; the player starts the sound and the picture display only then), 0x100 = the stream has
    // ended (FUN_002286d0).
    constexpr uint32_t kFrameReplyStatusWord = 3u;
    constexpr uint32_t kStatusMovieAudioReady = 0x200u;
    constexpr uint32_t kStatusMovieEnded = 0x100u;
    uint32_t g_movieSector = 0u;
    uint32_t g_movieSize = 0u;
    uint32_t g_movieVideoPos = 0u; // video bytes already delivered
    bool g_movieEnded = false;
    // Predictor state for the two SPU ADPCM channels. The 4096-byte audio pair after each video unit is
    // 16-byte left blocks interleaved with 16-byte right blocks (flag byte 0x02 on every block).
    int32_t g_movieHist[2][2] = {};
    uint32_t g_movieAudioUnits = 0u;
    // The audio sectors are 44.1 kHz stereo: 3584 frames per unit = 81.3 ms, and the 1519 units that carry audio
    // last 123.4 s against 122.6 s of video (3675 pictures at 29.97 fps). Played as 48 kHz (before 2026-10-30) the
    // sound ran 8.8 % fast and high, and the queue ran dry before the next unit arrived (gaps every unit: the
    // "choppy" intro). The runtime hands the 29.97 fps pictures out on its 60.000 Hz vsync, i.e. at 30.000 fps
    // (measured: 3643 pictures in 121.40 s), so the sound is consumed 30/29.97 faster too (44144 Hz, +1.7 cents) or
    // it would fall 0.1 % (120 ms over the intro) behind the picture. TEKKEN4_MOVIE_AUDIO_HZ=<rate> overrides the
    // source rate (48000 = the old behaviour, 44100 = without the vsync correction).
    double g_movieSourceHz = 44100.0 * 30.0 / 29.97;
    // The first unit is read (and its sound was queued) ~80 ms before the decoder hands out the first picture; the
    // sound is held until then so it starts with the picture.
    std::vector<int16_t> g_movieHeldPcm;
    uint32_t g_movieServedAtOpen = 0u;
    bool g_movieAudioStarted = false;

    void pushMoviePcm(const int16_t *frames, size_t count)
    {
        if (!g_movieAudioStarted && ps2_stubs::mpegPicturesServed() != g_movieServedAtOpen)
        {
            g_movieAudioStarted = true;
            if (!g_movieHeldPcm.empty())
                ps2PushMoviePcm(g_movieHeldPcm.data(), g_movieHeldPcm.size() / 2u);
            g_movieHeldPcm.clear();
        }
        if (!g_movieAudioStarted)
            g_movieHeldPcm.insert(g_movieHeldPcm.end(), frames, frames + count * 2u);
        else if (count != 0u)
            ps2PushMoviePcm(frames, count);
    }
    // Streaming 4-point (Catmull-Rom) resampler, source rate -> the mixer's 48 kHz, continuous across units.
    std::vector<int16_t> g_movieCarry; // stereo source frames not consumed yet (the first is the cubic's x[-1])
    double g_moviePos = 1.0;           // read position in g_movieCarry frames
    // TEKKEN4_MOVIE_SYNC=1: once a second while a movie plays (from the per-frame sound call), pictures handed out
    // vs audio played (A/V offset) and gaps; at the close, picture intervals (stutter) and the totals.
    bool g_movieSyncLog = false;
    std::chrono::steady_clock::time_point g_movieT0{}, g_movieNextLog{};

    void resetMovieResampler()
    {
        g_movieCarry.clear();
        g_moviePos = 1.0;
    }

    void resampleMovieAudio(const int16_t *frames, size_t count, std::vector<int16_t> &out)
    {
        const bool first = g_movieCarry.empty();
        if (first) // x[-1] = x[0] for the very first output
            g_movieCarry.insert(g_movieCarry.end(), frames, frames + 2u);
        g_movieCarry.insert(g_movieCarry.end(), frames, frames + count * 2u);
        const double step = g_movieSourceHz / 48000.0;
        const size_t have = g_movieCarry.size() / 2u;
        while (g_moviePos + 2.0 < static_cast<double>(have))
        {
            const size_t i = static_cast<size_t>(g_moviePos);
            const double t = g_moviePos - static_cast<double>(i);
            for (size_t c = 0; c < 2u; ++c)
            {
                const double p0 = g_movieCarry[(i - 1u) * 2u + c], p1 = g_movieCarry[i * 2u + c];
                const double p2 = g_movieCarry[(i + 1u) * 2u + c], p3 = g_movieCarry[(i + 2u) * 2u + c];
                const double v = p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)));
                out.push_back(static_cast<int16_t>(std::clamp(v, -32768.0, 32767.0)));
            }
            g_moviePos += step;
        }
        const size_t drop = static_cast<size_t>(g_moviePos) - 1u; // keep x[-1] of the next output
        g_movieCarry.erase(g_movieCarry.begin(), g_movieCarry.begin() + static_cast<std::ptrdiff_t>(drop * 2u));
        g_moviePos -= static_cast<double>(drop);
    }

    // TEKKEN4_MOVIE_SYNC: A/V offset = movie time of the sound played (48 kHz frames the mixer took from the movie
    // queue, scaled back to the 44.1 kHz source) minus that of the pictures sceMpegGetPicture handed out (29.97 fps);
    // > 0 = sound ahead of the picture.
    void movieSyncTick()
    {
        if (!g_movieSyncLog || g_movieSize == 0u)
            return;
        const auto now = std::chrono::steady_clock::now();
        if (now < g_movieNextLog)
            return;
        g_movieNextLog = now + std::chrono::seconds(1);
        const Ps2MoviePcmStats a = ps2MoviePcmStats();
        const ps2_stubs::MpegServeStats v = ps2_stubs::mpegServeStats();
        // both in movie time: the sound's 44.1 kHz frames played, the pictures at their 29.97 fps
        const double audioS = static_cast<double>(a.played) / 48000.0 * g_movieSourceHz / 44100.0;
        const double videoS = static_cast<double>(v.count) / 29.97;
        RUNTIME_LOG("[tekken4] movie sync t=" << std::fixed << std::setprecision(2)
                                              << std::chrono::duration<double>(now - g_movieT0).count() << " s: pictures "
                                              << v.count << " (" << videoS << " s), audio played " << audioS
                                              << " s, A-V " << (audioS - videoS) * 1000.0 << " ms, gaps "
                                              << static_cast<double>(a.missing) / 48.0 << " ms, queued "
                                              << static_cast<double>(a.queued) / 48.0 << " ms, units " << g_movieAudioUnits
                                              << std::defaultfloat << "\n");
    }

    void movieSyncSummary()
    {
        if (!g_movieSyncLog)
            return;
        const Ps2MoviePcmStats a = ps2MoviePcmStats();
        const ps2_stubs::MpegServeStats v = ps2_stubs::mpegServeStats();
        RUNTIME_LOG("[tekken4] movie summary: " << v.count << " pictures in " << v.spanMs / 1000.0 << " s ("
                                                << (v.spanMs > 0.0 ? (v.count - 1u) * 1000.0 / v.spanMs : 0.0)
                                                << " fps), intervals <20/20-28/28-38/38-45/45-60/>=60 ms: "
                                                << v.intervals[0] << "/" << v.intervals[1] << "/" << v.intervals[2] << "/"
                                                << v.intervals[3] << "/" << v.intervals[4] << "/" << v.intervals[5]
                                                << ", max " << v.maxIntervalMs << " ms; audio played "
                                                << static_cast<double>(a.played) / 48000.0 << " s, gaps "
                                                << static_cast<double>(a.missing) / 48.0 << " ms, " << g_movieAudioUnits
                                                << " units\n");
    }

    void decodeMovieAdpcm(const uint8_t *block, int32_t &hist1, int32_t &hist2, int16_t *out)
    {
        static constexpr int32_t kFilters[5][2] = {{0, 0}, {60, 0}, {115, -52}, {98, -55}, {122, -60}};
        uint32_t shift = block[0] & 0xFu;
        if (shift > 12u)
            shift = 9u;
        const uint32_t filter = std::min<uint32_t>((block[0] >> 4u) & 7u, 4u);
        const int32_t f0 = kFilters[filter][0];
        const int32_t f1 = kFilters[filter][1];
        uint32_t n = 0u;
        for (uint32_t word = 1; word < 8u; ++word)
        {
            const uint16_t packed = static_cast<uint16_t>(block[word * 2u] | (block[word * 2u + 1u] << 8u));
            for (uint32_t nibble = 0; nibble < 4u; ++nibble)
            {
                const int32_t raw = static_cast<int16_t>(((packed >> (nibble * 4u)) & 0xFu) << 12u) >> shift;
                const int32_t predicted = (hist1 * f0 + hist2 * f1 + 32) >> 6;
                const int32_t sample = std::clamp(raw + predicted, -32768, 32767);
                hist2 = hist1;
                hist1 = sample;
                out[n++] = static_cast<int16_t>(sample);
            }
        }
    }

    // One interleave unit is 81.3 ms of 44.1 kHz stereo (128 block pairs x 28 samples), resampled to 48 kHz and
    // queued onto the mixer clock, so a read-ahead ring plays out in guest time instead of as a burst.
    void queueMovieAudio(uint32_t unit)
    {
        if (!g_realSound || !openDisc())
            return;
        const uint64_t fileOffset = static_cast<uint64_t>(unit) * (kMovieVideoBytes + kMovieAudioBytes) + kMovieVideoBytes;
        if (fileOffset + kMovieAudioBytes > g_movieSize)
            return;
        uint8_t raw[kMovieAudioBytes];
        g_disc.clear();
        g_disc.seekg(static_cast<std::streamoff>(g_discBase + static_cast<uint64_t>(g_movieSector) * 2048u + fileOffset));
        g_disc.read(reinterpret_cast<char *>(raw), kMovieAudioBytes);
        if (g_disc.gcount() != static_cast<std::streamsize>(kMovieAudioBytes))
            return;
        constexpr uint32_t kBlocks = kMovieAudioBytes / 32u;
        constexpr uint32_t kFrames = kBlocks * 28u;
        std::vector<int16_t> pcm(kFrames * 2u);
        for (uint32_t block = 0; block < kBlocks; ++block)
        {
            int16_t left[28], right[28];
            decodeMovieAdpcm(raw + block * 32u, g_movieHist[0][0], g_movieHist[0][1], left);
            decodeMovieAdpcm(raw + block * 32u + 16u, g_movieHist[1][0], g_movieHist[1][1], right);
            for (uint32_t i = 0; i < 28u; ++i)
            {
                pcm[(block * 28u + i) * 2u] = left[i];
                pcm[(block * 28u + i) * 2u + 1u] = right[i];
            }
        }
        std::vector<int16_t> out;
        out.reserve((static_cast<size_t>(kFrames * 48000.0 / g_movieSourceHz) + 8u) * 2u);
        resampleMovieAudio(pcm.data(), kFrames, out);
        pushMoviePcm(out.data(), out.size() / 2u);
        if (g_movieAudioUnits++ == 0u)
            RUNTIME_LOG("[tekken4] movie audio: unit " << unit << " -> " << kFrames << " stereo frames at "
                                                       << g_movieSourceHz << " Hz -> " << out.size() / 2u << " at 48000 Hz\n");
    }

    void movieOpen(uint8_t *rdram, uint32_t sendAddr)
    {
        uint32_t args[4] = {};
        if (const uint8_t *send = getMemPtr(rdram, sendAddr))
            std::memcpy(args, send, sizeof(args));
        g_movieSector = args[0];
        g_movieSize = args[1];
        g_movieVideoPos = 0u;
        g_movieEnded = false;
        g_movieHist[0][0] = g_movieHist[0][1] = g_movieHist[1][0] = g_movieHist[1][1] = 0;
        g_movieAudioUnits = 0u;
        ps2ClearMoviePcm();
        resetMovieResampler();
        g_movieHeldPcm.clear();
        g_movieAudioStarted = false;
        g_movieServedAtOpen = ps2_stubs::mpegPicturesServed();
        (void)ps2_stubs::mpegServeStats(true);
        g_movieT0 = std::chrono::steady_clock::now();
        g_movieNextLog = g_movieT0 + std::chrono::seconds(1);
        RUNTIME_LOG("[tekken4] movie open: file 0x" << std::hex << args[2] << " sector " << std::dec << args[0]
                                                   << " size " << args[1] << " mode " << args[3]
                                                   << (args[3] != 0u ? " (mode 1 layout unverified)" : "") << "\n");
    }

    void movieRead(uint8_t *rdram, uint32_t sendAddr)
    {
        uint32_t args[2] = {};
        if (const uint8_t *send = getMemPtr(rdram, sendAddr))
            std::memcpy(args, send, sizeof(args));
        const uint32_t phys = args[0] & 0x01FFFFFFu;
        uint32_t want = args[1] * 2048u;
        if (phys + static_cast<uint64_t>(want) > PS2_RAM_SIZE)
            want = 0u;
        uint32_t done = 0u;
        while (done < want && openDisc())
        {
            // Video offset -> file offset: skip the audio sectors of every unit before it.
            const uint32_t unit = g_movieVideoPos / kMovieVideoBytes;
            const uint32_t inUnit = g_movieVideoPos % kMovieVideoBytes;
            if (inUnit == 0u)
                queueMovieAudio(unit);
            const uint64_t fileOffset = static_cast<uint64_t>(unit) * (kMovieVideoBytes + kMovieAudioBytes) + inUnit;
            if (fileOffset >= g_movieSize)
            {
                g_movieEnded = true;
                break;
            }
            uint32_t n = std::min(want - done, kMovieVideoBytes - inUnit);
            n = static_cast<uint32_t>(std::min<uint64_t>(n, g_movieSize - fileOffset));
            g_disc.clear();
            g_disc.seekg(static_cast<std::streamoff>(g_discBase + static_cast<uint64_t>(g_movieSector) * 2048u + fileOffset));
            g_disc.read(reinterpret_cast<char *>(rdram + phys + done), n);
            const uint32_t got = static_cast<uint32_t>(g_disc.gcount());
            done += got;
            g_movieVideoPos += got;
            if (got != n)
                break;
        }
        std::memcpy(rdram + kMovieReadResult, &done, 4);
    }

#ifdef _WIN32
    // Debug aid (TEKKEN4_PROFILE=<start s>:<seconds>): from <start> on, samples the game thread's instruction
    // pointer about every millisecond for <seconds>, then logs the functions it was in most often (names from the
    // PDB through dbghelp). The game thread is taken from the first per-frame sound call.
    // TEKKEN4_PROFILE_THREADS=all also samples every other thread of the process (GS drawing threads, IOP, ...)
    // and logs them as a second, combined list.
    std::atomic<HANDLE> g_gameThread{nullptr};

    // nameFilter: only threads whose description (SetThreadDescription, e.g. "GSThread") contains it; empty = all.
    std::vector<HANDLE> otherProcessThreads(DWORD gameThreadId, const std::string &nameFilter = {})
    {
        std::vector<HANDLE> threads;
        const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
        if (snapshot == INVALID_HANDLE_VALUE)
            return threads;
        THREADENTRY32 entry{};
        entry.dwSize = sizeof(entry);
        for (BOOL ok = Thread32First(snapshot, &entry); ok; ok = Thread32Next(snapshot, &entry))
        {
            if (entry.th32OwnerProcessID != GetCurrentProcessId() || entry.th32ThreadID == GetCurrentThreadId() ||
                entry.th32ThreadID == gameThreadId)
                continue;
            HANDLE h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_LIMITED_INFORMATION, FALSE,
                                 entry.th32ThreadID);
            if (!h)
                continue;
            if (!nameFilter.empty())
            {
                PWSTR description = nullptr;
                std::string name;
                if (SUCCEEDED(GetThreadDescription(h, &description)) && description)
                {
                    for (const wchar_t *c = description; *c; ++c)
                        name.push_back(static_cast<char>(*c < 128 ? *c : '?'));
                    LocalFree(description);
                }
                if (name.find(nameFilter) == std::string::npos)
                {
                    CloseHandle(h);
                    continue;
                }
            }
            threads.push_back(h);
        }
        CloseHandle(snapshot);
        return threads;
    }

    void sampleThread(HANDLE thread, std::unordered_map<DWORD64, uint32_t> &samples, uint32_t &total)
    {
        if (SuspendThread(thread) == static_cast<DWORD>(-1))
            return;
        CONTEXT c{};
        c.ContextFlags = CONTEXT_CONTROL;
        if (GetThreadContext(thread, &c))
        {
            ++samples[c.Rip];
            ++total;
        }
        ResumeThread(thread);
    }

    void captureGameThread()
    {
        if (g_gameThread.load())
            return;
        HANDLE h = nullptr;
        if (DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &h,
                            THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, 0))
            g_gameThread = h;
    }

    void startProfiler(const char *spec)
    {
        const double start = std::atof(spec);
        const char *colon = std::strchr(spec, ':');
        const double seconds = colon ? std::atof(colon + 1) : 10.0;
        // TEKKEN4_PROFILE_THREADS=all: every other thread; =<name>: only threads whose description contains it
        // (e.g. GSThread = the GL renderer's thread).
        const char *threadsEnv = std::getenv("TEKKEN4_PROFILE_THREADS");
        const bool allThreads = threadsEnv && *threadsEnv;
        const std::string threadFilter = (allThreads && std::strcmp(threadsEnv, "all") != 0) ? threadsEnv : "";
        std::thread([start, seconds, allThreads, threadFilter]() {
            std::this_thread::sleep_for(std::chrono::milliseconds(static_cast<int>(start * 1000.0)));
            HANDLE thread = g_gameThread.load();
            if (!thread)
                return;
            std::vector<HANDLE> others = allThreads ? otherProcessThreads(GetThreadId(thread), threadFilter) : std::vector<HANDLE>{};
            std::unordered_map<DWORD64, uint32_t> samples, otherSamples;
            uint32_t total = 0u, otherTotal = 0u;
            const auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(static_cast<int>(seconds * 1000.0));
            while (std::chrono::steady_clock::now() < end)
            {
                sampleThread(thread, samples, total);
                for (HANDLE other : others)
                    sampleThread(other, otherSamples, otherTotal);
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
            for (HANDLE other : others)
                CloseHandle(other);
            HMODULE dbghelp = LoadLibraryA("dbghelp.dll");
            using SymInitializeFn = BOOL(WINAPI *)(HANDLE, PCSTR, BOOL);
            using SymFromAddrFn = BOOL(WINAPI *)(HANDLE, DWORD64, PDWORD64, void *);
            using SymSetOptionsFn = DWORD(WINAPI *)(DWORD);
            auto symInitialize = dbghelp ? reinterpret_cast<SymInitializeFn>(GetProcAddress(dbghelp, "SymInitialize")) : nullptr;
            auto symFromAddr = dbghelp ? reinterpret_cast<SymFromAddrFn>(GetProcAddress(dbghelp, "SymFromAddr")) : nullptr;
            auto symSetOptions = dbghelp ? reinterpret_cast<SymSetOptionsFn>(GetProcAddress(dbghelp, "SymSetOptions")) : nullptr;
            const HANDLE process = GetCurrentProcess();
            const bool symbols = symInitialize && symFromAddr && (symSetOptions ? (symSetOptions(0x2 /*UNDNAME*/ | 0x4 /*DEFERRED*/), true) : true) &&
                                 symInitialize(process, nullptr, TRUE);
            auto report = [&](const std::unordered_map<DWORD64, uint32_t> &hits, uint32_t count, const char *what,
                              const char *tag) {
                std::unordered_map<std::string, uint32_t> byFunction;
                for (const auto &[ip, n] : hits)
                {
                    std::string name;
                    if (symbols)
                    {
                        alignas(8) char buffer[sizeof(SYMBOL_INFO) + 512] = {};
                        auto *info = reinterpret_cast<SYMBOL_INFO *>(buffer);
                        info->SizeOfStruct = sizeof(SYMBOL_INFO);
                        info->MaxNameLen = 511;
                        DWORD64 displacement = 0;
                        if (symFromAddr(process, ip, &displacement, info))
                            name = info->Name;
                    }
                    if (name.empty())
                    {
                        std::ostringstream o;
                        o << "0x" << std::hex << ip;
                        name = o.str();
                    }
                    byFunction[name] += n;
                }
                std::vector<std::pair<uint32_t, std::string>> sorted;
                for (const auto &[name, n] : byFunction)
                    sorted.emplace_back(n, name);
                std::sort(sorted.rbegin(), sorted.rend());
                RUNTIME_LOG("[tekken4] " << tag << ": " << count << " samples of " << what << "\n");
                for (size_t i = 0; i < sorted.size() && i < 30u; ++i)
                    RUNTIME_LOG("[tekken4] " << tag << " " << std::fixed << std::setprecision(1)
                                             << 100.0 * sorted[i].first / std::max<uint32_t>(count, 1u) << "% "
                                             << sorted[i].second << "\n");
            };
            report(samples, total, "the game thread", "profile");
            if (allThreads)
            {
                std::ostringstream what;
                what << others.size() << " other threads";
                report(otherSamples, otherTotal, what.str().c_str(), "profile-threads");
            }
        }).detach();
    }
#endif

    std::mutex g_mutex;
    std::set<uint32_t> g_soundClients;
    std::set<uint32_t> g_loggedCalls;
    uint64_t g_frames = 0u;
    uint64_t g_nextFrameLog = 1u;
    std::chrono::steady_clock::time_point g_firstFrame;
    uint64_t g_gsDumpFrame = 0u; // TEKKEN4_GS_DUMP=<frame>, 0 = off

    // While the GS history records, every GIF packet the arbiter hands to the GS is also written out raw
    // (quadwords as "hi lo", the GIFtag first) to gif_packets_frame<N>.txt.
    std::mutex g_gifLogMutex;
    std::ofstream g_gifLog;

    void processGifPacketLogged(PS2Runtime &runtime, const uint8_t *data, uint32_t size)
    {
        {
            std::lock_guard<std::mutex> lock(g_gifLogMutex);
            if (g_gifLog.is_open())
            {
                g_gifLog << "packet " << std::dec << size << " bytes\n" << std::hex << std::setfill('0');
                for (uint32_t off = 0; off + 16u <= size; off += 16u)
                {
                    uint64_t lo = 0, hi = 0;
                    std::memcpy(&lo, data + off, 8);
                    std::memcpy(&hi, data + off + 8, 8);
                    g_gifLog << "  " << std::setw(4) << off << ": " << std::setw(16) << hi << " " << std::setw(16) << lo
                             << "\n";
                }
                g_gifLog << std::setfill(' ');
            }
        }
        runtime.gs().processGIFPacket(data, size);
    }

    // Debug aid: write the GS's last 512 events (register writes, draws, image transfers) and the display
    // registers to gs_dump_frame<N>.txt in the working directory.
    void dumpGs(PS2Runtime &runtime, uint64_t frame)
    {
        std::ofstream f("gs_dump_frame" + std::to_string(frame) + ".txt");
        const GSRegisters &p = runtime.memory().gs();
        f << std::hex << "PMODE " << p.pmode << " SMODE1 " << p.smode1 << " SMODE2 " << p.smode2 << "\nDISPFB1 "
          << p.dispfb1 << " DISPLAY1 " << p.display1 << "\nDISPFB2 " << p.dispfb2 << " DISPLAY2 " << p.display2
          << "\nBGCOLOR " << p.bgcolor << "\n";
        const GSDebugSnapshot s = runtime.gs().getDebugSnapshot();
        for (int c = 0; c < 2; ++c)
        {
            const GSContext &x = s.ctx[c];
            f << "ctx" << c << " FRAME fbp " << x.frame.fbp << " fbw " << x.frame.fbw << " psm " << +x.frame.psm
              << " | TEX0 tbp0 " << x.tex0.tbp0 << " tbw " << +x.tex0.tbw << " psm " << +x.tex0.psm << " tw "
              << +x.tex0.tw << " th " << +x.tex0.th << " cbp " << x.tex0.cbp << " cpsm " << +x.tex0.cpsm
              << " | XYOFFSET/scissor see history | ALPHA " << x.alpha << " TEST " << x.test << "\n";
        }
        f << "TEXA ta0 " << +s.texa.ta0 << " aem " << s.texa.aem << " ta1 " << +s.texa.ta1 << "\n";
        const ps2_stubs::CdDebugSnapshot cd = ps2_stubs::getCdDebugSnapshot();
        f << std::dec << "CD initialized " << cd.initialized << " lastError " << cd.lastError << " nextPseudoLbn "
          << cd.nextPseudoLbn << " root " << cd.cdRoot.string() << " files " << cd.files.size() << "\n";
        for (const ps2_stubs::CdDebugFileEntry &file : cd.files)
            f << "  " << file.key << " lbn " << file.baseLbn << " sectors " << file.sectors << " size " << file.sizeBytes
              << "\n";
        f << "\n";
        for (const GSDebugHistoryEntry &e : runtime.gs().getDebugHistory())
        {
            f << std::dec << e.seq << " f" << e.frameIndex << std::hex << " ";
            switch (e.kind)
            {
            case GSDebugEventKind::GifTag:
                f << "GIFTAG size " << e.gifSizeBytes << " nloop " << e.gifNloop << " flg " << +e.gifFlg << " nreg "
                  << +e.gifNreg;
                break;
            case GSDebugEventKind::Register:
                f << "REG " << +e.reg << " = " << e.regValue;
                break;
            case GSDebugEventKind::Draw:
                f << "DRAW prim " << +e.prim.type << (e.prim.tme ? " TME" : "") << (e.prim.abe ? " ABE" : "")
                  << (e.prim.fst ? " FST" : "") << " ctx" << e.prim.ctxt << " verts " << std::dec << e.vertexCount
                  << " x " << e.xMin << ".." << e.xMax << " y " << e.yMin << ".." << e.yMax << " a " << +e.aMin
                  << ".." << +e.aMax << std::hex << " | fb " << e.frame.fbp << "/" << +e.frame.psm << " tex "
                  << e.tex0.tbp0 << " tbw " << +e.tex0.tbw << " psm " << +e.tex0.psm << " " << +e.tex0.tw << "x"
                  << +e.tex0.th << " tcc " << +e.tex0.tcc << " tfx " << +e.tex0.tfx << " cbp " << e.tex0.cbp
                  << " cpsm " << +e.tex0.cpsm << " cld " << +e.tex0.cld << " alpha " << e.alpha;
                break;
            case GSDebugEventKind::Transfer:
                f << "XFER dbp " << e.bitbltbuf.dbp << " dbw " << +e.bitbltbuf.dbw << " dpsm " << +e.bitbltbuf.dpsm
                  << " at " << std::dec << e.trxpos.dsax << "," << e.trxpos.dsay << " " << e.trxreg.rrw << "x"
                  << e.trxreg.rrh << " dir " << e.trxdir << " pixels " << e.transferPixels;
                break;
            case GSDebugEventKind::Present:
                f << "PRESENT display fbp " << e.displayFbp << " source " << e.sourceFbp << " " << std::dec << e.width
                  << "x" << e.height;
                break;
            }
            f << "\n";
        }
        // EE RAM 0x300000-0x500000 (.rodata, .bss start, the game's buffers) for comparing with PCSX2's.
        std::ofstream ram("ram_0x300000_frame" + std::to_string(frame) + ".bin", std::ios::binary);
        ram.write(reinterpret_cast<const char *>(runtime.memory().getRDRAM() + 0x300000u), 0x200000);
        // The MFIFO ring (0x100000, 512 KB) as it is at this point of the frame.
        std::ofstream ring("ring_frame" + std::to_string(frame) + ".bin", std::ios::binary);
        ring.write(reinterpret_cast<const char *>(runtime.memory().getRDRAM() + 0x100000u), 0x80000);
        RUNTIME_LOG("[tekken4] GS dump written for frame " << frame << "\n");
    }

    bool isSoundClient(uint32_t client)
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        return g_soundClients.count(client) != 0;
    }

    // Each replacement mirrors the generated stub wrappers: return to $ra, then handle or pass through.
    // Every other RPC service the game talks to, logged once per (client, sid) and (sid, function).
    std::set<uint64_t> g_loggedOtherBinds;
    std::set<uint64_t> g_loggedOtherCalls;
    std::unordered_map<uint32_t, uint32_t> g_clientSid;

    void sifBindRpc(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        ctx->pc = getRegU32(ctx, 31);
        if (getRegU32(ctx, 5) != kSoundSid)
        {
            const uint32_t client = getRegU32(ctx, 4);
            const uint32_t sid = getRegU32(ctx, 5);
            ps2_stubs::sceSifBindRpc(rdram, ctx, runtime);
            uint32_t server = 0u;
            if (const uint8_t *cd = getMemPtr(rdram, client))
                std::memcpy(&server, cd + kClientServerOffset, sizeof(server));
            std::lock_guard<std::mutex> lock(g_mutex);
            g_clientSid[client] = sid;
            if (g_loggedOtherBinds.insert((static_cast<uint64_t>(client) << 32) | sid).second)
                RUNTIME_LOG("[tekken4] bind sid 0x" << std::hex << sid << " client 0x" << client << " -> server 0x"
                                                    << server << (server ? "" : " (not bound, game will retry)")
                                                    << std::dec << "\n");
            return;
        }

        const uint32_t client = getRegU32(ctx, 4);
        if (!g_realSound)
        {
            uint8_t *cd = getMemPtr(rdram, client);
            if (!cd)
            {
                setReturnS32(ctx, -1);
                return;
            }
            // Any non-zero server ends the retry loop. Nothing dereferences it: calls on this client stop here.
            std::memset(cd + kClientBodyOffset, 0, kClientBodySize);
            std::memcpy(cd + kClientServerOffset, &client, sizeof(client));

            std::lock_guard<std::mutex> lock(g_mutex);
            if (g_soundClients.insert(client).second)
            {
                RUNTIME_LOG("[tekken4] sound RPC 0x12345 bound to silent HLE server, client 0x" << std::hex << client
                                                                                                << std::dec << "\n");
            }
            setReturnS32(ctx, 0);
            return;
        }

        // Real bind records the client under SID 0x12345 even when the IRX has not called
        // sceSifRegisterRpc yet. This ELF spins at 0x2227a8 until client.server != 0, and the module
        // load that would register the SID is not reached while that spin runs. A zeroed placeholder
        // (not the client itself: SifCallRpc writes through server) lets boot continue. Calls still
        // dispatch on the SID, so they hit zsiopdrv once its entry has registered.
        ps2_stubs::sceSifBindRpc(rdram, ctx, runtime);
        uint32_t server = 0u;
        uint8_t *cd = getMemPtr(rdram, client);
        if (cd)
            std::memcpy(&server, cd + kClientServerOffset, sizeof(server));
        const bool registered = server != 0u;
        if (!registered && cd && runtime)
        {
            const uint32_t placeholder = runtime->guestCalloc(1u, 64u, 16u);
            if (placeholder != 0u)
            {
                std::memcpy(cd + kClientServerOffset, &placeholder, sizeof(placeholder));
                server = placeholder;
            }
        }
        std::lock_guard<std::mutex> lock(g_mutex);
        if (g_soundClients.insert(client).second)
            RUNTIME_LOG("[tekken4] sound RPC 0x12345 bound, client 0x" << std::hex << client << " server 0x" << server
                                                                        << (registered ? " (zsiopdrv)" : " (placeholder, zsiopdrv not registered yet)")
                                                                        << std::dec << "\n");
        if (!registered && server == 0u)
            setReturnS32(ctx, -1);
    }

    void sifCallRpc(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        ctx->pc = getRegU32(ctx, 31);
        const uint32_t client = getRegU32(ctx, 4);
        if (!isSoundClient(client))
        {
            const uint32_t fno = getRegU32(ctx, 5);
            {
                std::lock_guard<std::mutex> lock(g_mutex);
                const auto it = g_clientSid.find(client);
                const uint32_t sid = it != g_clientSid.end() ? it->second : 0u;
                if (g_loggedOtherCalls.insert((static_cast<uint64_t>(sid) << 32) | fno).second)
                    RUNTIME_LOG("[tekken4] call sid 0x" << std::hex << sid << " fno 0x" << fno << " send 0x"
                                                        << getRegU32(ctx, 7) << "/" << getRegU32(ctx, 8) << " recv 0x"
                                                        << getRegU32(ctx, 9) << "/" << getRegU32(ctx, 10) << std::dec
                                                        << " (first time)\n");
            }
            ps2_syscalls::sceSifCallRpc(rdram, ctx, runtime);
            return;
        }

        const uint32_t function = getRegU32(ctx, 5);
        const uint32_t reply = getRegU32(ctx, 9);
        const uint32_t replySize = getRegU32(ctx, 10);
        const uint32_t endFunction = getRegU32(ctx, 11);
        // Mode 0 of 0x200 writes EE RAM the loader checksums; that copy stays here. Other modes are sound
        // banks the local HLE used to drop, so zsiopdrv has to receive them or the mixer stays silent.
        bool forward = false;
        uint32_t discMode = 0u;
        if (g_realSound)
        {
            if (function == kDiscReadCall)
            {
                if (const uint8_t *send = getMemPtr(rdram, getRegU32(ctx, 7)))
                    std::memcpy(&discMode, send + 12, 4);
                forward = discMode != 0u;
            }
            else if (function != kMovieOpenCall && function != kMovieReadCall && function != kMovieCloseCall)
                forward = true;
        }
        if (forward)
        {
            {
                std::lock_guard<std::mutex> lock(g_mutex);
                if (g_loggedCalls.insert(function).second)
                    RUNTIME_LOG("[tekken4] sound RPC call 0x" << std::hex << function
                                                               << " forwarded to zsiopdrv, reply 0x" << reply
                                                               << " size 0x" << replySize << std::dec << "\n");
            }
            if (function == kDiscReadCall)
            {
                static int forwardedReads = 0;
                if (forwardedReads < 8)
                {
                    ++forwardedReads;
                    uint32_t sector = 0u, size = 0u;
                    if (const uint8_t *send = getMemPtr(rdram, getRegU32(ctx, 7)))
                    {
                        std::memcpy(&sector, send, 4);
                        std::memcpy(&size, send + 8, 4);
                    }
                    RUNTIME_LOG("[tekken4] disc read mode " << discMode << " forwarded, sector " << sector
                                                            << " size " << size << "\n");
                }
            }
            ps2_syscalls::sceSifCallRpc(rdram, ctx, runtime);
            if (function == kDiscReadCall)
            {
                uint32_t done = 0u;
                std::memcpy(&done, rdram + kDiscReadDoneFlag, 4);
                ++done;
                std::memcpy(rdram + kDiscReadDoneFlag, &done, 4);
            }
            if (function == kSoundFrameCall && g_movieSize != 0u)
            {
                pushMoviePcm(nullptr, 0u); // starts the held sound once the first picture is out
                movieSyncTick();
            }
            if (function == kSoundFrameCall && g_movieSize != 0u && replySize >= 16u)
            {
                if (uint8_t *dst = getMemPtr(rdram, reply))
                {
                    uint32_t status = 0u;
                    std::memcpy(&status, dst + kFrameReplyStatusWord * 4u, 4);
                    status |= kStatusMovieAudioReady | (g_movieEnded ? kStatusMovieEnded : 0u);
                    std::memcpy(dst + kFrameReplyStatusWord * 4u, &status, 4);
                }
            }
            std::lock_guard<std::mutex> lock(g_mutex);
#ifdef _WIN32
            if (function == kSoundFrameCall)
                captureGameThread();
#endif
            if (function == kSoundFrameCall && ++g_frames == g_nextFrameLog)
            {
                const auto now = std::chrono::steady_clock::now();
                if (g_frames == 1u)
                    g_firstFrame = now;
                const double seconds = std::chrono::duration<double>(now - g_firstFrame).count();
                if (g_frames == 1u)
                    RUNTIME_LOG("[tekken4] main loop frame 1\n");
                else
                    RUNTIME_LOG("[tekken4] main loop frame " << g_frames << " after " << seconds << " s ("
                                                             << (g_frames - 1u) / seconds << " fps)\n");
                g_nextFrameLog *= 10u;
            }
            if (function == kSoundFrameCall && g_gsDumpFrame != 0u && g_frames + 2u == g_gsDumpFrame)
            {
                runtime->gs().clearDebugHistory();
                runtime->gs().setDebugHistoryPaused(false);
                std::lock_guard<std::mutex> gifLock(g_gifLogMutex);
                g_gifLog.open("gif_packets_frame" + std::to_string(g_gsDumpFrame) + ".txt");
            }
            if (function == kSoundFrameCall && g_frames == g_gsDumpFrame)
            {
                runtime->gs().setDebugHistoryPaused(true);
                {
                    std::lock_guard<std::mutex> gifLock(g_gifLogMutex);
                    g_gifLog.close();
                }
                dumpGs(*runtime, g_frames);
            }
            return;
        }
        if (uint8_t *dst = replySize ? getMemPtr(rdram, reply) : nullptr)
        {
            std::memset(dst, 0, replySize < kMaxReplySize ? replySize : kMaxReplySize);
        }
        if (function == kDiscReadCall)
            discRead(rdram, getRegU32(ctx, 7));
        else if (function == kMovieOpenCall)
            movieOpen(rdram, getRegU32(ctx, 7));
        else if (function == kMovieReadCall)
            movieRead(rdram, getRegU32(ctx, 7));
        else if (function == kMovieCloseCall)
        {
            if (g_movieAudioUnits != 0u)
                RUNTIME_LOG("[tekken4] movie audio closed after " << g_movieAudioUnits << " units\n");
            movieSyncSummary();
            g_movieSize = 0u;
            g_movieAudioUnits = 0u;
            ps2ClearMoviePcm();
        }
        else if (function == kSoundFrameCall && g_movieSize != 0u && replySize >= 16u)
        {
            pushMoviePcm(nullptr, 0u);
            movieSyncTick();
            const uint32_t status = kStatusMovieAudioReady | (g_movieEnded ? kStatusMovieEnded : 0u);
            if (uint8_t *dst = getMemPtr(rdram, reply))
                std::memcpy(dst + kFrameReplyStatusWord * 4u, &status, 4);
        }

        std::lock_guard<std::mutex> lock(g_mutex);
        if (g_loggedCalls.insert(function).second)
        {
            RUNTIME_LOG("[tekken4] sound RPC call 0x" << std::hex << function << " (first time), reply 0x" << reply
                                                       << " size 0x" << replySize << std::dec << "\n");
        }
        // The per-frame sound update doubles as a frame counter: log at 1, 10, 100, ... frames.
#ifdef _WIN32
        if (function == kSoundFrameCall)
            captureGameThread();
#endif
        if (function == kSoundFrameCall && ++g_frames == g_nextFrameLog)
        {
            const auto now = std::chrono::steady_clock::now();
            if (g_frames == 1u)
                g_firstFrame = now;
            const double seconds = std::chrono::duration<double>(now - g_firstFrame).count();
            if (g_frames == 1u)
                RUNTIME_LOG("[tekken4] main loop frame 1\n");
            else
                RUNTIME_LOG("[tekken4] main loop frame " << g_frames << " after " << seconds << " s ("
                                                         << (g_frames - 1u) / seconds << " fps)\n");
            g_nextFrameLog *= 10u;
        }
        // The GS history is paused by default (the debug panel turns it on): record two frames, then dump.
        if (function == kSoundFrameCall && g_gsDumpFrame != 0u && g_frames + 2u == g_gsDumpFrame)
        {
            runtime->gs().clearDebugHistory();
            runtime->gs().setDebugHistoryPaused(false);
            std::lock_guard<std::mutex> gifLock(g_gifLogMutex);
            g_gifLog.open("gif_packets_frame" + std::to_string(g_gsDumpFrame) + ".txt");
        }
        if (function == kSoundFrameCall && g_frames == g_gsDumpFrame)
        {
            runtime->gs().setDebugHistoryPaused(true);
            {
                std::lock_guard<std::mutex> gifLock(g_gifLogMutex);
                g_gifLog.close();
            }
            dumpGs(*runtime, g_frames);
        }
        if (endFunction != 0u)
        {
            RUNTIME_LOG("[tekken4] sound RPC call 0x" << std::hex << function << " wants end function 0x"
                                                       << endFunction << ", not called" << std::dec << "\n");
        }
        setReturnS32(ctx, 0);
    }

    void sifCheckStatRpc(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        ctx->pc = getRegU32(ctx, 31);
        // The real driver can still be inside SifCallRpc. The silent HLE finishes every call before it returns.
        if (g_realSound || !isSoundClient(getRegU32(ctx, 4)))
        {
            ps2_stubs::sceSifCheckStatRpc(rdram, ctx, runtime);
            return;
        }
        setReturnS32(ctx, 0); // never busy: every call completes inside sifCallRpc
    }

    // The recompiled sceSifSendCmd ends in ps2_syscalls::sceSifSendCmd, which copies the extra payload to IOP RAM
    // and hands the packet to the IOP module's command handler. It does not store SIF_CMD_SET_SREG. zsiopdrv's init
    // (handler 0x4c6b4) spins on sceSifGetSreg(31) until that store is non-zero. The game writes index 31 = 1 at
    // 0x228ca8, before the bind.
    // zsiopdrv also pulls sound data from EE RAM: it asks with SIF command 2 (EE handler 0x228a08), the main loop
    // (0x228d90) answers with FUN_00228cc8 = sceSifSendCmd(cid 0, 0x1ccacc0, 0x24, EE source, IOP dest, size).
    // TEKKEN4_BGM=0 restores the state before the music fix (docs/MUSIC_FIX.md) for A/B runs: payload and packet
    // are dropped here, and the IOP delivers no SPU2 interrupts (the BGM stream's refill clock).
    void sifSendCmd(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        ctx->pc = getRegU32(ctx, 31);
        const uint32_t cid = getRegU32(ctx, 4);
        const uint32_t packet = getRegU32(ctx, 5);
        uint32_t index = 0u;
        uint32_t value = 0u;
        bool have = false;
        if (cid == kSifCmdSetSreg && packet != 0u)
        {
            if (const uint8_t *bytes = getMemPtr(rdram, packet))
            {
                std::memcpy(&index, bytes + 16, 4);
                std::memcpy(&value, bytes + 20, 4);
                have = index < 32u;
            }
        }
        static const bool bgmOff = []
        {
            const char *env = std::getenv("TEKKEN4_BGM");
            return env && std::strcmp(env, "0") == 0;
        }();
        if (cid != kSifCmdSetSreg && bgmOff)
        {
            setReturnS32(ctx, 1);
            return;
        }
        ps2_syscalls::sceSifSendCmd(rdram, ctx, runtime);
        if (!have)
            return;
        ps2x::iop::setSifSoftwareRegister(index, value);
        static int logged = 0;
        if (logged < 8)
        {
            ++logged;
            RUNTIME_LOG("[tekken4] SIF_CMD_SET_SREG index=" << index << " value=" << value << "\n");
        }
    }

    // Debug aid (TEKKEN4_IRQ_LOG=<count>): log the MFIFO ring state around the game's DMA-end handlers and its
    // frame start/end, to see which end interrupts arrive and in what order.
    std::atomic<int> g_irqLogLeft{0};

    std::string ringState(const uint8_t *rdram)
    {
        const uint8_t *s = rdram + 0x1cd7b40u;
        int32_t pending = 0;
        std::memcpy(&pending, s + 4, 4);
        std::ostringstream o;
        o << "[0]=" << +s[0] << " [1]=" << +s[1] << " [2]=" << +s[2] << " [3]=" << +s[3] << " [4]=" << pending;
        return o.str();
    }

    template <void (*Original)(uint8_t *, R5900Context *, PS2Runtime *)>
    void logged(const char *what, uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const bool log = g_irqLogLeft.fetch_sub(1) > 0;
        const std::string before = log ? ringState(rdram) : std::string();
        const uint32_t cause = getRegU32(ctx, 4);
        Original(rdram, ctx, runtime);
        if (log)
            RUNTIME_LOG("[tekken4] " << what << " (a0=" << cause << ") frame " << g_frames << ": " << before << "  ->  "
                                     << ringState(rdram) << "\n");
        // First time path 1 ends before the frame-end +1 (VIF1 end count 2 while nothing is pending), save the
        // ring so it can be compared with PCSX2's (logs: ring_early_end.bin, 0x100000-0x110000).
        static bool dumped = false;
        const uint8_t *s = rdram + 0x1cd7b40u;
        int32_t pending = 0;
        std::memcpy(&pending, s + 4, 4);
        if (!dumped && cause == 1u && s[2] == 2u && pending == 0 && s[3] == 1u)
        {
            dumped = true;
            std::ofstream("ring_early_end.bin", std::ios::binary).write(reinterpret_cast<const char *>(rdram + 0x100000u), 0x10000);
            RUNTIME_LOG("[tekken4] path 1 ended before frame end: ring saved to ring_early_end.bin\n");
        }
    }

    // The game's "close DMA tag" of its VIF packet library (0x291cc0, not recognised as an SDK function, so it runs
    // as game code): pads pk->cur to a qword, then ADDS (cur - tag)/16 - 1 to the open tag's first word. The
    // runtime's stubs for the recognised library calls (sceGifPkAddGsAD etc.) already keep that qwc field up to
    // date as they write (refreshPacketBuilderPendingCount), so tags built with both came out with qwc doubled
    // (image-upload CNT 10 instead of 5: VIF1 then misread the ring and the frame's DMA interrupts looped).
    // Same function, but the qwc is SET, which is right whether or not stubs touched the tag.
    // pk layout: [0] cur, [1] base, [2] open DMA tag, [3] open GIF tag.
    void closeDmaTag(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        (void)runtime;
        ctx->pc = getRegU32(ctx, 31);
        const uint32_t pk = getRegU32(ctx, 4);
        uint8_t *p = getMemPtr(rdram, pk);
        if (!p)
            return;
        uint32_t cur = 0, tag = 0;
        std::memcpy(&cur, p, 4);
        std::memcpy(&tag, p + 8, 4);
        const uint32_t zero = 0;
        for (; (cur & 0xCu) != 0u; cur += 4u)
            if (uint8_t *w = getMemPtr(rdram, cur))
                std::memcpy(w, &zero, 4);
        if (uint8_t *t = tag ? getMemPtr(rdram, tag) : nullptr)
        {
            uint32_t word0 = 0;
            std::memcpy(&word0, t, 4);
            const uint32_t qwc = ((cur - tag) >> 4) - 1u;
            word0 = (word0 & 0xFFFF0000u) | (qwc & 0xFFFFu);
            std::memcpy(t, &word0, 4);
        }
        std::memcpy(p + 8, &zero, 4);
        std::memcpy(p, &cur, 4);
        setReturnU32(ctx, cur);
    }

    // The game's libc rand (0x2a2538). The recompiler maps it by name to the runtime's stub, which returns the host's
    // std::rand(); the game's srand (0x2a2528) is not stubbed and seeds the guest state, which that stub never reads.
    // The host generator was therefore never seeded: every run drew the same numbers and the CPU picked the same
    // opponents (arcade always Law, story always Steve) where PCSX2 varies. This is the game's own routine:
    // next = next * 1103515245 + 12345 on the 32-bit word at reent + 88 (reent = *0x304b94), result next & 0x7fffffff.
    constexpr uint32_t kRand = 0x002a2538u;
    constexpr uint32_t kReentPtr = 0x00304b94u;
    void guestRand(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        (void)runtime;
        ctx->pc = getRegU32(ctx, 31);
        uint32_t reent = 0, next = 0;
        std::memcpy(&reent, rdram + kReentPtr, 4);
        uint8_t *state = getMemPtr(rdram, reent + 88u);
        if (!state)
        {
            setReturnS32(ctx, 0);
            return;
        }
        std::memcpy(&next, state, 4);
        next = next * 1103515245u + 12345u;
        std::memcpy(state, &next, 4);
        setReturnS32(ctx, static_cast<int32_t>(next & 0x7FFFFFFFu));
    }

    // Debug: the same close, logged from frame 4 on (TEKKEN4_IRQ_LOG).
    std::atomic<int> g_closeLogLeft{60};
    void closeTagLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t pk = getRegU32(ctx, 4);
        uint32_t pkWords[4] = {};
        if (const uint8_t *p = getMemPtr(rdram, pk))
            std::memcpy(pkWords, p, sizeof(pkWords));
        uint32_t tagBefore = 0;
        const uint8_t *tagPtr = pkWords[2] ? getMemPtr(rdram, pkWords[2]) : nullptr;
        if (tagPtr)
            std::memcpy(&tagBefore, tagPtr, 4);
        closeDmaTag(rdram, ctx, runtime);
        if (g_frames >= 4 && g_closeLogLeft.fetch_sub(1) > 0)
        {
            uint32_t tagAfter = 0, pkAfter[4] = {};
            if (tagPtr)
                std::memcpy(&tagAfter, tagPtr, 4);
            if (const uint8_t *p = getMemPtr(rdram, pk))
                std::memcpy(pkAfter, p, sizeof(pkAfter));
            RUNTIME_LOG("[tekken4] close tag pk 0x" << std::hex << pk << " cur " << pkWords[0] << " tag " << pkWords[2]
                                                    << " word0 " << tagBefore << " -> " << tagAfter << " | after: cur "
                                                    << pkAfter[0] << " tag " << pkAfter[2] << " ra " << getRegU32(ctx, 31)
                                                    << std::dec << "\n");
        }
    }

    // Around the open-CNT (0x291d30) and sceGifPkCloseGifTag (0x291ee8): pk words and the scratchpad qwords.
    std::atomic<int> g_pkLogLeft{40};
    void logPk(const char *what, uint8_t *rdram, uint32_t pk, const char *when)
    {
        uint32_t w[4] = {};
        if (const uint8_t *p = getMemPtr(rdram, pk))
            std::memcpy(w, p, sizeof(w));
        std::ostringstream o;
        o << std::hex << what << " " << when << ": pk cur " << w[0] << " dmatag " << w[2] << " giftag " << w[3];
        for (uint32_t a : {w[2], w[3]})
            if (const uint8_t *q = a ? getMemPtr(rdram, a) : nullptr)
            {
                uint64_t lo = 0;
                std::memcpy(&lo, q, 8);
                o << " [" << a << "]=" << lo;
            }
        RUNTIME_LOG("[tekken4] " << o.str() << "\n");
    }
    void openCntLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t pk = getRegU32(ctx, 4);
        const bool log = g_frames >= 4 && g_pkLogLeft.fetch_sub(1) > 0;
        if (log)
            RUNTIME_LOG("[tekken4] open CNT args a1 " << std::hex << getRegU32(ctx, 5) << " a2 " << getRegU32(ctx, 6)
                                                      << " a3 " << getRegU32(ctx, 7) << " ra " << getRegU32(ctx, 31)
                                                      << std::dec << "\n");
        FUN_00291d30_0x291d30(rdram, ctx, runtime);
        if (log)
            logPk("open CNT", rdram, pk, "after");
    }
    void closeGifLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t pk = getRegU32(ctx, 4);
        const bool log = g_frames >= 4 && g_pkLogLeft.fetch_sub(1) > 0;
        if (log)
            logPk("close GIF", rdram, pk, "before");
        sceGifPkCloseGifTag_0x291ee8(rdram, ctx, runtime);
        if (log)
            logPk("close GIF", rdram, pk, "after ");
    }

    void vif1EndLogged(uint8_t *r, R5900Context *c, PS2Runtime *p) { logged<FUN_00232ab0_0x232ab0>("VIF1 end handler", r, c, p); }
    void gifEndLogged(uint8_t *r, R5900Context *c, PS2Runtime *p) { logged<FUN_00232bc8_0x232bc8>("GIF end handler ", r, c, p); }
    void frameStartLogged(uint8_t *r, R5900Context *c, PS2Runtime *p) { logged<FUN_002323a0_0x2323a0>("frame start     ", r, c, p); }
    void frameEndLogged(uint8_t *r, R5900Context *c, PS2Runtime *p) { logged<FUN_002330b8_0x2330b8>("frame end (+1)  ", r, c, p); }

    // Movie pictures. libmpeg's sceMpegGetPicture calls the player's "no data" callback (sceMpegCbNodata,
    // 0x227888) whenever the IPU runs out of bitstream. The callback pumps the disc stream (FUN_002287a8), takes the
    // previous chunk out of the movie ring and points a toIPU DMA (channel 4, chain mode, one REFE tag at
    // 0x1ccab30) at the next 0x9c00 bytes. The runtime's decoder takes bitstream from sceMpegAddBs or PSS demuxing
    // and never calls that callback, so GetPicture waited forever. Here GetPicture first runs the callback the way
    // libmpeg would, hands each transfer it starts to sceMpegAddBs and stops the channel as if the IPU had taken
    // it, until a picture is decoded.
    constexpr uint32_t kSceMpegGetPicture = 0x0028af00u;
    constexpr uint32_t kMovieNodataCallback = 0x00227888u;
    constexpr uint32_t kMovieIpuTag = 0x01ccab30u;
    constexpr uint32_t kIpuToChcr = 0x1000b400u;
    constexpr int kMaxNodataCalls = 64;

    // Runs a guest function to completion from host code: returns to pc 0 like the scheduler's invocations.
    bool callGuest(uint8_t *rdram, const R5900Context &caller, PS2Runtime *runtime, uint32_t function, uint32_t a0)
    {
        R5900Context call = caller;
        SET_GPR_U32(&call, 4, a0);
        SET_GPR_U32(&call, 31, 0u);
        call.pc = function;
        for (int steps = 0; call.pc != 0u && steps < 100000; ++steps)
        {
            PS2Runtime::RecompiledFunction fn = runtime->lookupFunction(call.pc);
            if (!fn)
                return false;
            fn(rdram, &call, runtime);
        }
        return call.pc == 0u;
    }

    bool mpegHasPicture(uint8_t *rdram, const R5900Context &caller, PS2Runtime *runtime, uint32_t mpeg)
    {
        R5900Context query = caller;
        SET_GPR_U32(&query, 4, mpeg);
        ps2_stubs::sceMpegIsRefBuffEmpty(rdram, &query, runtime);
        return getRegU32(&query, 2) == 0u;
    }

    uint64_t g_movieBytesFed = 0u;

    // Animated IPU images (the character select's background, the attract loop). FUN_00226e88 sets up one job per
    // image of an image file at 0x1ccaa80 (0x54 bytes each: +0x2c/+0x30 size in macroblocks, +0x38 RGB32 output,
    // +0x3c frame table, +0x40 position, +0x44 frames << 8, +0x48 speed, +0x4c/+0x50 current frame data and size).
    // Every frame FUN_002272a0(step) advances each animation and has the IPU decode the current frames (FDEC the
    // flags byte, IDEC through toIPU/fromIPU DMA; the channel-3 handler 0x2273b0 starts the next image), and
    // FUN_00227568 spins until 0x1ccaa0c reaches -1. The runtime has no IPU: decode the frames here instead.
    constexpr uint32_t kIpuImagesDecode = 0x002272a0u;
    constexpr uint32_t kIpuJobs = 0x01ccaa80u;
    constexpr uint32_t kIpuJobSize = 0x54u;
    constexpr uint32_t kIpuActive = 0x01ccaa04u;
    constexpr uint32_t kIpuCount = 0x01ccaa08u;
    constexpr uint32_t kIpuPending = 0x01ccaa0cu;
    constexpr uint32_t kIpuStage = 0x01ccaa18u;
    constexpr uint32_t kIpuFormat = 0x01ccaa2cu; // 0 RGB32, 1 RGB16, 2 RGB16 dithered (IDEC OFM/DTE)

    int32_t guest32(const uint8_t *rdram, uint32_t addr)
    {
        int32_t value = 0;
        std::memcpy(&value, rdram + (addr & 0x01FFFFFCu), 4);
        return value;
    }

    void setGuest32(uint8_t *rdram, uint32_t addr, int32_t value)
    {
        std::memcpy(rdram + (addr & 0x01FFFFFCu), &value, 4);
    }

    // value / 256 rounding toward zero, as the game's code does it.
    int32_t div256(int32_t value)
    {
        return (value < 0 ? value + 0xFF : value) >> 8;
    }

    void ipuImagesDecode(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        (void)runtime;
        ctx->pc = getRegU32(ctx, 31);
        if (guest32(rdram, kIpuActive) == 0)
            return;
        const int32_t step = static_cast<int32_t>(getRegU32(ctx, 4));
        const int32_t count = guest32(rdram, kIpuCount);
        const int32_t format = guest32(rdram, kIpuFormat);
        static int failuresLogged = 0;
        for (int32_t i = 0; i < count; ++i)
        {
            const uint32_t job = kIpuJobs + static_cast<uint32_t>(i) * kIpuJobSize;
            int32_t position = guest32(rdram, job + 0x40u) + div256(guest32(rdram, job + 0x48u) * step);
            if (guest32(rdram, job + 0x44u) <= position)
                position = 0;
            setGuest32(rdram, job + 0x40u, position);
            const uint32_t table = static_cast<uint32_t>(guest32(rdram, job + 0x3cu));
            const uint32_t entry = static_cast<uint32_t>(div256(position) * 8) + table;
            const uint32_t data = table + static_cast<uint32_t>(guest32(rdram, entry + 4u));
            const uint32_t size = static_cast<uint32_t>(guest32(rdram, entry + 8u));
            setGuest32(rdram, job + 0x4cu, static_cast<int32_t>(data));
            setGuest32(rdram, job + 0x50u, static_cast<int32_t>(size));

            const uint32_t mbWidth = static_cast<uint32_t>(guest32(rdram, job + 0x2cu));
            const uint32_t mbHeight = static_cast<uint32_t>(guest32(rdram, job + 0x30u));
            const uint32_t out = static_cast<uint32_t>(guest32(rdram, job + 0x38u)) & 0x01FFFFFFu;
            const uint64_t outBytes = static_cast<uint64_t>(mbWidth) * mbHeight * 1024u;
            const uint32_t in = data & 0x01FFFFFFu;
            bool decoded = false;
            if (format == 0 && in + static_cast<uint64_t>(size) <= PS2_RAM_SIZE && out + outBytes <= PS2_RAM_SIZE)
                decoded = ps2_stubs::decodeIpuIntraPicture(rdram + in, size, mbWidth, mbHeight, rdram + out);
            if (!decoded && failuresLogged < 8)
            {
                ++failuresLogged;
                RUNTIME_LOG("[tekken4] IPU image " << i << " frame " << div256(position) << " (" << mbWidth << "x" << mbHeight
                                                   << " macroblocks, format " << format << ") not decoded\n");
            }
        }
        setGuest32(rdram, kIpuStage, 0);
        setGuest32(rdram, kIpuPending, -1); // all decoded: FUN_00227568 returns at once
    }

    void mpegGetPicture(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        ctx->pc = getRegU32(ctx, 31);
        const uint32_t mpeg = getRegU32(ctx, 4);
        uint8_t *tag = getMemPtr(rdram, kMovieIpuTag);
        for (int i = 0; tag && i < kMaxNodataCalls && !mpegHasPicture(rdram, *ctx, runtime, mpeg); ++i)
        {
            std::memset(tag, 0, 16);
            if (!callGuest(rdram, *ctx, runtime, kMovieNodataCallback, mpeg))
                break;
            uint64_t refe = 0;
            std::memcpy(&refe, tag, 8);
            if (refe == 0u) // the callback had no data to send yet; it pumped the stream, so ask again
                continue;
            const uint32_t qwc = static_cast<uint32_t>(refe & 0xFFFFu);
            const uint32_t addr = static_cast<uint32_t>((refe >> 32) & 0x0FFFFFF0u);
            R5900Context feed = *ctx;
            SET_GPR_U32(&feed, 4, mpeg);
            SET_GPR_U32(&feed, 5, addr);
            SET_GPR_U32(&feed, 6, qwc * 16u);
            ps2_stubs::sceMpegAddBs(rdram, &feed, runtime);
            runtime->memory().writeIORegister(kIpuToChcr, runtime->memory().readIORegister(kIpuToChcr) & ~0x100u);
            if (g_movieBytesFed == 0u)
                RUNTIME_LOG("[tekken4] movie: first bitstream to the decoder, 0x" << std::hex << qwc * 16u
                                                                                << " bytes from 0x" << addr << std::dec << "\n");
            g_movieBytesFed += qwc * 16u;
        }
        ps2_stubs::sceMpegGetPicture(rdram, ctx, runtime);
    }

    // Debug aid (TEKKEN4_MOVIE_LOG=<count>): the movie player's state and the values its exits test, logged on
    // each pass while it plays (state 3..6), up to <count> lines.
    std::atomic<int> g_movieLogLeft{0};
    void moviePlayerLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        auto w = [rdram](uint32_t addr)
        {
            uint32_t v = 0u;
            std::memcpy(&v, rdram + addr, 4);
            return static_cast<int32_t>(v);
        };
        const int32_t before = w(0x01ccab40u);
        FUN_00227bd8_0x227bd8(rdram, ctx, runtime);
        if (before >= 3 && before <= 6 && g_movieLogLeft.fetch_sub(1) > 0)
            RUNTIME_LOG("[tekken4] movie player state " << before << " -> " << w(0x01ccab40u) << ": frame " << w(0x01ccab58u)
                                                       << " shown " << w(0x01ccabe4u) << " bufs " << w(0x01ccac24u)
                                                       << " a120 " << w(0x00357a20u) << " end35c " << w(0x01ccabdcu)
                                                       << " exit358 " << w(0x01ccabd8u) << " pad " << std::hex
                                                       << w(0x00356054u) << std::dec << " skipflag " << w(0x00357868u)
                                                       << " mode2c4 " << w(0x01ccab44u) << " wait38c " << w(0x01ccac0cu)
                                                       << " buffered " << w(0x01ccac58u) << "\n");
    }

    // Progressive scan (480p). The video-mode setup FUN_0022a598(keep, index) takes entry <index> of the 6-byte table at
    // 0x31e970 (interlace flag, omode, double-buffer psm, display FBP): 1/2 = NTSC interlaced (CT24 640x224 field
    // buffer at FBP 0xd2), 3/4 = PAL, 5 = DTV480P (omode 0x50, CT24 640x448 display buffer at FBP 0x8c), 6/7 = 480p
    // with a CT16 display buffer. It calls sceGsResetGraph(0, inter, omode, FFMD 1), sets the 480p flag (0x1ccafb4) and
    // picks the vsync copy packets per index (table 0x2ce550): index 1 copies the even or odd lines of the 640x448
    // back buffer into the 224-line field buffer depending on CSR.FIELD, index 5 copies the whole 448-line frame with
    // the same packet every vsync. The US game only ever asks for 1 (the PAL release has a "Progressive Scan" menu entry
    // for 5..7). TEKKEN4_PROGRESSIVE=1 (default) maps the NTSC interlaced entries to 5: full frames, no fields, no line
    // doubling; =0 keeps interlaced FRAME mode. Netplay always uses the default so both peers run the same mode (the mode
    // index, its flag and the copy packets live in RDRAM, which the desync check hashes).
    constexpr uint32_t kVideoModeSetup = 0x0022a598u;
    constexpr uint32_t kVideoModeProgressive = 5u;
    bool g_progressive = true;
    void videoModeSetup(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t index = getRegU32(ctx, 5);
        if (g_progressive && (index == 1u || index == 2u))
        {
            static bool logged = false;
            if (!logged)
                RUNTIME_LOG("[tekken4] video mode " << index << " (NTSC interlaced) -> " << kVideoModeProgressive
                                                    << " (480p progressive, TEKKEN4_PROGRESSIVE)\n");
            logged = true;
            SET_GPR_U32(ctx, 5, kVideoModeProgressive);
        }
        FUN_0022a598_0x22a598(rdram, ctx, runtime);
    }
    // sceGsResetGraph is the runtime's stub, which sets the display registers but not libgraph's sceGsGParam
    // (0x3018c0: interlace, omode, ffmode, version; read by the game through sceGsGetGParam 0x289f20, which is game
    // code). The ELF's data holds NTSC interlaced (1, 2, 1), so in 480p FUN_0022a370 still took the interlaced
    // double-buffer setup (SMODE2 3, DH 895). Mode 0 (reset) stores them here like the real function.
    constexpr uint32_t kSceGsResetGraph = 0x00289d90u;
    constexpr uint32_t kSceGsGParam = 0x003018c0u;
    void gsResetGraph(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t mode = getRegU32(ctx, 4) & 0xFFFFu, interlace = getRegU32(ctx, 5), omode = getRegU32(ctx, 6),
                       ffmode = getRegU32(ctx, 7);
        ps2_stubs::sceGsResetGraph(rdram, ctx, runtime);
        if (mode == 0u)
        {
            const uint16_t values[3] = {static_cast<uint16_t>(interlace & 1u), static_cast<uint16_t>(omode & 0xFFu),
                                        static_cast<uint16_t>(ffmode & 1u)};
            std::memcpy(rdram + kSceGsGParam, values, sizeof values);
        }
    }

    void apply(PS2Runtime &runtime)
    {
        {
            const char *progressive = std::getenv("TEKKEN4_PROGRESSIVE");
            const char *net = std::getenv("TEKKEN4_NET");
            if (progressive && *progressive && !(net && *net))
                g_progressive = std::strcmp(progressive, "0") != 0;
            runtime.registerFunction(kVideoModeSetup, videoModeSetup);
            runtime.registerFunction(kSceGsResetGraph, gsResetGraph);
            RUNTIME_LOG("[tekken4] display: " << (g_progressive ? "progressive 480p" : "interlaced (TEKKEN4_PROGRESSIVE=0)")
                                              << "\n");
        }
        if (const char *sound = std::getenv("TEKKEN4_SOUND"); sound && std::strcmp(sound, "1") == 0)
        {
            const std::filesystem::path iso = findIsoPath();
            if (!iso.empty())
            {
                PS2Runtime::IoPaths paths = PS2Runtime::getIoPaths();
                paths.cdImage = iso;
                PS2Runtime::setIoPaths(paths);
                g_realSound = true;
                RUNTIME_LOG("[tekken4] TEKKEN4_SOUND=1: SID 0x12345 goes to zsiopdrv, cdImage " << iso.string()
                                                                                                << "\n");
            }
            else
                RUNTIME_LOG("[tekken4] TEKKEN4_SOUND=1 but no ISO; silent HLE stays\n");
        }
        if (const char *wav = std::getenv("TEKKEN4_SOUND_WAV"); wav && wav[0] != '\0')
        {
            std::filesystem::path wavPath(wav);
            if (wavPath.is_relative())
                wavPath = PS2Runtime::getIoPaths().elfDirectory.parent_path().parent_path() / wavPath;
            const std::string absolute = wavPath.lexically_normal().string();
#ifdef _WIN32
            _putenv_s("TEKKEN4_SOUND_WAV", absolute.c_str());
#else
            setenv("TEKKEN4_SOUND_WAV", absolute.c_str(), 1);
#endif
        }
        runtime.registerFunction(0x00291cc0u, closeDmaTag);
        // The VIF1 packet builder's close (same code, other copy): FUN_00233b60's texture-flush CNT came out qwc 4
        // instead of 2, VIF1 then read the next REF tags as data and the fight stalled ~4 s in (found by Grok, task
        // cnt-qwc).
        runtime.registerFunction(0x00291fd8u, closeDmaTag);
        runtime.registerFunction(kSceMpegGetPicture, mpegGetPicture);
        runtime.registerFunction(kIpuImagesDecode, ipuImagesDecode);
        runtime.registerFunction(kRand, guestRand);
        if (const char *presentLog = std::getenv("TEKKEN4_PRESENT_LOG"))
        {
            // Debug aid for a shaking picture: for <seconds>, samples the presented frame every 5 ms and logs each
            // change of its brightness-weighted vertical centre (in 1/100 line). A still picture that moves by
            // about a line every frame shakes; edges alone flicker by a line between fields even on a TV.
            const int seconds = std::atoi(presentLog);
            PS2Runtime *rt = &runtime;
            std::thread([rt, seconds]() {
                std::vector<uint8_t> frame;
                uint32_t w = 0u, h = 0u;
                int last = -1, changes = 0, lo = 0, hi = 0;
                const auto start = std::chrono::steady_clock::now();
                while (std::chrono::steady_clock::now() - start < std::chrono::seconds(seconds))
                {
                    std::this_thread::sleep_for(std::chrono::milliseconds(5));
                    if (!rt->gs().copyLatchedHostPresentationFrame(frame, w, h) || w <= 320u)
                        continue;
                    double sum = 0.0, weighted = 0.0;
                    for (uint32_t y = 0; y < h; ++y)
                    {
                        const uint8_t *row = frame.data() + static_cast<size_t>(y) * w * 4u;
                        uint32_t lum = 0u;
                        for (uint32_t x = 0; x < w; x += 4u)
                            lum += row[x * 4u] + row[x * 4u + 1u] + row[x * 4u + 2u];
                        sum += lum;
                        weighted += static_cast<double>(lum) * y;
                    }
                    const int centre = sum > 0.0 ? static_cast<int>(weighted / sum * 100.0) : -1;
                    const int second = static_cast<int>(
                        std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count());
                    if (second != last)
                    {
                        if (last >= 0 && changes > 0)
                            RUNTIME_LOG("[tekken4] present second " << last << ": centre " << lo << ".." << hi
                                                                    << " (spread " << hi - lo << ")\n");
                        last = second;
                        lo = hi = centre;
                        changes = 1;
                    }
                    lo = std::min(lo, centre);
                    hi = std::max(hi, centre);
                }
            }).detach();
        }
        if (const char *hz = std::getenv("TEKKEN4_MOVIE_AUDIO_HZ"); hz && std::atof(hz) >= 8000.0)
            g_movieSourceHz = std::atof(hz);
        g_movieSyncLog = std::getenv("TEKKEN4_MOVIE_SYNC") != nullptr;
        if (const char *movieLog = std::getenv("TEKKEN4_MOVIE_LOG"))
        {
            g_movieLogLeft = std::atoi(movieLog);
            runtime.registerFunction(0x00227bd8u, moviePlayerLogged);
        }
        if (const char *irqLog = std::getenv("TEKKEN4_IRQ_LOG"))
        {
            g_irqLogLeft = std::atoi(irqLog);
            runtime.registerFunction(0x00232ab0u, vif1EndLogged);
            runtime.registerFunction(0x00232bc8u, gifEndLogged);
            runtime.registerFunction(0x002323a0u, frameStartLogged);
            runtime.registerFunction(0x002330b8u, frameEndLogged);
            runtime.registerFunction(0x00291cc0u, closeTagLogged);
            runtime.registerFunction(0x00291d30u, openCntLogged);
            runtime.registerFunction(0x00291ee8u, closeGifLogged);
        }
        if (const char *watch = std::getenv("TEKKEN4_WATCH_MS"))
        {
            // Debug aid for stalls: after the delay, log the MFIFO ring state (struct from FUN_002322a0:
            // [0] pending paths, [1] active, [2] VIF1 ends, [3] GIF ends, [4] pending count, [8..] saved MADRs).
            const unsigned long delayMs = std::strtoul(watch, nullptr, 10);
            uint8_t *rdram = runtime.memory().getRDRAM();
            std::thread([delayMs, rdram]() {
                for (int i = 0; i < 3; ++i)
                {
                    std::this_thread::sleep_for(std::chrono::milliseconds(delayMs / 3 + 1));
                    std::ostringstream s;
                    s << std::hex;
                    for (uint32_t off = 0; off < 0x18; off += 4)
                    {
                        uint32_t w = 0;
                        std::memcpy(&w, rdram + 0x1cd7b40u + off, 4);
                        s << " " << std::setw(8) << std::setfill('0') << w;
                    }
                    uint32_t done = 0;
                    std::memcpy(&done, rdram + kDiscReadDoneFlag, 4);
                    RUNTIME_LOG("[tekken4] watch: ring state" << s.str() << " | disc done flag " << done << "\n");
                }
            }).detach();
        }
        if (const char *dump = std::getenv("TEKKEN4_GS_DUMP"))
        {
            g_gsDumpFrame = std::strtoull(dump, nullptr, 10);
            // Same as the runtime's own packet function, plus the raw log while recording.
            PS2Runtime *rt = &runtime;
            runtime.gifArbiter().setProcessPacketFn([rt](const uint8_t *data, uint32_t size)
                                                    { processGifPacketLogged(*rt, data, size); });
        }
#ifdef _WIN32
        if (const char *profile = std::getenv("TEKKEN4_PROFILE"))
            startProfiler(profile);
#endif
        if (const char *perf = std::getenv("TEKKEN4_PERF_LOG"))
        {
            // Debug aid for the frame rate: for <seconds>, logs each second the game's frames (sound call 0x100)
            // and the host time spent drawing (GIF packets through the GS), which runs on the game's thread.
            static std::atomic<uint64_t> gsNanoseconds{0};
            PS2Runtime *rt = &runtime;
            runtime.gifArbiter().setProcessPacketFn([rt](const uint8_t *data, uint32_t size)
                                                    {
                                                        const auto t0 = std::chrono::steady_clock::now();
                                                        rt->gs().processGIFPacket(data, size);
                                                        gsNanoseconds += static_cast<uint64_t>(
                                                            std::chrono::duration_cast<std::chrono::nanoseconds>(
                                                                std::chrono::steady_clock::now() - t0).count());
                                                    });
            const int seconds = std::atoi(perf);
            std::thread([seconds]() {
                uint64_t lastFrames = 0u, lastGs = 0u;
                for (int s = 0; s < seconds; ++s)
                {
                    std::this_thread::sleep_for(std::chrono::seconds(1));
                    const uint64_t frames = g_frames, gs = gsNanoseconds.load();
                    RUNTIME_LOG("[tekken4] perf second " << s << ": " << frames - lastFrames << " frames, GS "
                                                         << (gs - lastGs) / 1000000u << " ms\n");
                    lastFrames = frames;
                    lastGs = gs;
                }
            }).detach();
        }
        runtime.registerFunction(kSceSifBindRpc, sifBindRpc);
        runtime.registerFunction(kSceSifCallRpc, sifCallRpc);
        runtime.registerFunction(kSceSifCheckStatRpc, sifCheckStatRpc);
        if (g_realSound)
            runtime.registerFunction(kSceSifSendCmd, sifSendCmd);
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 (SLUS-20328 v1.00)", "SLUS_203.28", 0x00180088u, 0xB975F704u, tekken4::apply)
