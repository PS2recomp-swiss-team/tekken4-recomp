// Call-stack sampler for the fight. Separate from tekken4_overrides.cpp (that file is the sound task).
//
// TEKKEN4_STACKPROF=<start s>:<seconds>  every ~1 ms, suspend the game thread and walk up to
// TEKKEN4_STACKPROF_DEPTH frames (default 8) with RtlLookupFunctionEntry + RtlVirtualUnwind.
// Logs top 30 leaves and, for the top 8, the top 5 caller chains of 3 frames. "user" chains skip
// ntdll/kernelbase/CRT frames so a leaf in a syscall still shows the game/runtime caller.
// The game thread is the thread that first enters FUN_0018e1e0 or FUN_00193800 (both run on the
// EE thread; FUN_00182430 is not per frame). If neither has run by the window, the oldest thread.
#include "game_overrides.h"
#include "ps2_log.h"
#include "ps2_runtime.h"
#include <ps2_recompiled_functions.h>

#ifdef _WIN32
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#define NOGDI
#define NOUSER
#include <windows.h>
#include <dbghelp.h>
#include <tlhelp32.h>
#endif

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <set>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace tekken4_profiler
{
#ifdef _WIN32
    constexpr int kMaxDepth = 32;
    constexpr uint32_t kEye = 0x0018e1e0u;
    constexpr uint32_t kLook = 0x00193800u;

    using LookupFn = decltype(&::RtlLookupFunctionEntry);
    using UnwindFn = decltype(&::RtlVirtualUnwind);

    std::atomic<HANDLE> g_gameThread{nullptr};
    LookupFn g_lookup = nullptr;
    UnwindFn g_unwind = nullptr;

    struct Sample
    {
        uint8_t n;
        DWORD64 ip[kMaxDepth];
    };

    struct Resolved
    {
        std::string name;
        std::string module;
    };

    void note(const std::string &line)
    {
        RUNTIME_LOG("[tekken4] " << line << "\n");
        std::cout.flush();
        static std::ofstream out;
        if (!out.is_open())
            out.open("stackprof.txt", std::ios::out | std::ios::trunc);
        if (out)
        {
            out << line << "\n";
            out.flush();
        }
    }

    void captureGameThread()
    {
        if (g_gameThread.load(std::memory_order_acquire))
            return;
        HANDLE h = nullptr;
        if (!DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &h,
                             THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, 0))
            return;
        HANDLE expected = nullptr;
        if (!g_gameThread.compare_exchange_strong(expected, h, std::memory_order_release, std::memory_order_relaxed))
            CloseHandle(h);
    }

    void eyeHook(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        captureGameThread();
        FUN_0018e1e0_0x18e1e0(rdram, ctx, runtime);
    }

    void lookHook(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        captureGameThread();
        FUN_00193800_0x193800(rdram, ctx, runtime);
    }

    int readU64(DWORD64 addr, DWORD64 *out)
    {
        if (addr < 0x10000ULL || addr > 0x00007FFFFFFEFFFFULL)
            return 0;
        MEMORY_BASIC_INFORMATION mbi{};
        if (VirtualQuery(reinterpret_cast<void *>(addr), &mbi, sizeof(mbi)) == 0)
            return 0;
        if (mbi.State != MEM_COMMIT || (mbi.Protect & PAGE_GUARD))
            return 0;
        const DWORD prot = mbi.Protect & 0xFFu;
        if (prot != PAGE_READONLY && prot != PAGE_READWRITE && prot != PAGE_WRITECOPY && prot != PAGE_EXECUTE_READ &&
            prot != PAGE_EXECUTE_READWRITE && prot != PAGE_EXECUTE_WRITECOPY)
            return 0;
        const DWORD64 regionEnd = reinterpret_cast<DWORD64>(mbi.BaseAddress) + mbi.RegionSize;
        if (addr > regionEnd - 8u)
            return 0;
        std::memcpy(out, reinterpret_cast<const void *>(addr), 8);
        return 1;
    }

    // Caller is suspended (or it is this thread, for the startup self-test). No heap, no locks.
    int walkBody(CONTEXT *ctx, DWORD64 *frames, int depth)
    {
        int n = 0;
        DWORD64 prevRip = 0;
        for (int i = 0; i < depth; ++i)
        {
            const DWORD64 rip = ctx->Rip;
            if (rip < 0x10000ULL || rip > 0x00007FFFFFFFFFFFULL || rip == prevRip)
                break;
            prevRip = rip;
            frames[n++] = rip;
            DWORD64 imageBase = 0;
            RUNTIME_FUNCTION *rf = g_lookup(rip, &imageBase, nullptr);
            if (!rf)
            {
                DWORD64 ret = 0;
                if (!readU64(ctx->Rsp, &ret))
                    break;
                ctx->Rip = ret;
                ctx->Rsp += 8;
            }
            else
            {
                void *handlerData = nullptr;
                DWORD64 establisher = 0;
                g_unwind(0, imageBase, rip, rf, ctx, &handlerData, &establisher, nullptr);
            }
        }
        return n;
    }

    // noinline: __try must not be inlined into a function that has C++ destructors (C2712).
    __declspec(noinline) int walkSafe(CONTEXT *ctx, DWORD64 *frames, int depth)
    {
        int n = 0;
        __try
        {
            n = walkBody(ctx, frames, depth);
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            n = -1;
        }
        return n;
    }

    __declspec(noinline) int sampleOne(HANDLE thread, DWORD64 *frames, int depth)
    {
        if (SuspendThread(thread) == static_cast<DWORD>(-1))
            return -1;
        int n = 0;
        __try
        {
            __try
            {
                alignas(16) CONTEXT ctx;
                std::memset(&ctx, 0, sizeof(ctx));
                ctx.ContextFlags = CONTEXT_FULL;
                if (GetThreadContext(thread, &ctx))
                    n = walkBody(&ctx, frames, depth);
            }
            __finally
            {
                ResumeThread(thread);
            }
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            n = 0;
        }
        return n;
    }

    bool loadUnwind()
    {
        const HMODULE ntdll = GetModuleHandleA("ntdll.dll");
        if (!ntdll)
            return false;
        g_lookup = reinterpret_cast<LookupFn>(GetProcAddress(ntdll, "RtlLookupFunctionEntry"));
        g_unwind = reinterpret_cast<UnwindFn>(GetProcAddress(ntdll, "RtlVirtualUnwind"));
        return g_lookup && g_unwind;
    }

    HANDLE pickOldestThread()
    {
        const HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
        if (snap == INVALID_HANDLE_VALUE)
            return nullptr;
        const DWORD self = GetCurrentThreadId();
        const DWORD pid = GetCurrentProcessId();
        HANDLE best = nullptr;
        uint64_t bestCreate = ~0ull;
        THREADENTRY32 entry{};
        entry.dwSize = sizeof(entry);
        for (BOOL ok = Thread32First(snap, &entry); ok; ok = Thread32Next(snap, &entry))
        {
            if (entry.th32OwnerProcessID != pid || entry.th32ThreadID == self)
                continue;
            HANDLE h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE,
                                  entry.th32ThreadID);
            if (!h)
                continue;
            FILETIME create{}, exitT{}, kernel{}, user{};
            uint64_t ticks = ~0ull;
            if (GetThreadTimes(h, &create, &exitT, &kernel, &user))
            {
                ULARGE_INTEGER u{};
                u.LowPart = create.dwLowDateTime;
                u.HighPart = create.dwHighDateTime;
                ticks = u.QuadPart;
            }
            if (ticks < bestCreate)
            {
                if (best)
                    CloseHandle(best);
                best = h;
                bestCreate = ticks;
            }
            else
                CloseHandle(h);
        }
        CloseHandle(snap);
        return best;
    }

    std::string moduleBase(DWORD64 ip)
    {
        HMODULE mod = nullptr;
        if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                                reinterpret_cast<LPCSTR>(ip), &mod) ||
            !mod)
            return {};
        char path[MAX_PATH] = {};
        if (!GetModuleFileNameA(mod, path, MAX_PATH))
            return {};
        const char *base = path;
        for (const char *p = path; *p; ++p)
            if (*p == '\\' || *p == '/')
                base = p + 1;
        std::string name(base);
        for (char &c : name)
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');
        return name;
    }

    bool systemModule(const std::string &m)
    {
        static const char *k[] = {"ntdll.dll",          "kernel32.dll",        "kernelbase.dll",
                                  "ucrtbase.dll",       "msvcp140.dll",        "msvcp140_1.dll",
                                  "msvcp140_2.dll",     "vcruntime140.dll",    "vcruntime140_1.dll",
                                  "msvcrt.dll",         "win32u.dll",          "user32.dll",
                                  "gdi32.dll",          "advapi32.dll",        "sechost.dll",
                                  "rpcrt4.dll",         "bcrypt.dll",          "bcryptprimitives.dll",
                                  "combase.dll",        "imm32.dll"};
        if (m.rfind("api-ms-win", 0) == 0)
            return true;
        for (const char *s : k)
            if (m == s)
                return true;
        return false;
    }

    std::string hexAddr(DWORD64 ip)
    {
        std::ostringstream o;
        o << "0x" << std::hex << ip;
        return o.str();
    }

    std::string pct(uint32_t n, uint32_t total)
    {
        std::ostringstream o;
        o << std::fixed << std::setprecision(1) << (total ? 100.0 * static_cast<double>(n) / static_cast<double>(total) : 0.0);
        return o.str();
    }

    std::vector<std::pair<uint32_t, std::string>> rank(const std::unordered_map<std::string, uint32_t> &m)
    {
        std::vector<std::pair<uint32_t, std::string>> v;
        v.reserve(m.size());
        for (const auto &kv : m)
            v.emplace_back(kv.second, kv.first);
        std::sort(v.begin(), v.end(), [](const auto &a, const auto &b) {
            if (a.first != b.first)
                return a.first > b.first;
            return a.second < b.second;
        });
        return v;
    }

    std::string chainOf(const Sample &s, const std::unordered_map<DWORD64, Resolved> &syms, bool user, int frames)
    {
        std::string chain;
        int got = 0;
        for (int f = 1; f < s.n && got < frames; ++f)
        {
            const auto it = syms.find(s.ip[f]);
            if (it == syms.end())
                continue;
            if (user && systemModule(it->second.module))
                continue;
            if (got)
                chain += " <- ";
            chain += it->second.name;
            ++got;
        }
        return chain.empty() ? std::string("(none)") : chain;
    }

    void addChainNames(std::set<std::string> &names, const std::string &chain)
    {
        if (chain == "(none)")
            return;
        std::string rest = chain;
        while (!rest.empty())
        {
            const size_t cut = rest.find(" <- ");
            names.insert(cut == std::string::npos ? rest : rest.substr(0, cut));
            if (cut == std::string::npos)
                break;
            rest.erase(0, cut + 4);
        }
    }

    std::string siteFor(DWORD64 ip, BOOL(WINAPI *symGetLine)(HANDLE, DWORD64, PDWORD, PIMAGEHLP_LINE64), HANDLE process)
    {
        if (!symGetLine)
            return {};
        IMAGEHLP_LINE64 line{};
        line.SizeOfStruct = sizeof(line);
        DWORD disp = 0;
        if (!symGetLine(process, ip, &disp, &line) || !line.FileName)
            return {};
        const char *base = line.FileName;
        for (const char *p = line.FileName; *p; ++p)
            if (*p == '\\' || *p == '/')
                base = p + 1;
        return std::string(base) + ":" + std::to_string(line.LineNumber);
    }

    void report(const std::vector<Sample> &samples, int depth, int suspendFail, int emptyWalk, const char *source,
                DWORD tid)
    {
        const uint32_t total = static_cast<uint32_t>(samples.size());
        note("stackprof: " + std::to_string(total) + " samples of the game thread depth " + std::to_string(depth) +
             " tid " + std::to_string(tid) + " source " + source + " suspendFail " + std::to_string(suspendFail) +
             " empty " + std::to_string(emptyWalk));
        if (!total)
            return;

        HMODULE dbghelp = LoadLibraryA("dbghelp.dll");
        using SymInitializeFn = BOOL(WINAPI *)(HANDLE, PCSTR, BOOL);
        using SymFromAddrFn = BOOL(WINAPI *)(HANDLE, DWORD64, PDWORD64, PSYMBOL_INFO);
        using SymSetOptionsFn = DWORD(WINAPI *)(DWORD);
        using SymGetLineFn = BOOL(WINAPI *)(HANDLE, DWORD64, PDWORD, PIMAGEHLP_LINE64);
        auto symInitialize = dbghelp ? reinterpret_cast<SymInitializeFn>(GetProcAddress(dbghelp, "SymInitialize")) : nullptr;
        auto symFromAddr = dbghelp ? reinterpret_cast<SymFromAddrFn>(GetProcAddress(dbghelp, "SymFromAddr")) : nullptr;
        auto symSetOptions = dbghelp ? reinterpret_cast<SymSetOptionsFn>(GetProcAddress(dbghelp, "SymSetOptions")) : nullptr;
        auto symGetLine = dbghelp ? reinterpret_cast<SymGetLineFn>(GetProcAddress(dbghelp, "SymGetLineFromAddr64")) : nullptr;
        const HANDLE process = GetCurrentProcess();
        const bool symbols = symInitialize && symFromAddr &&
                             (symSetOptions ? (symSetOptions(0x2u | 0x4u | 0x10u), true) : true) &&
                             symInitialize(process, nullptr, TRUE);

        std::unordered_map<DWORD64, Resolved> syms;
        syms.reserve(4096);
        auto resolve = [&](DWORD64 ip) -> const Resolved & {
            const auto it = syms.find(ip);
            if (it != syms.end())
                return it->second;
            Resolved r;
            r.module = moduleBase(ip);
            // Export symbols lie about size: dbghelp reports ntdll!memcpy as 30816 bytes, the gap to the
            // next export. The pdata function is 682 bytes. A name is kept only when it starts in that
            // function; otherwise the leaf is module+RVA of the pdata function so callers stay honest.
            DWORD64 imageBase = 0;
            RUNTIME_FUNCTION *rf = g_lookup ? g_lookup(ip, &imageBase, nullptr) : nullptr;
            const DWORD64 funcStart = rf && imageBase ? imageBase + rf->BeginAddress : ip;
            const DWORD64 funcEnd = rf && imageBase ? imageBase + rf->EndAddress : ip + 1;
            if (symbols)
            {
                alignas(8) char buffer[sizeof(SYMBOL_INFO) + 512] = {};
                auto *info = reinterpret_cast<SYMBOL_INFO *>(buffer);
                info->SizeOfStruct = sizeof(SYMBOL_INFO);
                info->MaxNameLen = 511;
                DWORD64 displacement = 0;
                if (symFromAddr(process, ip, &displacement, info) && info->Name[0])
                {
                    const DWORD64 symStart = info->Address;
                    // SYMFLAG_EXPORT (0x200): Size is the gap to the next export. ntdll!memcpy is reported
                    // as 30816 bytes over a 682-byte pdata function, so an export name is kept only when
                    // that export starts inside this pdata function. A PDB symbol's Size is the real
                    // function even when pdata splits it into chunks (displacement still falls inside Size).
                    const bool exportSym = (info->Flags & 0x200u) != 0;
                    const bool inFunc = rf && symStart >= funcStart && symStart < funcEnd &&
                                        displacement < (funcEnd - symStart);
                    const bool pdbCovers = !exportSym && info->Size > 0 && displacement < info->Size &&
                                           info->Size <= (1u << 20);
                    const bool tight = !rf && info->Size > 0 && info->Size <= 8192u && displacement < info->Size;
                    if (inFunc || pdbCovers || tight)
                        r.name = info->Name;
                }
            }
            if (r.name.empty() && rf && imageBase)
            {
                std::ostringstream o;
                o << (r.module.empty() ? std::string("mod") : r.module) << "+0x" << std::hex << (funcStart - imageBase);
                r.name = o.str();
            }
            if (r.name.empty())
                r.name = hexAddr(ip);
            return syms.emplace(ip, std::move(r)).first->second;
        };

        std::unordered_map<std::string, uint32_t> leaves;
        std::unordered_map<std::string, std::unordered_map<std::string, uint32_t>> rawChains, userChains;
        std::unordered_map<std::string, std::pair<DWORD64, uint32_t>> hotIp;
        std::unordered_map<DWORD64, uint32_t> ipHits;
        for (const Sample &s : samples)
            for (int f = 0; f < s.n; ++f)
                ++ipHits[s.ip[f]];
        for (const auto &kv : ipHits)
        {
            const Resolved &r = resolve(kv.first);
            auto &hot = hotIp[r.name];
            if (kv.second > hot.second)
                hot = {kv.first, kv.second};
        }
        for (const Sample &s : samples)
        {
            if (!s.n)
                continue;
            const std::string &leaf = resolve(s.ip[0]).name;
            ++leaves[leaf];
            ++rawChains[leaf][chainOf(s, syms, false, 3)];
            ++userChains[leaf][chainOf(s, syms, true, 3)];
        }

        const auto rankedLeaves = rank(leaves);
        for (size_t i = 0; i < rankedLeaves.size() && i < 30u; ++i)
            note("stackprof leaf " + pct(rankedLeaves[i].first, total) + "% " + std::to_string(rankedLeaves[i].first) +
                 "/" + std::to_string(total) + " " + rankedLeaves[i].second);
        note("stackprof note: chain is immediate caller <- its caller <- its caller; user skips ntdll/kernelbase/CRT; "
             "% is of game-thread samples");

        std::set<std::string> printed, sites;
        auto emitChains = [&](const std::string &leaf) {
            if (!printed.insert(leaf).second)
                return;
            sites.insert(leaf);
            const auto rawIt = rawChains.find(leaf);
            const auto userIt = userChains.find(leaf);
            int shown = 0;
            if (rawIt != rawChains.end())
                for (const auto &c : rank(rawIt->second))
                {
                    if (shown >= 5)
                        break;
                    addChainNames(sites, c.second);
                    note("stackprof chain " + leaf + " " + pct(c.first, total) + "% " + std::to_string(c.first) + "/" +
                         std::to_string(total) + " " + c.second);
                    ++shown;
                }
            shown = 0;
            if (userIt != userChains.end())
                for (const auto &c : rank(userIt->second))
                {
                    if (shown >= 5)
                        break;
                    addChainNames(sites, c.second);
                    note("stackprof user " + leaf + " " + pct(c.first, total) + "% " + std::to_string(c.first) + "/" +
                         std::to_string(total) + " " + c.second);
                    ++shown;
                }
        };

        for (size_t i = 0; i < rankedLeaves.size() && i < 8u; ++i)
            emitChains(rankedLeaves[i].second);
        bool sawMemcpy = false, sawMemmove = false, sawWrite = false, sawHeap = false, sawWait = false;
        for (const auto &leaf : rankedLeaves)
        {
            const bool mem = leaf.second == "memcpy";
            const bool move = leaf.second == "memmove";
            const bool wr = leaf.second.find("WriteFile") != std::string::npos;
            const bool heap = leaf.second.find("RtlAllocateHeap") != std::string::npos;
            const bool wait = leaf.second.find("NtWaitForAlertByThreadId") != std::string::npos;
            if (!(mem || move || wr || heap || wait))
                continue;
            sawMemcpy = sawMemcpy || mem;
            sawMemmove = sawMemmove || move;
            sawWrite = sawWrite || wr;
            sawHeap = sawHeap || heap;
            sawWait = sawWait || wait;
            note("stackprof focus " + pct(leaf.first, total) + "% " + std::to_string(leaf.first) + "/" +
                 std::to_string(total) + " " + leaf.second);
            emitChains(leaf.second);
        }
        if (!sawMemcpy)
            note("stackprof focus memcpy absent");
        if (!sawMemmove)
            note("stackprof focus memmove absent");
        if (!sawWrite)
            note("stackprof focus WriteFile absent");
        if (!sawHeap)
            note("stackprof focus RtlAllocateHeap absent");
        if (!sawWait)
            note("stackprof focus NtWaitForAlertByThreadId absent");

        for (const std::string &name : sites)
        {
            const auto it = hotIp.find(name);
            if (it == hotIp.end())
                continue;
            std::string where = siteFor(it->second.first, symGetLine, process);
            if (where.empty())
            {
                const auto sy = syms.find(it->second.first);
                if (sy != syms.end())
                    where = sy->second.module;
            }
            if (!where.empty())
                note("stackprof site " + name + " " + where);
        }
        note("stackprof done");
    }

    void selfTest()
    {
        alignas(16) CONTEXT ctx;
        std::memset(&ctx, 0, sizeof(ctx));
        RtlCaptureContext(&ctx);
        DWORD64 frames[8] = {};
        const int n = walkSafe(&ctx, frames, 8);
        std::ostringstream o;
        o << "stackprof self-test frames " << n;
        for (int i = 0; i < n && i < 3; ++i)
            o << " " << hexAddr(frames[i]);
        note(o.str());
    }

    void run(double start, double seconds, int depth)
    {
        if (!loadUnwind())
        {
            note("stackprof RtlLookupFunctionEntry unavailable");
            return;
        }
        selfTest();
        note("stackprof armed " + std::to_string(start) + ":" + std::to_string(seconds) + " depth " +
             std::to_string(depth));
        std::this_thread::sleep_for(std::chrono::milliseconds(static_cast<int>(start * 1000.0)));
        HANDLE thread = g_gameThread.load(std::memory_order_acquire);
        const char *source = "hook";
        if (!thread)
        {
            for (int i = 0; i < 200 && !thread; ++i)
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
                thread = g_gameThread.load(std::memory_order_acquire);
            }
        }
        if (!thread)
        {
            thread = pickOldestThread();
            source = "oldest";
        }
        if (!thread)
        {
            note("stackprof no game thread");
            return;
        }
        const DWORD tid = GetThreadId(thread);
        note("stackprof sampling tid " + std::to_string(tid) + " source " + source);
        size_t cap = static_cast<size_t>(seconds * 2000.0) + 64u;
        if (cap > 200000u)
            cap = 200000u;
        std::vector<Sample> samples;
        samples.reserve(cap);
        int suspendFail = 0, emptyWalk = 0, dropped = 0;
        const auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(static_cast<int>(seconds * 1000.0));
        while (std::chrono::steady_clock::now() < end)
        {
            Sample s{};
            const int n = sampleOne(thread, s.ip, depth);
            if (n < 0)
                ++suspendFail;
            else if (n == 0)
                ++emptyWalk;
            else if (samples.size() < cap)
            {
                s.n = static_cast<uint8_t>(n);
                samples.push_back(s);
            }
            else
                ++dropped;
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        if (dropped)
            note("stackprof dropped " + std::to_string(dropped));
        report(samples, depth, suspendFail, emptyWalk, source, tid);
    }

    void start(const char *spec)
    {
        const double startSec = std::atof(spec);
        const char *colon = std::strchr(spec, ':');
        double seconds = colon ? std::atof(colon + 1) : 10.0;
        if (seconds < 0.1)
            seconds = 0.1;
        int depth = 8;
        if (const char *env = std::getenv("TEKKEN4_STACKPROF_DEPTH"))
        {
            depth = std::atoi(env);
            if (depth < 1)
                depth = 1;
            if (depth > kMaxDepth)
                depth = kMaxDepth;
        }
        std::thread([startSec, seconds, depth]() { run(startSec, seconds, depth); }).detach();
    }
#endif

    void apply(PS2Runtime &runtime)
    {
#ifdef _WIN32
        const char *spec = std::getenv("TEKKEN4_STACKPROF");
        if (!spec || !spec[0])
            return;
        const bool eye = runtime.registerFunction(kEye, eyeHook);
        const bool look = runtime.registerFunction(kLook, lookHook);
        if (!eye || !look)
            note("stackprof hook miss eye " + std::to_string(eye ? 1 : 0) + " look " + std::to_string(look ? 1 : 0));
        start(spec);
#else
        (void)runtime;
#endif
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 stack profiler (SLUS-20328 v1.00)", "SLUS_203.28", 0x00180088u, 0xB975F704u,
                           tekken4_profiler::apply)
