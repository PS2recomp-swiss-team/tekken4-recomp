// Tekken 4 (SCES-50878, PAL v2.00): screenshots from the runtime's own presented frame, independent of the window.
// Window captures (tools\run_capture.ps1, PrintWindow) come back blank while the monitor is off or the game runs from
// a hidden process (Grok tasks): this writes frame_<NN>s.bmp into the working directory (the run dir) instead.
//
// TEKKEN4_FRAME_SHOTS=<s>[,<s>...]: seconds after the override is applied (program start) at which to save the latest
// latched host presentation frame (GS::copyLatchedHostPresentationFrame, RGBA8, top-down) as a 32-bit BMP.
// tools\run_capture.ps1 sets it to its -Shots list.
//
// TEKKEN4_FRAME_SHOT_POLL=1 (default off): also poll frame_req.id in the working directory about once per frame
// from this thread (not from the present path: a disk stat there hitchs on the USB project disk). The file holds
// "<id> <id>". When both numbers match and the id is new, write frame_req_<id>.bmp and then frame_req_<id>.ok.
// Timed shots are unchanged. The host never deletes the files.
#include "game_overrides.h"
#include "ps2_log.h"
#include "ps2_runtime.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace tekken4_frameshot
{
    void put16(std::ofstream &f, uint16_t v) { f.write(reinterpret_cast<const char *>(&v), 2); }
    void put32(std::ofstream &f, uint32_t v) { f.write(reinterpret_cast<const char *>(&v), 4); }

    bool writeBmp(const std::string &path, const std::vector<uint8_t> &rgba, uint32_t width, uint32_t height)
    {
        std::ofstream f(path, std::ios::binary);
        if (!f)
            return false;
        const uint32_t imageBytes = width * height * 4u;
        f.write("BM", 2);
        put32(f, 54u + imageBytes);
        put32(f, 0u);
        put32(f, 54u);
        put32(f, 40u);                                    // BITMAPINFOHEADER
        put32(f, width);
        put32(f, static_cast<uint32_t>(-static_cast<int32_t>(height))); // negative height: rows top-down
        put16(f, 1u);
        put16(f, 32u);
        put32(f, 0u); // BI_RGB
        put32(f, imageBytes);
        put32(f, 2835u);
        put32(f, 2835u);
        put32(f, 0u);
        put32(f, 0u);
        std::vector<uint8_t> bgra(imageBytes);
        for (uint32_t i = 0; i < width * height; ++i)
        {
            bgra[i * 4u + 0u] = rgba[i * 4u + 2u];
            bgra[i * 4u + 1u] = rgba[i * 4u + 1u];
            bgra[i * 4u + 2u] = rgba[i * 4u + 0u];
            bgra[i * 4u + 3u] = 0xFFu; // the PS2's 0x80-based alpha means nothing in a picture viewer
        }
        f.write(reinterpret_cast<const char *>(bgra.data()), static_cast<std::streamsize>(bgra.size()));
        return static_cast<bool>(f);
    }

    // Serve one on-demand id. False = try the same id again (no frame yet, or the bmp did not land).
    bool serveRequest(PS2Runtime *rt, uint32_t id)
    {
        std::vector<uint8_t> pixels;
        uint32_t width = 0u, height = 0u;
        if (!rt->gs().copyLatchedHostPresentationFrame(pixels, width, height) || !width || !height ||
            pixels.size() < static_cast<size_t>(width) * height * 4u)
            return false;
        char bmpName[64];
        char okName[64];
        std::snprintf(bmpName, sizeof(bmpName), "frame_req_%08u.bmp", id);
        std::snprintf(okName, sizeof(okName), "frame_req_%08u.ok", id);
        if (!writeBmp(bmpName, pixels, width, height))
            return false;
        std::ofstream ok(okName, std::ios::binary);
        if (!ok)
            return false;
        ok << "ok\n";
        if (!ok)
            return false;
        RUNTIME_LOG("[frameshot] wrote " << bmpName << " " << width << "x" << height << "\n");
        return true;
    }

    void pollRequests(PS2Runtime *rt)
    {
        uint32_t last = 0u;
        RUNTIME_LOG("[frameshot] on-demand on (TEKKEN4_FRAME_SHOT_POLL), watching frame_req.id\n");
        for (;;)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(15));
            std::ifstream in("frame_req.id");
            if (!in)
                continue;
            std::string text;
            std::getline(in, text);
            in.close(); // drop the share before the bmp write; the host overwrites this file for the next id
            unsigned a = 0u, b = 0u;
            if (std::sscanf(text.c_str(), "%u %u", &a, &b) != 2 || a == 0u || a != b || a == last)
                continue;
            if (serveRequest(rt, a))
                last = a;
        }
    }

    void apply(PS2Runtime &runtime)
    {
        const char *spec = std::getenv("TEKKEN4_FRAME_SHOTS");
        if (spec && *spec)
        {
            std::vector<double> seconds;
            std::stringstream list(spec);
            for (std::string item; std::getline(list, item, ',');)
                if (!item.empty())
                    seconds.push_back(std::atof(item.c_str()));
            RUNTIME_LOG("[frameshot] " << seconds.size() << " frame shots planned (TEKKEN4_FRAME_SHOTS)\n");
            PS2Runtime *rt = &runtime;
            std::thread([rt, seconds]() {
                const auto start = std::chrono::steady_clock::now();
                for (const double at : seconds)
                {
                    std::this_thread::sleep_until(start + std::chrono::milliseconds(static_cast<int64_t>(at * 1000.0)));
                    std::vector<uint8_t> pixels;
                    uint32_t width = 0u, height = 0u;
                    std::ostringstream name;
                    name << "frame_" << static_cast<int>(at) << "s.bmp";
                    if (rt->gs().copyLatchedHostPresentationFrame(pixels, width, height) && width && height &&
                        pixels.size() >= static_cast<size_t>(width) * height * 4u &&
                        writeBmp(name.str(), pixels, width, height))
                        RUNTIME_LOG("[frameshot] wrote " << name.str() << " " << width << "x" << height << "\n");
                    else
                        RUNTIME_LOG("[frameshot] no presented frame for " << name.str() << "\n");
                }
            }).detach();
        }
        const char *poll = std::getenv("TEKKEN4_FRAME_SHOT_POLL");
        if (poll && std::strcmp(poll, "1") == 0)
        {
            PS2Runtime *rt = &runtime;
            std::thread([rt]() { pollRequests(rt); }).detach();
        }
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 frame shots (SCES-50878 v2.00)", "SCES_508.78", 0x00180088u, 0xBEFFF97Au,
                           tekken4_frameshot::apply)
