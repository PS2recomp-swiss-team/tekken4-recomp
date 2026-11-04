"""Verify the local US executable's round-setting contract without running a game.

python -I tools/test_rounds_setting.py
The executable is local-only and is never copied into test output.
"""
from pathlib import Path
import struct
import unittest
import zlib


ROOT = Path(__file__).resolve().parent.parent


class RoundsSettingTests(unittest.TestCase):
    def test_us_round_setting_sites(self):
        elf = ROOT / "game/disc/SLUS_203.28"
        if not elf.exists():
            self.skipTest("local US ELF unavailable")
        data = elf.read_bytes()
        self.assertEqual(zlib.crc32(data), 0xB975F704)
        self.assertEqual(data[:6], b"\x7fELF\x01\x01")
        phoff = struct.unpack_from("<I", data, 28)[0]
        phentsize, phnum = struct.unpack_from("<HH", data, 42)

        def word(address):
            for i in range(phnum):
                kind, offset, virtual, _, size = struct.unpack_from(
                    "<IIIII", data, phoff + i * phentsize)
                if kind == 1 and virtual <= address <= virtual + size - 4:
                    return struct.unpack_from("<I", data, offset + address - virtual)[0]
            self.fail(f"address {address:#x} not in a file-backed LOAD segment")

        def expect(address, opcode):
            self.assertEqual(word(address), opcode, f"instruction {address:#x}")

        def call(address, target):
            expect(address, (3 << 26) | (target >> 2))

        # Options Round is stored as n-1; mode entry copies n into its match rules.
        expect(0x1E2070, 0x3C030037)  # base 0x370000
        expect(0x1E2078, 0x9062C2B9)  # u8 at 0x36c2b9
        call(0x1DD848, 0x1E2070)
        expect(0x1DD850, 0x24420001)  # +1
        expect(0x1DD858, 0xA222002B)  # 0x2a8bf8 + 0x2b

        # Match initialization invokes the setter before deriving the total-round cap.
        expect(0x198BDC, 0x90448C23)  # load actual rounds from 0x2a8c23
        call(0x198BD8, 0x197B68)
        expect(0x197B68, 0x3C020035)
        expect(0x197B70, 0xAC447D74)  # u32 rounds-to-win at 0x357d74
        expect(0x197B80, 0x8C627D74)  # same getter
        call(0x198BFC, 0x197B78)
        expect(0x198C04, 0x00021040)  # n*2
        expect(0x198C0C, 0x2444FFFF)  # n*2-1
        call(0x198C08, 0x197B88)
        expect(0x197B90, 0xAC447D78)  # total-round cap at 0x357d78
        expect(0x198C18, 0xA640008E)  # clear P1 wins only after rule setup

        # HUD's marker loop and the judge both read that same active value.
        call(0x1F0BA0, 0x197B78)
        expect(0x1F0BAC, 0x0040F02D)  # fp=n
        expect(0x1F0C00, 0x0000982D)  # marker index=0
        expect(0x1F0D90, 0x26730001)  # index++
        expect(0x1F0D94, 0x027E102A)  # index<n
        call(0x1BBF24, 0x197B78)
        expect(0x1BBF28, 0x8650008E)  # P1 wins
        expect(0x1BBF2C, 0x0202802B)  # wins<n
        call(0x1BBF38, 0x197B78)
        expect(0x1BBF3C, 0x8630008E)  # P2 wins


if __name__ == "__main__":
    unittest.main(verbosity=2)
