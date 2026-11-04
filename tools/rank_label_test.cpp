// Tests the production host-only label loader with synthetic pixels and optional
// locally installed US ELF data. No game pixels or metric tables are embedded.
#include "../runtime/tekken4_rank_label.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <iterator>

namespace
{
    constexpr uint32_t descriptor = 0x2bd100, metrics = 0x400000;
    constexpr uint32_t source = 0x500000, palette = 0x600000, indices = 0x700000;

    template <typename T> void put(std::vector<uint8_t> &ram, uint32_t address, T value)
    {
        std::memcpy(ram.data() + address, &value, sizeof(value));
    }

    std::vector<uint8_t> fixture()
    {
        std::vector<uint8_t> ram(32 * 1024 * 1024);
        for (const auto &entry : std::vector<std::pair<uint32_t, uint32_t>>{
                 {0x18, 5}, {0x1c, 20}, {0x20, 200}, {0x24, source}, {0x28, palette}, {0x2c, indices}})
            put(ram, descriptor + entry.first, entry.second);
        put(ram, 0x31f208, metrics);
        for (uint32_t c = 32; c <= 126; ++c)
            ram[metrics + c] = 6;
        ram[metrics + 'A'] = 4;
        ram[metrics + 0x100 + 'A'] = static_cast<uint8_t>(-1);
        ram[metrics + 0x100 + 'g'] = 1;
        put<uint16_t>(ram, indices + ('A' - 32) * 2, 3);
        put<uint16_t>(ram, indices + ('g' - 32) * 2, 7);
        put<uint32_t>(ram, palette + 4, 0x40112233);
        put<uint32_t>(ram, palette + 8, 0x80556677);
        put<uint32_t>(ram, palette + 12, 0xff99aabb);
        ram[source + 3 * 200 + 1 * 10] = 0x01;     // A: x0/y1, low nibble
        ram[source + 3 * 200 + 2 * 10] = 0x20;     // A: x1/y2, high nibble
        ram[source + 7 * 200 + 0 * 10 + 1] = 0x03; // g: x2/y0, glyph indirection
        return ram;
    }

    Color pixel(int x, int y) { return test_raylib::uploaded[static_cast<size_t>(y) * test_raylib::width + x]; }
    void colour(Color actual, Color expected) { assert(std::memcmp(&actual, &expected, sizeof(Color)) == 0); }

    void synthetic()
    {
        auto ram = fixture();
        const auto before = ram;
        const auto label = tekken4_rank_label::load(ram.data(), "Ag");
        assert(label.texture.id && label.width == 10);
        assert(test_raylib::width == 30 && test_raylib::height == 20);
        colour(pixel(10, 0), Color{0x33, 0x22, 0x11, 127});
        colour(pixel(11, 1), Color{0x77, 0x66, 0x55, 255});
        colour(pixel(16, 1), Color{0xbb, 0xaa, 0x99, 255});
        colour(pixel(9, 0), Color{0, 0, 0, 0});
        colour(pixel(10, 1), Color{0, 0, 0, 0});
        assert(ram == before);

        PS2Runtime runtime(ram.data());
        assert(!tekken4_rank_label::draw(runtime, "Ag", 100, 50, 2, 3, 64, 19));
        assert(test_raylib::draws == 0);
        assert(tekken4_rank_label::draw(runtime, "Ag", 100, 50, 2, 3, 64, 20));
        assert(test_raylib::draws == 1);
        assert(test_raylib::target.x == 80 && test_raylib::target.y == 50);
        assert(test_raylib::target.width == 60 && test_raylib::target.height == 60);
        assert(test_raylib::tint.a == 127);
        assert(!tekken4_rank_label::draw(runtime, "Ag", 100, 50, 2, 3, 0, 20));
        assert(!tekken4_rank_label::draw(runtime, nullptr, 100, 50, 2, 3, 128, 20));
        assert(ram == before);

        for (const auto &change : std::vector<std::pair<uint32_t, uint32_t>>{
                 {descriptor + 0x18, 6}, {descriptor + 0x1c, 21}, {descriptor + 0x20, 199},
                 {descriptor + 0x24, 0x1ffffff}, {descriptor + 0x28, 0x1fffff0},
                 {descriptor + 0x2c, 0}, {0x31f208, 0x1fffff0}})
        {
            ram = before;
            put(ram, change.first, change.second);
            const auto invalidBefore = ram;
            assert(!tekken4_rank_label::load(ram.data(), "Ag").texture.id);
            assert(ram == invalidBefore);
        }
        ram = before;
        put<uint16_t>(ram, indices + ('A' - 32) * 2, 192);
        assert(!tekken4_rank_label::load(ram.data(), "Ag").texture.id);
        ram = before;
        ram[metrics + 'A'] = 0;
        assert(!tekken4_rank_label::load(ram.data(), "Ag").texture.id);
        ram = before;
        ram[metrics + 0x100 + 'A'] = 21;
        assert(!tekken4_rank_label::load(ram.data(), "Ag").texture.id);
        ram = before;
        assert(!tekken4_rank_label::load(ram.data(), "").texture.id);
        assert(!tekken4_rank_label::load(ram.data(), "\n").texture.id);
        assert(!tekken4_rank_label::load(ram.data(), std::string(33, 'A')).texture.id);
        assert(!tekken4_rank_label::load(ram.data(), " ").texture.id);
    }

    void installedElf(const char *path)
    {
        std::ifstream input(path, std::ios::binary);
        const std::vector<uint8_t> elf((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
        assert(elf.size() > 52 && std::memcmp(elf.data(), "\x7f" "ELF\x01\x01", 6) == 0);
        const auto u16 = [&elf](size_t offset) { return tekken4_rank_label::read<uint16_t>(elf.data(), static_cast<uint32_t>(offset)); };
        const auto u32 = [&elf](size_t offset) { return tekken4_rank_label::read<uint32_t>(elf.data(), static_cast<uint32_t>(offset)); };
        std::vector<uint8_t> ram(32 * 1024 * 1024);
        for (size_t i = 0; i < u16(44); ++i)
        {
            const size_t ph = u32(28) + i * u16(42);
            assert(ph + 32 <= elf.size());
            if (u32(ph) != 1) continue;
            const uint32_t offset = u32(ph + 4), address = u32(ph + 8) & 0x1ffffffu, bytes = u32(ph + 16);
            assert(offset + bytes <= elf.size() && address + bytes <= ram.size());
            std::memcpy(ram.data() + address, elf.data() + offset, bytes);
        }
        const auto before = ram;
        const uint32_t installedMetrics = tekken4_rank_label::read<uint32_t>(ram.data(), 0x31f208);
        for (const std::string name : {"Warrior", "Tekken Lord", "Beginner", "A", "g"})
        {
            int expectedWidth = 0;
            for (unsigned char c : name) expectedWidth += static_cast<int8_t>(ram[installedMetrics + c]);
            const auto label = tekken4_rank_label::load(ram.data(), name);
            assert(label.texture.id && label.width == expectedWidth);
            if (name == "A")
            {
                // Independently known native A bounds: cap starts at row 4,
                // lower rim reaches row 17; no vertical inversion or X bearing.
                bool row4 = false, row17 = false;
                for (int x = 0; x < test_raylib::width; ++x)
                {
                    assert(pixel(x, 0).a == 0 && pixel(x, 19).a == 0);
                    row4 = row4 || pixel(x, 4).a != 0;
                    row17 = row17 || pixel(x, 17).a != 0;
                }
                assert(row4 && row17);
            }
        }
        assert(ram == before);
    }
}

int main(int argc, char **argv)
{
    synthetic();
    if (argc == 2) installedElf(argv[1]);
    std::cout << "rank label tests: all passed\n";
}
