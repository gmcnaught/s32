"""tools/v60x/exposure.py against a hand-written trace.

Run from the repository root:  python -m unittest verif/v60x/test_exposure.py
"""
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'tools', 'v60x'))
import exposure  # noqa: E402

# pc, opcode, second byte -- six instructions a game might run.
TRACE = """\
00100000 2d 68     MOV.W       executes
00100007 84 61     ADD.W       executes
0010000a 5b 08     MOVBS       5B-08: bit string, decoded and not executed
0010000d 5c 18     ADDF        5C-18: floating point arithmetic, not executed
00100010 f7 67     GETPSW      executes
00100012 6b 05     Bcc         6B: the never-taken branch, a control transfer
00100014 zz zz     a line the bench did not finish; skipped
"""


class ExposureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.t = exposure.load_table()
        decode, cls.executed = exposure.build_decoder(cls.t)
        cls.decode = staticmethod(decode)

    def test_plain_opcodes_decode_by_their_byte(self):
        self.assertEqual(self.decode(0x2D, 0x68), 'MOV.W')
        self.assertEqual(self.decode(0x84, 0x61), 'ADD')
        self.assertEqual(self.decode(0xF7, 0x67), 'GETPSW')
        self.assertEqual(self.decode(0x6B, 0x05), 'Bcc')

    def test_escape_opcodes_decode_by_the_second_bytes_low_five_bits(self):
        self.assertEqual(self.decode(0x5B, 0x08), 'MOVBS')
        self.assertEqual(self.decode(0x5C, 0x18), 'ADDF')
        self.assertEqual(self.decode(0x5C, 0x08), 'MOVF')

    def test_a_byte_the_table_does_not_name_is_a_question_mark(self):
        self.assertEqual(self.decode(0x58, 0x1F), '?')

    def test_the_clean_room_set_is_the_tables(self):
        self.assertIn('MOV.W', self.executed)
        self.assertIn('MOVF', self.executed)
        self.assertNotIn('MOVBS', self.executed)
        self.assertNotIn('ADDF', self.executed)
        self.assertEqual(len(self.executed), 93)

    def test_report_counts_and_coverage(self):
        counts = exposure.count(io.StringIO(TRACE), self.decode)
        self.assertEqual(sum(counts.values()), 6)
        out = io.StringIO()
        total, covered, missing = exposure.report(counts, self.executed, out)
        self.assertEqual((total, covered), (6, 4))
        self.assertEqual([m for m, n in missing], ['MOVBS', 'ADDF'])
        self.assertIn('66.67%', out.getvalue())


if __name__ == '__main__':
    unittest.main()
