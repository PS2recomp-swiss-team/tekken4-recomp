// Synthetic RAM only. No ELF, game assets, renderer or network required.
#include "../runtime/tekken4_native_names.h"
#include <cassert>
#include <iostream>
#include <limits>
#include <vector>

using namespace tekken4_names;

int main()
{
    assert(sanitize("Alice_rb-09.%_!") == "Alice_rb-09.%_!");
    assert(sanitize("") == "");
    assert(sanitize("abcdefghijklmnopQ") == "abcdefghijklmnop");
    assert(sanitize("Zo\xc3\xab \xe4\xb8\xad \xf0\x9f\x98\x80") == "Zo? ? ?");
    assert(sanitize(std::string("a\0b\n\x7f", 5)) == "a?b??");
    assert(sanitize("\xc0\xaf\xed\xa0\x80\xf4\x90\x80\x80") == "?????????");
    assert(sanitize("\xe2\x82") == "??");
    assert(sanitize("123456789012345\xf0\x9f\x98\x80") == "123456789012345?");
    assert(asciiFromWide(L"Zo\u00eb|Guest_9") == "Zo?|Guest_9");
    const wchar_t pair[] = {0xd83d, 0xde00, L'|', L'B'};
    assert(asciiFromWide(std::wstring_view(pair, 4)) == "?|B");
    assert(parse(nullptr, nullptr).names[0].empty());
    assert(!parse("Alice", nullptr).enabled());
    assert(!parse("A|B|C", nullptr).enabled());
    assert(!parse("A|B", "0").enabled());
    assert(!parse("|", nullptr).enabled());
    assert(parse("|Guest", "1").names[1] == "Guest");

    // There is deliberately no host/join/local-slot argument. Both PCs receive the launcher's P1|P2 order.
    const auto host = parse("Alice|Bob", "1"), join = parse("Alice|Bob", nullptr);
    assert(host.names == join.names);
    assert(fightSide(0x1f1b94) == 0 && fightSide(0x1f1bd8) == 1);
    assert(fightSide(0x1f1b90) == -1 && fightSide(0) == -1);
    assert(selectSide(0x1f507c, kSelectNameObject) == 0);
    assert(selectSide(0x1f507c, kSelectNameObject + kSelectStride) == 1);
    assert(selectSide(0x1f507c, kSelectNameObject + 1) == -1);
    assert(selectSide(0x1f5078, kSelectNameObject) == -1);
    assert(selectWidgetSide(0x27ef78, 0, 0x104) == 0);
    assert(selectWidgetSide(0x27ef78, 1, 0x105) == 1);
    assert(selectWidgetSide(0x27ef74, 0, 0x104) == -1);
    assert(selectWidgetSide(0x27ef78, 0, 0x105) == -1);
    assert(selectWidgetSide(0x27ef78, 2, 0x106) == -1);
    std::array<float, 16> matrix{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -216, 5, -297, 1};
    int cx = -1, cy = -1;
    assert(selectWidgetCentre(matrix, cx, cy) && cx == 104 && cy == 219);
    matrix[12] = 216;
    assert(selectWidgetCentre(matrix, cx, cy) && cx == 536 && cy == 219);
    const auto validMatrix = matrix;
    // Unsupported transforms/coordinates must fall back, without changing output positions.
    for (size_t index : {size_t{0}, size_t{1}, size_t{14}, size_t{15}})
    {
        matrix = validMatrix;
        matrix[index] += 0.5f;
        assert(!selectWidgetCentre(matrix, cx, cy) && cx == 536 && cy == 219);
    }
    matrix = validMatrix;
    matrix[12] = 321;
    assert(!selectWidgetCentre(matrix, cx, cy));
    matrix = validMatrix;
    matrix[13] = 225;
    assert(!selectWidgetCentre(matrix, cx, cy));
    matrix = validMatrix;
    matrix[12] = std::numeric_limits<float>::infinity();
    assert(!selectWidgetCentre(matrix, cx, cy));
    matrix = validMatrix;
    matrix[13] = std::numeric_limits<float>::quiet_NaN();
    assert(!selectWidgetCentre(matrix, cx, cy));
    // A mirror's fighter/name texture id is irrelevant: caller and per-side object still distinguish sides.
    assert(host.names[static_cast<size_t>(selectSide(0x1f507c, kSelectNameObject))] == "Alice");
    assert(join.names[static_cast<size_t>(selectSide(0x1f507c, kSelectNameObject + kSelectStride))] == "Bob");
    assert(fingerprint(123, host) == fingerprint(123, join));
    assert(fingerprint(123, host) != fingerprint(123, parse("Bob|Alice", "1")));
    assert(fingerprint(123, host) != fingerprint(123, parse("Alice|Bob", "0")));
    assert(fingerprint(123, host) != fingerprint(124, host));
    assert(fingerprint(0, host) != 0); // AUTO_VS=0 still checks the name contract
    assert(fingerprint(0, parse("A|B", "0")) == fingerprint(0, parse("X|Y", "0")));
    assert(fingerprint(0, parse("Zo\xc3\xab|B", nullptr)) == fingerprint(0, parse("Zo?|B", nullptr)));

    std::vector<uint8_t> ram(0x2000000, 0xa5);
    constexpr uint32_t metrics = 0x200000; // artificial, deliberately not the game's width data
    write<uint32_t>(ram.data(), kFontDescriptor, metrics);
    std::fill(ram.begin() + metrics, ram.begin() + metrics + 256, uint8_t{8});
    ram[metrics + 'W'] = 17;
    const auto text = fit(ram.data(), host.names[0]);
    assert(text.name == "Alice" && text.width == 40);
    assert(fit(ram.data(), std::string(16, 'W')).name == std::string(6, 'W'));
    assert(fit(ram.data(), std::string(16, 'a')).name == std::string(13, 'a'));
    ram[metrics + 'a'] = 0xff;
    assert(fit(ram.data(), "a").name.empty());
    write<uint32_t>(ram.data(), kFontDescriptor, 0xfffffff0);
    assert(fit(ram.data(), "A").name.empty());
    write<uint32_t>(ram.data(), kFontDescriptor, metrics);

    {
        // The real VS select uses PS2D node IDs and a different caller from the legacy 3D select.
        assert(selectNodeSide(0x27ef78, 0, 0x104) == 0);
        assert(selectNodeSide(0x27ef78, 1, 0x105) == 1);
        assert(selectNodeSide(0x27ef00, 0, 0xc9) == -1); // portrait draw must remain intact
        assert(selectNodeSide(0x27ef78, 0, 0x105) == -1);
        assert(selectNodeSide(0x27ef78, 2, 0x106) == -1);
        constexpr uint32_t node = 0x210000u, projection = 0x1cd7e20u;
        write<uint32_t>(ram.data(), node, 0);
        write<uint16_t>(ram.data(), node + 0x52, 1);
        write<uint32_t>(ram.data(), node + 0x58, 0);
        const float rows[8] = {1, 0, 0, -1, 0, 0, 2048, 2048};
        for (uint32_t col = 0; col < 4; ++col)
            for (uint32_t row = 0; row < 2; ++row)
                write<float>(ram.data(), projection + col * 16 + row * 4, rows[col * 2 + row]);
        write<float>(ram.data(), node + 0x40, -216.0f);
        write<float>(ram.data(), node + 0x44, 5.0f);
        write<float>(ram.data(), node + 0x5c, 1.0f);
        int nodeCx = 0, nodeCy = 0;
        uint8_t alpha = 0;
        assert(selectNodeAnchor(ram.data(), node, nodeCx, nodeCy, alpha) && nodeCx == 104 && nodeCy == 219 && alpha == 128);
        write<float>(ram.data(), node + 0x40, 216.0f);
        write<float>(ram.data(), node + 0x44, 9.0f);
        write<float>(ram.data(), node + 0x5c, 0.5f);
        assert(selectNodeAnchor(ram.data(), node, nodeCx, nodeCy, alpha) && nodeCx == 536 && nodeCy == 215 && alpha == 64);
        write<uint16_t>(ram.data(), node + 0x52, 0);
        assert(!selectNodeAnchor(ram.data(), node, nodeCx, nodeCy, alpha));
        write<uint16_t>(ram.data(), node + 0x52, 1);
        write<uint32_t>(ram.data(), node + 0x58, 1);
        assert(!selectNodeAnchor(ram.data(), node, nodeCx, nodeCy, alpha));
        write<uint32_t>(ram.data(), node + 0x58, 0);
        write<float>(ram.data(), projection, 2.0f);
        assert(!selectNodeAnchor(ram.data(), node, nodeCx, nodeCy, alpha));
        assert(!selectNodeAnchor(ram.data(), 0xfffffff0u, nodeCx, nodeCy, alpha));
    }

    const uint32_t start = kQueue + 8;
    write<uint32_t>(ram.data(), kQueue, start);
    assert(enqueue(ram.data(), text, 66, 48, 128));
    const uint32_t next = read32(ram.data(), kQueue);
    assert(next == start + 18 && ram[start] == 9 && ram[start + 1] == 0);
    assert(ram[start + 2] == 66 && ram[start + 4] == 48);
    assert(ram[start + 6] == 0xff && ram[start + 7] == 0xff);
    uint16_t depth = 0;
    std::memcpy(&depth, ram.data() + start + 6, sizeof(depth));
    const uint32_t glyphZ = static_cast<uint32_t>(static_cast<int32_t>(static_cast<int16_t>(depth)) * 16);
    assert((glyphZ & 0x00ffffffu) == (0x0ffffff0u & 0x00ffffffu)); // original name Z, GS Z24
    assert(ram[start + 8] == 6 && ram[start + 9] == 7 && ram[start + 10] == 128);
    assert(std::strcmp(reinterpret_cast<const char *>(ram.data() + start + 11), "Alice") == 0);
    assert(ram[start + 17] == 0 && ram[next] == 0 && ram[next + 1] == 0);
    assert(read32(ram.data(), kTextCursor) == start + 17);
    assert(enqueue(ram.data(), fit(ram.data(), "100%"), -2, 48, 64)); // '%' is literal, no format injection
    const auto after = ram;
    // Restoring guest RAM restores all state needed to make exactly the same writes during rollback.
    write<uint32_t>(ram.data(), kQueue, next);
    assert(enqueue(ram.data(), fit(ram.data(), "100%"), -2, 48, 64));
    assert(ram == after);
    assert(!enqueue(ram.data(), Text{}, 0, 0, 128));
    assert(!enqueue(ram.data(), text, 32768, 0, 128));
    write<uint32_t>(ram.data(), kQueue, kQueueEnd - 8);
    const auto full = ram;
    assert(!enqueue(ram.data(), text, 0, 0, 128) && ram == full);
    write<uint32_t>(ram.data(), kQueue, start + 1);
    assert(!enqueue(ram.data(), text, 0, 0, 128));
    std::cout << "native names: sanitizer, sides, contract, metrics and queue all passed\n";
}
