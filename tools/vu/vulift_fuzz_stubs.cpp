// Tekken 4 port (t4vurecomp): link stubs for tools/vu/vulift_fuzz.cpp (the VU engine without the rest of the runtime;
// the fuzz runs are silent, so no GIF packet ever reaches these).
#include "runtime/ps2_memory.h"
#include "runtime/gs/gs_frontend.h"
#include <cstdlib>

void PS2Memory::submitGifPacket(GifPathId, const uint8_t *, uint32_t, bool, bool) { std::abort(); }
void GS::processGIFPacket(const uint8_t *, uint32_t) { std::abort(); }
