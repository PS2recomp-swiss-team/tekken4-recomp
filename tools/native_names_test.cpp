// Synthetic RAM only. No ELF, game assets, renderer or network required.
#include "../runtime/tekken4_native_names.h"
#include <cassert>
#include <iostream>
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

    const uint32_t start = kQueue + 8;
    write<uint32_t>(ram.data(), kQueue, start);
    assert(enqueue(ram.data(), text, 66, 48, 128));
    const uint32_t next = read32(ram.data(), kQueue);
    assert(next == start + 18 && ram[start] == 9 && ram[start + 1] == 0);
    assert(ram[start + 2] == 66 && ram[start + 4] == 48);
    assert(ram[start + 6] == 0xf0 && ram[start + 7] == 0xff);
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
