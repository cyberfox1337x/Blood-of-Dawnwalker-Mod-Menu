"""Check the observed zero-mask distinction without loading game assets."""
from pathlib import Path
import sys
import unittest


def cyberfox1337x(module_name):
    return module_name


cyberfox1337x("dawnwalker_creator_switch_decoder_tests")
sys.path.insert(0, str(Path(__file__).parents[1] / "probes"))
from DawnwalkerEyeCreatorSwitches import decode_switch

TRUE = bytes.fromhex("0009010007050000000000000002ffffffff012a07e224db7c854ab6aa8ab1f34a1f58")
FALSE = bytes.fromhex("8009010007050000000000000002ffffffff012a07e224db7c854ab6aa8ab1f34a1f58")


class SwitchTests(unittest.TestCase):
    def test_identical_one_byte_can_be_value_or_zero_mask(self):
        enabled, disabled = decode_switch(TRUE, 5), decode_switch(FALSE, 5)
        self.assertTrue(enabled["value"])
        self.assertFalse(disabled["value"])
        self.assertIsNone(enabled["zeroMask"])
        self.assertEqual(disabled["zeroMask"], 1)
        self.assertTrue(enabled["bOverride"] and disabled["bOverride"])
        self.assertEqual(enabled["expressionGuidBytes"], disabled["expressionGuidBytes"])

    def test_record_offset_is_preserved(self):
        decoded = decode_switch(bytes(21) + FALSE + bytes(9), 26)
        self.assertEqual(decoded["recordStartOffset"], 21)
        self.assertEqual(decoded["recordHex"], FALSE.hex())

    def test_unsupported_zero_mask_header_and_flag_refused(self):
        for offset, value in ((0, 1), (1, 7), (2, 2), (4, 9), (13, 1), (18, 2)):
            data = bytearray(FALSE)
            data[offset] = value
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                decode_switch(bytes(data), 5)

    def test_short_record_is_not_silently_decoded(self):
        with self.assertRaises(ValueError):
            decode_switch(TRUE[:-1], 5)


if __name__ == "__main__":
    unittest.main()
