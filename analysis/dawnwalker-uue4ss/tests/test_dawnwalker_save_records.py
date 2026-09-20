"""Save comparison must distinguish an inverse pair from unrelated progression."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "probes"))
from compare_dawnwalker_save_records import compare_records, cyberfox1337x  # noqa: E402

cyberfox1337x.function("dawnwalker_save_record_comparison_tests")


class SaveRecordComparisonTests(unittest.TestCase):
    def test_reports_bounded_record_relative_change_and_exact_inverse_without_claiming_semantics(self):
        baseline = {"Probe": bytes(8)}
        changed = {"Probe": bytes(4) + b"\x01\x00\x00\x00"}
        result = compare_records(baseline, changed, baseline)[0]
        self.assertEqual(result["changedRecordRelativeBytePositions"], [8])
        self.assertTrue(result["inverseRestoresOriginalBody"])
        self.assertTrue(result["bodyChanged"])
        self.assertFalse(result["semanticFieldVerified"])

    def test_flags_unrestored_record_and_variable_sized_data(self):
        result = compare_records({"Probe": b"before"}, {"Probe": b"different"}, {"Probe": b"after"})[0]
        self.assertFalse(result["sameSize"])
        self.assertFalse(result["inverseRestoresOriginalBody"])
        self.assertEqual(result["changedRecordRelativeBytePositions"], [])

    def test_refuses_unmatched_subsystems(self):
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            compare_records({"A": b"a"}, {"B": b"b"}, {"A": b"a"})


if __name__ == "__main__":
    unittest.main()
