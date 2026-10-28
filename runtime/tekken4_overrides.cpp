// Tekken 4 (SCES-50878, PAL v2.00) overrides for PS2Recomp's ps2xRuntime.
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
    // Namco's sound driver runs on the IOP and serves SIF RPC id 0x12345. Its EE library (0x2230d0-0x224140)
    // binds one client (0x1cccbc0) and only makes synchronous calls: 4 words in at 0x1ccc700 (the per-frame
    // call 0x100 sends a 0x80-byte command queue at 0x1ccc7c0 instead), 8 words back at 0x1ccc780.
    // FUN_002230d0 retries the bind every vsync until client.server != 0, so without a server boot stops there.
    // TEKKEN4_SOUND=1 plus an ISO forwards this SID to zsiopdrv, except mode-0 disc reads and the movie
    // calls (0x3000/0x3100/0x3200), which stay on the local HLE. Without that env every call is answered
    // at once with a zeroed reply: no sound.
    constexpr uint32_t kSoundSid = 0x12345u;
    constexpr uint32_t kSceSifBindRpc = 0x00282808u;
    constexpr uint32_t kSceSifCallRpc = 0x002829d8u;
    constexpr uint32_t kSceSifCheckStatRpc = 0x00282bc8u;
    constexpr uint32_t kSceSifSendCmd = 0x00281F40u;
    constexpr uint32_t kSifCmdSetSreg = 0x80000001u; // ps2sdk SIF_CMD_SET_SREG, packet+16 index, packet+20 value

    // t_SifRpcClientData: 16-byte header, then command, buf, cbuf, end_function, end_param, server.
    constexpr uint32_t kClientBodyOffset = 0x10u;
    constexpr uint32_t kClientBodySize = 0x18u;
    constexpr uint32_t kClientServerOffset = 0x24u;
    constexpr uint32_t kMaxReplySize = 0x1000u;
    constexpr uint32_t kSoundFrameCall = 0x100u; // FUN_002232a0, once per pass of the main loop (FUN_001969f8)

    // The same driver is the game's disc loader. FUN_002155d0 sends call 0x200 with (sector, EE destination,
    // size, mode) in the 4 send words. Sectors count from the start of TEKKEN/DATA.BIN (file table at 0x314360:
    // sector, size, checksum, key; with that base every checksum matches). When the read is done the driver
    // triggers callback 0x229328, which does done_flag += 1 at gp-0x5148 = 0x35a128; the loader polls that flag
    // (FUN_002297b0), decrypts the first 4 KB (~word + key) and checks the file's checksum.
    constexpr uint32_t kDiscReadCall = 0x200u;
    constexpr uint32_t kDiscReadDoneFlag = 0x0035a128u;
    // Where TEKKEN/DATA.BIN sits on this disc (ISO9660 directory of SCES-50878 v2.00).
    constexpr uint64_t kDataBinLbn = 1236u;
    constexpr uint64_t kDataBinSize = 2694412288u;
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

    // Movies (player FUN_00228520). Call 0x3000 (sector, size, file, mode) opens a movie file; each 0x3200
    // (EE destination, sectors) then asks for the next sectors of its video, into a ring the player decodes with
    // libmpeg. The files interleave 0x27 sectors of MPEG-2 video with 2 sectors of SPU ADPCM audio, which the
    // driver keeps (PCSX2's ring holds the video units back to back). The driver answers with SIF command 4,
    // whose handler 0x229350 stores the byte count at gp-0x5144 = 0x35a12c; the player sets it to -1 before
    // asking (FUN_00229108). Call 0x3100 closes the stream. Mode 1 (0x10000-byte requests) is not verified yet.
    constexpr uint32_t kMovieOpenCall = 0x3000u;
    constexpr uint32_t kMovieReadCall = 0x3200u;
    constexpr uint32_t kMovieCloseCall = 0x3100u;
    constexpr uint32_t kMovieReadResult = 0x0035a12cu;
    constexpr uint32_t kMovieVideoBytes = 0x27u * 2048u; // per interleave unit
    constexpr uint32_t kMovieAudioBytes = 2u * 2048u;
    // The driver's per-frame reply (call 0x100, word 3) carries the movie stream's status: 0x200 = its audio is
    // ready (FUN_00229040; the player starts the sound and the picture display only then), 0x100 = the stream has
    // ended (FUN_00229030).
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

    // One interleave unit is 74.7 ms of 48 kHz stereo (128 block pairs x 28 samples). Queued onto the mixer
    // clock, so a read-ahead ring plays out in guest time instead of as a burst.
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
        ps2PushMoviePcm(pcm.data(), kFrames);
        if (g_movieAudioUnits++ == 0u)
            RUNTIME_LOG("[tekken4] movie audio: unit " << unit << " -> " << kFrames << " stereo frames\n");
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
        // sceSifRegisterRpc yet. This ELF spins at 0x2230f0 until client.server != 0, and the module
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

    // First unique 0x100 send buffers (byte queue, terminator 0xF0). Capped so a per-frame keepalive does not
    // flood the log or move the fight fps comparison.
    void logSoundQueue(uint8_t *rdram, uint32_t sendAddr, uint32_t sendSize)
    {
        static int logs = 0;
        static uint8_t prev[128]{};
        static uint32_t prevSize = 0;
        if (logs >= 24 || sendSize == 0u || sendSize > sizeof(prev))
            return;
        const uint8_t *send = getMemPtr(rdram, sendAddr);
        if (!send)
            return;
        if (prevSize == sendSize && std::memcmp(prev, send, sendSize) == 0)
            return;
        std::memcpy(prev, send, sendSize);
        prevSize = sendSize;
        ++logs;
        std::ostringstream out;
        out << "[tekken4] rpc 0x100 send";
        for (uint32_t i = 0; i < sendSize; ++i)
        {
            if (send[i] == 0xF0u)
            {
                out << " F0";
                break;
            }
            if (i >= 48u)
            {
                out << " ...";
                break;
            }
            out << ' ' << std::hex << std::setw(2) << std::setfill('0') << static_cast<unsigned>(send[i]);
        }
        RUNTIME_LOG(out.str() << "\n");
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
            if (function == kSoundFrameCall)
                logSoundQueue(rdram, getRegU32(ctx, 7), getRegU32(ctx, 8));
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
            g_movieSize = 0u;
            g_movieAudioUnits = 0u;
            ps2ClearMoviePcm();
        }
        else if (function == kSoundFrameCall && g_movieSize != 0u && replySize >= 16u)
        {
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

    // The recompiled sceSifSendCmd ends in ps2_syscalls::sceSifSendCmd, which copies an extra payload and
    // returns 1. It does not store SIF_CMD_SET_SREG. zsiopdrv's init (handler 0x4c6b4) spins on
    // sceSifGetSreg(31) until that store is non-zero. The game writes index 31 = 1 at 0x229608, before the bind.
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
        const uint8_t *s = rdram + 0x1cda2c0u;
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
        const uint8_t *s = rdram + 0x1cda2c0u;
        int32_t pending = 0;
        std::memcpy(&pending, s + 4, 4);
        if (!dumped && cause == 1u && s[2] == 2u && pending == 0 && s[3] == 1u)
        {
            dumped = true;
            std::ofstream("ring_early_end.bin", std::ios::binary).write(reinterpret_cast<const char *>(rdram + 0x100000u), 0x10000);
            RUNTIME_LOG("[tekken4] path 1 ended before frame end: ring saved to ring_early_end.bin\n");
        }
    }

    // The game's "close DMA tag" of its VIF packet library (0x292900, not recognised as an SDK function, so it runs
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

    // The game's libc rand (0x2a3178). The recompiler maps it by name to the runtime's stub, which returns the host's
    // std::rand(); the game's srand (0x2a3168) is not stubbed and seeds the guest state, which that stub never reads.
    // The host generator was therefore never seeded: every run drew the same numbers and the CPU picked the same
    // opponents (arcade always Law, story always Steve) where PCSX2 varies. This is the game's own routine:
    // next = next * 1103515245 + 12345 on the 32-bit word at reent + 88 (reent = *0x3059d4), result next & 0x7fffffff.
    constexpr uint32_t kRand = 0x002a3178u;
    constexpr uint32_t kReentPtr = 0x003059d4u;
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

    // Around the open-CNT (0x292970) and sceGifPkCloseGifTag (0x292b28): pk words and the scratchpad qwords.
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
        FUN_00292970_0x292970(rdram, ctx, runtime);
        if (log)
            logPk("open CNT", rdram, pk, "after");
    }
    void closeGifLogged(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        const uint32_t pk = getRegU32(ctx, 4);
        const bool log = g_frames >= 4 && g_pkLogLeft.fetch_sub(1) > 0;
        if (log)
            logPk("close GIF", rdram, pk, "before");
        sceGifPkCloseGifTag_0x292b28(rdram, ctx, runtime);
        if (log)
            logPk("close GIF", rdram, pk, "after ");
    }

    void vif1EndLogged(uint8_t *r, R5900Context *c, PS2Runtime *p) { logged<FUN_00233430_0x233430>("VIF1 end handler", r, c, p); }
    void gifEndLogged(uint8_t *r, R5900Context *c, PS2Runtime *p) { logged<FUN_00233548_0x233548>("GIF end handler ", r, c, p); }
    void frameStartLogged(uint8_t *r, R5900Context *c, PS2Runtime *p) { logged<FUN_00232d20_0x232d20>("frame start     ", r, c, p); }
    void frameEndLogged(uint8_t *r, R5900Context *c, PS2Runtime *p) { logged<FUN_00233a38_0x233a38>("frame end (+1)  ", r, c, p); }

    // Movie pictures. libmpeg's sceMpegGetPicture calls the player's "no data" callback (sceMpegCbNodata,
    // 0x2281d0) whenever the IPU runs out of bitstream. The callback pumps the disc stream (FUN_00229108), takes the
    // previous chunk out of the movie ring and points a toIPU DMA (channel 4, chain mode, one REFE tag at
    // 0x1ccd2b0) at the next 0x9c00 bytes. The runtime's decoder takes bitstream from sceMpegAddBs or PSS demuxing
    // and never calls that callback, so GetPicture waited forever. Here GetPicture first runs the callback the way
    // libmpeg would, hands each transfer it starts to sceMpegAddBs and stops the channel as if the IPU had taken
    // it, until a picture is decoded.
    constexpr uint32_t kSceMpegGetPicture = 0x0028bb40u;
    constexpr uint32_t kMovieNodataCallback = 0x002281d0u;
    constexpr uint32_t kMovieIpuTag = 0x01ccd2b0u;
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

    // Animated IPU images (the character select's background, the attract loop). FUN_002277d0 sets up one job per
    // image of an image file at 0x1ccd200 (0x54 bytes each: +0x2c/+0x30 size in macroblocks, +0x38 RGB32 output,
    // +0x3c frame table, +0x40 position, +0x44 frames << 8, +0x48 speed, +0x4c/+0x50 current frame data and size).
    // Every frame FUN_00227be8(step) advances each animation and has the IPU decode the current frames (FDEC the
    // flags byte, IDEC through toIPU/fromIPU DMA; the channel-3 handler 0x227cf8 starts the next image), and
    // FUN_00227eb0 spins until 0x1ccd18c reaches -1. The runtime has no IPU: decode the frames here instead.
    constexpr uint32_t kIpuImagesDecode = 0x00227be8u;
    constexpr uint32_t kIpuJobs = 0x01ccd200u;
    constexpr uint32_t kIpuJobSize = 0x54u;
    constexpr uint32_t kIpuActive = 0x01ccd184u;
    constexpr uint32_t kIpuCount = 0x01ccd188u;
    constexpr uint32_t kIpuPending = 0x01ccd18cu;
    constexpr uint32_t kIpuStage = 0x01ccd198u;
    constexpr uint32_t kIpuFormat = 0x01ccd1acu; // 0 RGB32, 1 RGB16, 2 RGB16 dithered (IDEC OFM/DTE)

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
        setGuest32(rdram, kIpuPending, -1); // all decoded: FUN_00227eb0 returns at once
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
        const int32_t before = w(0x01ccd2c0u);
        FUN_00228520_0x228520(rdram, ctx, runtime);
        if (before >= 3 && before <= 6 && g_movieLogLeft.fetch_sub(1) > 0)
            RUNTIME_LOG("[tekken4] movie player state " << before << " -> " << w(0x01ccd2c0u) << ": frame " << w(0x01ccd2d8u)
                                                       << " shown " << w(0x01ccd364u) << " bufs " << w(0x01ccd3a4u)
                                                       << " a120 " << w(0x0035a120u) << " end35c " << w(0x01ccd35cu)
                                                       << " exit358 " << w(0x01ccd358u) << " pad " << std::hex
                                                       << w(0x00358754u) << std::dec << " skipflag " << w(0x00359f68u)
                                                       << " mode2c4 " << w(0x01ccd2c4u) << " wait38c " << w(0x01ccd38cu)
                                                       << " buffered " << w(0x01ccd3d8u) << "\n");
    }

    void apply(PS2Runtime &runtime)
    {
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
        runtime.registerFunction(0x00292900u, closeDmaTag);
        // The VIF1 packet builder's close (same code, other copy): FUN_002344e0's texture-flush CNT came out qwc 4
        // instead of 2, VIF1 then read the next REF tags as data and the fight stalled ~4 s in (found by Grok, task
        // cnt-qwc).
        runtime.registerFunction(0x00292c18u, closeDmaTag);
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
        if (const char *movieLog = std::getenv("TEKKEN4_MOVIE_LOG"))
        {
            g_movieLogLeft = std::atoi(movieLog);
            runtime.registerFunction(0x00228520u, moviePlayerLogged);
        }
        if (const char *irqLog = std::getenv("TEKKEN4_IRQ_LOG"))
        {
            g_irqLogLeft = std::atoi(irqLog);
            runtime.registerFunction(0x00233430u, vif1EndLogged);
            runtime.registerFunction(0x00233548u, gifEndLogged);
            runtime.registerFunction(0x00232d20u, frameStartLogged);
            runtime.registerFunction(0x00233a38u, frameEndLogged);
            runtime.registerFunction(0x00292900u, closeTagLogged);
            runtime.registerFunction(0x00292970u, openCntLogged);
            runtime.registerFunction(0x00292b28u, closeGifLogged);
        }
        if (const char *watch = std::getenv("TEKKEN4_WATCH_MS"))
        {
            // Debug aid for stalls: after the delay, log the MFIFO ring state (struct from FUN_00232c20:
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
                        std::memcpy(&w, rdram + 0x1cda2c0u + off, 4);
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

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 (SCES-50878 v2.00)", "SCES_508.78", 0x00180088u, 0xBEFFF97Au, tekken4::apply)
