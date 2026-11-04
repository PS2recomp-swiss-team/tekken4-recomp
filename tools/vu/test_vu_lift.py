"""Synthetic ISA checks for indirect-target discovery; contains no game program."""
import struct
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from vu_lift import Group, infer_jr_targets


class IndirectTargets(unittest.TestCase):
    @staticmethod
    def image(size, pairs):
        code = bytearray(struct.pack('<II', 0x8000033c, 0x000002ff) * (size // 8))
        for pc, lower, upper in pairs:
            struct.pack_into('<II', code, pc, lower, upper)
        return bytes(code)

    def test_jump_uses_its_source_register_and_discovered_entries(self):
        # IADDIU vi2,vi0,4 -> byte entry 32; vi3,vi0,6 -> 48.
        # JR vi2 and JR vi3 must not acquire one another's constants.
        code = self.image(64, [(0, 0x10020004, 0x2ff), (8, 0x10030006, 0x2ff),
                               (16, 0x48001000, 0x2ff), (24, 0x48001800, 0x2ff)])
        self.assertEqual(infer_jr_targets(code, 1, {32, 48}), {16: {32}, 24: {48}})
        self.assertEqual(infer_jr_targets(code, 1, {32}), {16: {32}})

    def test_float_literal_and_relative_assignment_are_not_targets(self):
        code = self.image(64, [(0, 0x10020004, 0x800002ff), # I-bit lower literal
                               (8, 0x10020804, 0x2ff),    # vi1+4, not vi0+4
                               (16, 0x48001000, 0x2ff)])
        self.assertEqual(infer_jr_targets(code, 1, {32}), {})

    def test_unsigned_immediate_wraps_at_unit_micro_memory_size(self):
        # 15-bit unsigned 0x7fff; multiplication by 8 and unit address mask.
        pairs = [(0, 0x11e207ff, 0x2ff), (8, 0x48001000, 0x2ff)]
        self.assertEqual(infer_jr_targets(self.image(0x4000, pairs), 1, {0x3ff8}), {8: {0x3ff8}})
        self.assertEqual(infer_jr_targets(self.image(0x1000, pairs), 0, {0xff8}), {8: {0xff8}})

    def test_entry_outside_image_is_rejected(self):
        code = self.image(32, [(0, 0x10020020, 0x2ff), (8, 0x48001000, 0x2ff)])
        self.assertEqual(infer_jr_targets(code, 1, {256}), {})

    def test_unknown_runtime_target_keeps_exact_state_handover(self):
        code = self.image(64, [(0, 0x48001000, 0x2ff), (32, 0x8000033c, 0x400002ff)])
        group = Group(1, code, {0}, {0: {32}}, 'synthetic_indirect')
        group.generate()
        emitted = '\n'.join(group.lines)
        self.assertIn('switch (jtv)', emitted)
        self.assertIn('case 0x20:', emitted)
        self.assertIn('X.bailPc = jtv;', emitted)
        self.assertIn('VuLiftAccess::exportState(*X.vu, X,', emitted)
        self.assertIn('return kVuLiftBailed;', emitted)


if __name__ == '__main__':
    unittest.main()
